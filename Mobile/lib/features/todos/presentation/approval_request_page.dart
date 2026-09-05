import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/media/mobile_image_compressor.dart';
import '../../../core/media/mobile_upload_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/application/oa_catalog_sync_coordinator.dart';
import '../../collaboration/data/oa_local_store.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../domain/approval_form_calculation.dart';

// Keep the mobile form responsive when the OA service is unreachable. The
// form and draft remain usable after this deadline, and the user can retry the
// workflow preview independently.
const _workflowPreviewTimeout = Duration(seconds: 6);

class ApprovalRequestPage extends ConsumerStatefulWidget {
  const ApprovalRequestPage({
    super.key,
    required this.applicationKey,
    required this.templateId,
    this.initialTitle = '',
    this.initialFormData = const {},
    this.initialAttachments = const [],
    this.initialAttachmentIds = const [],
    this.initialAttachmentBindings = const [],
    this.sourceOutboxId,
  });

  final String applicationKey;
  final String templateId;
  final String initialTitle;
  final Map<String, Object?> initialFormData;
  final List<OaLocalAttachment> initialAttachments;
  final List<String> initialAttachmentIds;
  final List<Map<String, Object?>> initialAttachmentBindings;
  final String? sourceOutboxId;

  @override
  ConsumerState<ApprovalRequestPage> createState() =>
      _ApprovalRequestPageState();
}

class _ApprovalRequestPageState extends ConsumerState<ApprovalRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _values = <String, Object?>{};
  final _attachments = <OaLocalAttachment>[];
  final _serverFieldErrors = <String, String>{};
  final _clientFieldErrors = <String, String>{};
  final _calculationFieldErrors = <String, String>{};
  String _title = '';
  String _defaultTitle = '';
  bool _submitting = false;
  bool _validationAttempted = false;
  bool _previewing = false;
  OaWorkflowPreview? _workflowPreview;
  Object? _workflowPreviewError;
  String _workflowPreviewFingerprint = '';
  int _workflowPreviewSequence = 0;
  int _workflowRecoveryEpoch = 0;
  int _workflowPreviewRecoveryEpoch = 0;
  bool _uploadingAttachment = false;
  bool _draftLoaded = false;
  bool _draftWasRestored = false;
  bool _restoredExistingValues = false;
  bool _hasUnsavedChanges = false;
  int _draftRevision = 0;
  bool _draftSaving = false;
  bool _handlingPop = false;
  Object? _draftSaveError;
  Future<bool>? _draftSaveInFlight;
  final String _newDraftId = const Uuid().v4();
  late final String _draftAccountScope;
  bool _allowPop = false;
  DateTime? _draftSavedAt;
  OaApprovalDraft? _draft;
  Timer? _draftTimer;
  Timer? _workflowPreviewTimer;

  @override
  void initState() {
    super.initState();
    _draftAccountScope = ref.read(collaborationAccountScopeProvider);
    Future<void>.microtask(_loadDraft);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _workflowPreviewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(oaSyncAvailabilityProvider, (previous, next) {
      if (previous != OaSyncAvailability.available &&
          next == OaSyncAvailability.available) {
        _workflowRecoveryEpoch++;
        _scheduleWorkflowRecovery();
      }
    });
    final value = ref.watch(oaBootstrapProvider);
    final catalog = ref.watch(oaApplicationCatalogProvider).value;
    final directory = ref.watch(imBootstrapProvider).value;
    final departments =
        ref.watch(imDepartmentsProvider).value ?? const <ImDepartment>[];
    return value.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('发起审批')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '审批应用加载失败',
          description: mobileErrorText(error),
          onRetry: () => ref.invalidate(oaBootstrapProvider),
        ),
      ),
      data: (data) {
        if (!_draftLoaded) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final template = _findTemplate(data.templates, widget.templateId);
        if (template == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('发起审批')),
            body: const EmptyState(
              icon: Icons.rule_folder_outlined,
              title: '审批模板不可用',
              description: '该部门尚未发布可用流程，请联系管理员。',
            ),
          );
        }
        final allowOfflineDraft =
            catalog?.items
                .where((item) => item.applicationKey == widget.applicationKey)
                .firstOrNull
                ?.allowOfflineDraft ??
            false;
        final members = directory == null
            ? const <ImMember>[]
            : _uniqueMembers([directory.currentMember, ...directory.contacts]);
        return _buildForm(
          data,
          template,
          allowOfflineDraft,
          directory?.currentMember,
          members,
          departments,
        );
      },
    );
  }

  Widget _buildForm(
    OaBootstrap data,
    OaApprovalTemplate template,
    bool allowOfflineDraft,
    ImMember? requester,
    List<ImMember> members,
    List<ImDepartment> departments,
  ) {
    final fields = _parseFields(template.formSchemaJson);
    _sanitizeSchemaValues(fields);
    _applySchemaDefaults(fields, requester);
    _recalculateDerivedFields(fields);
    final defaultTitle = '${data.displayName}的${template.name}';
    _defaultTitle = defaultTitle;
    _scheduleWorkflowPreview(template);
    final pageTheme = Theme.of(context);
    final compactInputTheme = pageTheme.inputDecorationTheme.copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      filled: true,
      fillColor: const Color(0xFFF6F7F9),
      labelStyle: const TextStyle(fontSize: 12.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: pageTheme.colorScheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: pageTheme.colorScheme.error, width: 1),
      ),
    );
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop(template, allowOfflineDraft);
      },
      child: Scaffold(
        appBar: AppBar(centerTitle: true, title: Text(template.name)),
        body: AbsorbPointer(
          absorbing: _submitting || _handlingPop,
          child: Theme(
            data: pageTheme.copyWith(inputDecorationTheme: compactInputTheme),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                children: [
                  _RequesterSummary(
                    displayName: requester?.displayName.isNotEmpty == true
                        ? requester!.displayName
                        : data.displayName,
                    departmentName: requester?.departmentName ?? '',
                    avatarKey: requester?.avatarKey ?? '',
                    avatarDataUrl: requester?.avatarDataUrl ?? '',
                    templateVersion: template.version,
                    draftSavedAt: _draftSavedAt,
                    draftStatus: _draftSaveError != null
                        ? '保存失败'
                        : _draftSaving
                        ? '保存中'
                        : _hasUnsavedChanges
                        ? '未保存'
                        : _draftSavedAt == null
                        ? ''
                        : _draftWasRestored
                        ? '已恢复上次草稿'
                        : '草稿已保存',
                  ),
                  const SizedBox(height: 8),
                  MobileSurface(
                    key: const Key('approval-form-surface'),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final field in fields) ...[
                          if (field.type == 'attachment' ||
                              field.type == 'file')
                            _AttachmentEditor(
                              field: field,
                              items: _attachments
                                  .where(
                                    (item) =>
                                        item.formFieldId.isEmpty ||
                                        item.formFieldId == field.id,
                                  )
                                  .toList(),
                              uploading: _uploadingAttachment,
                              errorText:
                                  _serverFieldErrors[field.id] ??
                                  _clientFieldErrors[field.id],
                              onAdd: () => _pickAttachment(
                                field,
                                template,
                                allowOfflineDraft,
                              ),
                              onDelete: (attachment) => _deleteAttachment(
                                attachment,
                                template,
                                allowOfflineDraft,
                              ),
                              onOpen: (attachment) => _openLocalAttachment(
                                attachment,
                                allowImagePreview: field.imagePreview,
                              ),
                            )
                          else
                            _SchemaField(
                              field: field,
                              autovalidateMode: _validationAttempted
                                  ? AutovalidateMode.always
                                  : AutovalidateMode.disabled,
                              value: _values[field.id],
                              serverError:
                                  _serverFieldErrors[field.id] ??
                                  _clientFieldErrors[field.id] ??
                                  (field.type == 'datetime' ||
                                          field.type == 'date'
                                      ? _calculationFieldErrors[field.id]
                                      : null),
                              dependencyInvalid:
                                  _calculationFieldErrors.containsKey(
                                    field.durationStartFieldId,
                                  ) ||
                                  _calculationFieldErrors.containsKey(
                                    field.durationEndFieldId,
                                  ),
                              calculationError:
                                  _calculationFieldErrors[field.id],
                              members: members,
                              departments: departments,
                              onChanged: (value) {
                                setState(() {
                                  _values[field.id] = value;
                                  _serverFieldErrors.remove(field.id);
                                  _clientFieldErrors.remove(field.id);
                                  _recalculateDerivedFields(fields);
                                  if (_validationAttempted) {
                                    _clientFieldErrors
                                      ..clear()
                                      ..addAll(_validateSubmission(fields));
                                  }
                                  _markDraftChanged();
                                });
                                _scheduleDraftSave(template, allowOfflineDraft);
                                _scheduleWorkflowPreview(template);
                              },
                            ),
                          const SizedBox(height: 10),
                        ],
                        if (fields.isEmpty)
                          const EmptyState(
                            icon: Icons.description_outlined,
                            title: '当前模板没有可填写字段',
                          ),
                        if (fields.isNotEmpty) ...[
                          const Divider(height: 17),
                          ApprovalWorkflowInline(
                            preview: _workflowPreview,
                            loading: _previewing,
                            error: _workflowPreviewError,
                            templateVersion: template.version,
                            onRetry: () =>
                                _refreshWorkflowPreview(template, force: true),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Spacer(),
                if (allowOfflineDraft) ...[
                  SizedBox(
                    width: 88,
                    child: TextButton(
                      key: const Key('approval-draft-button'),
                      onPressed:
                          _submitting ||
                              _handlingPop ||
                              _draftSaving ||
                              _uploadingAttachment
                          ? null
                          : () => _saveDraft(template, showFeedback: true),
                      style: compactMobileActionStyle,
                      child: const Text('保存草稿'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                SizedBox(
                  width: 104,
                  child: FilledButton(
                    key: const Key('approval-submit-button'),
                    onPressed:
                        _submitting || _handlingPop || _uploadingAttachment
                        ? null
                        : () => _submit(
                            template,
                            fields,
                            _title.trim().isEmpty
                                ? defaultTitle
                                : _title.trim(),
                            allowOfflineDraft,
                          ),
                    style: compactMobileActionStyle,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                              semanticsLabel: '正在提交申请',
                            ),
                          )
                        : const Text('提交申请'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(
    OaApprovalTemplate template,
    List<_FieldDefinition> fields,
    String title,
    bool allowOfflineDraft,
  ) async {
    if (_submitting ||
        _handlingPop ||
        _uploadingAttachment ||
        !_ownsDraftPage) {
      return;
    }
    final clientErrors = _validateSubmission(fields);
    setState(() {
      _validationAttempted = true;
      _clientFieldErrors
        ..clear()
        ..addAll(clientErrors);
    });
    final mountedFieldsValid = _formKey.currentState?.validate() ?? true;
    if (clientErrors.isNotEmpty || !mountedFieldsValid) {
      final firstError = clientErrors.values.firstOrNull;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(firstError == null ? '请检查必填项' : '请检查：$firstError'),
          ),
        );
      return;
    }
    _draftTimer?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submitting = true);
    try {
      // A successful submission deletes the draft. Do not let an older disk
      // write finish afterwards and resurrect it, or start a duplicate submit.
      await _draftSaveInFlight;
      if (!_ownsDraftPage) return;
      final request = await ref
          .read(oaRepositoryProvider)
          .submitApproval(
            applicationKey: widget.applicationKey,
            template: template,
            title: title,
            formData: _values,
            attachmentIds: widget.initialAttachmentIds,
            attachmentBindings: widget.initialAttachmentBindings,
            pendingAttachments: _attachments,
            allowOfflineQueue: allowOfflineDraft,
          );
      if (mounted) {
        ref.read(oaCatalogSyncCoordinatorProvider).catchUpAfterMutation();
      }
      await _discardSourceOutbox();
      if (_draft != null) {
        await ref.read(oaRepositoryProvider).deleteDraft(_draft!.id);
      }
      ref.invalidate(oaBootstrapProvider);
      ref.invalidate(oaNotificationsProvider);
      ref.invalidate(oaNotificationPageProvider);
      ref.invalidate(oaDraftsProvider);
      ref.invalidate(oaOutboxProvider);
      if (mounted) context.pushReplacement('/approval/${request.id}');
    } on OaSubmissionQueuedException {
      await _discardSourceOutbox();
      if (_draft != null) {
        await ref.read(oaRepositoryProvider).deleteDraft(_draft!.id);
      }
      ref.invalidate(oaDraftsProvider);
      ref.invalidate(oaOutboxProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('网络不可用，申请已保存到待同步')));
        context.go('/todos');
      }
    } catch (error) {
      if (mounted) {
        final details = _submissionError(error);
        setState(() {
          _serverFieldErrors
            ..clear()
            ..addAll(details.fieldErrors);
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(details.displayMessage)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _discardSourceOutbox() async {
    final sourceOutboxId = widget.sourceOutboxId;
    if (sourceOutboxId == null || sourceOutboxId.isEmpty) return;
    await ref.read(oaRepositoryProvider).discardOutbox(sourceOutboxId);
  }

  void _scheduleWorkflowPreview(OaApprovalTemplate template) {
    final fingerprint = jsonEncode(_values);
    if (fingerprint == _workflowPreviewFingerprint &&
        (_previewing ||
            _workflowPreview != null ||
            _workflowPreviewError != null)) {
      return;
    }
    _workflowPreviewTimer?.cancel();
    _workflowPreviewTimer = Timer(
      const Duration(milliseconds: 350),
      () => _refreshWorkflowPreview(template),
    );
  }

  // A successful OA sync is evidence that the service is reachable again.
  // Retry only a transient failure, once per recovery, without changing input.
  // The epoch also remembers recovery while the old request is still pending.
  void _scheduleWorkflowRecovery() {
    if (!mounted ||
        _previewing ||
        _workflowRecoveryEpoch <= _workflowPreviewRecoveryEpoch ||
        !_isRecoverableWorkflowPreviewError(_workflowPreviewError)) {
      return;
    }
    _workflowPreviewTimer?.cancel();
    _workflowPreviewTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted ||
          _previewing ||
          _workflowRecoveryEpoch <= _workflowPreviewRecoveryEpoch ||
          ref.read(oaSyncAvailabilityProvider) !=
              OaSyncAvailability.available ||
          !_isRecoverableWorkflowPreviewError(_workflowPreviewError)) {
        return;
      }
      final templates = ref.read(oaBootstrapProvider).value?.templates;
      if (templates == null) return;
      final template = _findTemplate(templates, widget.templateId);
      if (template != null) {
        unawaited(_refreshWorkflowPreview(template, force: true));
      }
    });
  }

  Future<void> _refreshWorkflowPreview(
    OaApprovalTemplate template, {
    bool force = false,
  }) async {
    final fingerprint = jsonEncode(_values);
    if (!force &&
        fingerprint == _workflowPreviewFingerprint &&
        (_previewing || _workflowPreview != null)) {
      return;
    }
    final sequence = ++_workflowPreviewSequence;
    _workflowPreviewRecoveryEpoch = _workflowRecoveryEpoch;
    if (mounted) {
      setState(() {
        _previewing = true;
        _workflowPreviewFingerprint = fingerprint;
        _workflowPreviewError = null;
      });
    }
    try {
      final preview = await ref
          .read(oaWorkflowPreviewLoaderProvider)(
            applicationKey: widget.applicationKey,
            template: template,
            formData: Map<String, Object?>.from(_values),
          )
          .timeout(_workflowPreviewTimeout);
      if (mounted && sequence == _workflowPreviewSequence) {
        setState(() {
          _workflowPreview = preview;
          _workflowPreviewFingerprint = fingerprint;
          _workflowPreviewError = null;
          _previewing = false;
        });
      }
    } catch (error) {
      if (mounted && sequence == _workflowPreviewSequence) {
        setState(() {
          _workflowPreview = null;
          _workflowPreviewFingerprint = fingerprint;
          _workflowPreviewError = error;
          _previewing = false;
        });
        _scheduleWorkflowRecovery();
      }
    }
  }

  void _recalculateDerivedFields(List<_FieldDefinition> fields) {
    final durationErrors = <String, String>{};
    final fieldsById = {for (final field in fields) field.id: field};
    for (final field in fields) {
      if (field.durationUnit == null ||
          field.durationStartFieldId == null ||
          field.durationEndFieldId == null) {
        continue;
      }
      final start = DateTime.tryParse(
        _values[field.durationStartFieldId]?.toString() ?? '',
      );
      final end = DateTime.tryParse(
        _values[field.durationEndFieldId]?.toString() ?? '',
      );
      if (start == null || end == null) {
        _values.remove(field.id);
        continue;
      }
      if (!end.isAfter(start)) {
        _values.remove(field.id);
        final startLabel =
            fieldsById[field.durationStartFieldId]?.label ?? '开始时间';
        final endLabel = fieldsById[field.durationEndFieldId]?.label ?? '结束时间';
        durationErrors[field.durationEndFieldId!] =
            '“$endLabel”必须晚于“$startLabel”';
        continue;
      }
      if (field.durationUnit == 'hours') {
        _values[field.id] =
            (end.difference(start).inMinutes / 60 * 100).round() / 100;
      } else if (field.durationUnit == 'days') {
        final startDay = DateTime(start.year, start.month, start.day);
        final endDay = DateTime(end.year, end.month, end.day);
        _values[field.id] = endDay.difference(startDay).inDays + 1;
      }
    }
    final calculated = evaluateApprovalFormCalculations(
      fields: fields
          .map(
            (field) => ApprovalFormCalculationField(
              id: field.id,
              label: field.label,
              type: field.type,
              calculation: field.calculation,
            ),
          )
          .toList(growable: false),
      sourceValues: _values,
    );
    for (final field in fields.where((field) => field.calculation != null)) {
      if (calculated.values.containsKey(field.id)) {
        _values[field.id] = calculated.values[field.id];
      } else {
        _values.remove(field.id);
      }
    }
    _calculationFieldErrors
      ..clear()
      ..addAll(durationErrors)
      ..addAll(calculated.errors);
  }

  Map<String, String> _validateSubmission(List<_FieldDefinition> fields) {
    final errors = <String, String>{..._serverFieldErrors};
    for (final field in fields) {
      if (errors.containsKey(field.id)) continue;
      if (_calculationFieldErrors[field.id] case final calculationError?) {
        errors[field.id] = calculationError;
        continue;
      }
      // The editable source field owns the error; do not also ask the user to
      // repair the empty read-only duration produced by that invalid range.
      if (field.durationUnit != null &&
          (_calculationFieldErrors.containsKey(field.durationStartFieldId) ||
              _calculationFieldErrors.containsKey(field.durationEndFieldId))) {
        continue;
      }
      if (field.type == 'attachment' || field.type == 'file') {
        final itemCount = _attachments
            .where(
              (item) =>
                  item.formFieldId.isEmpty || item.formFieldId == field.id,
            )
            .length;
        if (field.required && itemCount == 0) {
          errors[field.id] = '请上传${field.label}';
        } else if (itemCount > field.maxCount) {
          errors[field.id] = '${field.label}最多保留 ${field.maxCount} 个附件';
        }
        continue;
      }
      final fieldError = field.validateValue(_values[field.id]);
      if (fieldError != null) errors[field.id] = fieldError;
    }
    return errors;
  }

  void _applySchemaDefaults(
    List<_FieldDefinition> fields,
    ImMember? requester,
  ) {
    if (_restoredExistingValues) return;
    final now = DateTime.now();
    for (final field in fields) {
      if (_values.containsKey(field.id)) continue;
      final defaultValue = field.resolveDefault(requester: requester, now: now);
      if (defaultValue != null) _values[field.id] = defaultValue;
    }
  }

  void _sanitizeSchemaValues(List<_FieldDefinition> fields) {
    for (final field in fields) {
      final value = _values[field.id];
      if (value is Map) {
        _values.remove(field.id);
        continue;
      }
      if (field.isReadOnly &&
          value is String &&
          _isSchemaConfigurationText(value)) {
        _values.remove(field.id);
        continue;
      }
      final acceptsList =
          field.type == 'multiSelect' || field.type == 'dateRange';
      if (value is Iterable && !acceptsList) {
        _values.remove(field.id);
      }
    }
  }

  bool _isSchemaConfigurationText(String value) {
    final parts = value
        .split(RegExp(r'[,，;；|、]'))
        .map((item) => item.replaceAll(RegExp(r'\s+'), '').trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return false;
    return parts.every(
          (item) =>
              item == '自动计算' ||
              item == '只读' ||
              item.startsWith('单位') ||
              item.startsWith('公式'),
        ) &&
        parts.any((item) => item == '自动计算' || item == '只读');
  }

  Future<void> _loadDraft() async {
    if (widget.initialTitle.isNotEmpty || widget.initialFormData.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _title = widget.initialTitle;
        _values
          ..clear()
          ..addAll(widget.initialFormData);
        _attachments
          ..clear()
          ..addAll(widget.initialAttachments);
        _restoredExistingValues = true;
        _draftLoaded = true;
      });
      return;
    }
    try {
      final draft = await ref.read(oaDraftLoaderProvider)(widget.templateId);
      if (!_ownsDraftPage) return;
      setState(() {
        _draft = draft;
        if (draft != null) {
          _title = draft.title;
          _values
            ..clear()
            ..addAll(draft.formData);
          _attachments
            ..clear()
            ..addAll(draft.attachments);
          _draftWasRestored = true;
          _restoredExistingValues = true;
          _draftSavedAt = draft.updatedAt;
        }
        _draftLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _draftLoaded = true);
    }
  }

  Future<void> _pickAttachment(
    _FieldDefinition field,
    OaApprovalTemplate template,
    bool allowOfflineDraft,
  ) async {
    final currentFieldItems = _attachments
        .where(
          (item) => item.formFieldId.isEmpty || item.formFieldId == field.id,
        )
        .toList(growable: false);
    final retainedCount = field.multiple
        ? _attachments.length
        : _attachments.length - currentFieldItems.length;
    if (retainedCount >= 20 ||
        (field.multiple && currentFieldItems.length >= field.maxCount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            field.multiple && currentFieldItems.length >= field.maxCount
                ? '${field.label}最多添加 ${field.maxCount} 个附件'
                : '单个申请最多添加 20 个附件',
          ),
        ),
      );
      return;
    }
    var uploading = false;
    try {
      final selected = await withMobileFileAccess(FilePicker.pickFile);
      if (selected == null || !mounted) return;
      final originalContentType = _attachmentContentType(
        path.extension(selected.name).replaceFirst('.', ''),
      );
      final sourceLength = await withMobileFileAccess(selected.length);
      validateMobileUploadSourceLength(
        originalContentType.startsWith('image/')
            ? MobileUploadKind.approvalImage
            : MobileUploadKind.approvalFile,
        sourceLength,
      );
      setState(() => _uploadingAttachment = true);
      uploading = true;
      final bytes = await withMobileFileAccess(selected.readAsBytes);
      if (bytes.isEmpty) {
        throw const MobileUploadAccessException();
      }
      final prepared = await ref
          .read(mobileImageCompressorProvider)
          .prepare(
            fileName: selected.name,
            bytes: bytes,
            contentType: originalContentType,
            purpose: MobileImagePurpose.approval,
          );
      if (prepared.bytes.length > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('单个附件不能超过 20 MB')));
        }
        return;
      }
      final attachment = OaLocalAttachment(
        id: const Uuid().v4(),
        fileName: prepared.fileName,
        contentType: prepared.contentType,
        bytes: prepared.bytes,
        formFieldId: field.id,
      );
      if (mounted) {
        setState(() {
          if (!field.multiple) {
            _attachments.removeWhere(
              (item) =>
                  item.formFieldId.isEmpty || item.formFieldId == field.id,
            );
          }
          _attachments.add(attachment);
          _serverFieldErrors.remove(field.id);
          _clientFieldErrors.remove(field.id);
          _markDraftChanged();
        });
        _scheduleDraftSave(template, allowOfflineDraft);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileUploadErrorText('附件处理失败', error))),
        );
      }
    } finally {
      if (mounted && uploading) {
        setState(() => _uploadingAttachment = false);
      }
    }
  }

  void _deleteAttachment(
    OaLocalAttachment attachment,
    OaApprovalTemplate template,
    bool allowOfflineDraft,
  ) {
    setState(() {
      _attachments.remove(attachment);
      _serverFieldErrors.remove(attachment.formFieldId);
      _clientFieldErrors.remove(attachment.formFieldId);
      _markDraftChanged();
    });
    _scheduleDraftSave(template, allowOfflineDraft);
  }

  Future<void> _openLocalAttachment(
    OaLocalAttachment attachment, {
    required bool allowImagePreview,
  }) async {
    if (allowImagePreview &&
        attachment.contentType.toLowerCase().startsWith('image/')) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (context) =>
              _LocalImageAttachmentPreview(attachment: attachment),
        ),
      );
      return;
    }
    try {
      final directory = await getTemporaryDirectory();
      final safeName = path.basename(attachment.fileName).trim().isEmpty
          ? 'attachment'
          : path.basename(attachment.fileName).trim();
      final target = File(
        path.join(directory.path, 'oa-${attachment.id}-$safeName'),
      );
      await target.writeAsBytes(attachment.bytes, flush: true);
      final result = await OpenFilex.open(target.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
  }

  void _scheduleDraftSave(OaApprovalTemplate template, bool allowOfflineDraft) {
    if (!allowOfflineDraft ||
        !_draftLoaded ||
        !_ownsDraftPage ||
        _submitting ||
        _handlingPop) {
      return;
    }
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 600),
      () => _saveDraft(template),
    );
  }

  Future<bool> _saveDraft(
    OaApprovalTemplate template, {
    bool showFeedback = false,
  }) async {
    if (!_ownsDraftPage) return false;
    _draftTimer?.cancel();
    final future = _draftSaveInFlight ??= _persistLatestDraft(template)
        .whenComplete(() {
          _draftSaveInFlight = null;
          if (_ownsDraftPage) setState(() => _draftSaving = false);
        });
    final saved = await future;
    if (showFeedback && mounted && _ownsDraftPage) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(saved ? '草稿已保存' : '草稿未保存，请重试')));
    }
    return saved;
  }

  bool get _ownsDraftPage =>
      mounted &&
      ref.read(collaborationAccountScopeProvider) == _draftAccountScope;

  void _markDraftChanged() {
    _draftRevision++;
    _hasUnsavedChanges = true;
    _draftSaveError = null;
  }

  Future<bool> _persistLatestDraft(OaApprovalTemplate template) async {
    setState(() {
      _draftSaving = true;
      _draftSaveError = null;
    });
    try {
      final saver = ref.read(oaDraftSaverProvider);
      while (_ownsDraftPage) {
        final revision = _draftRevision;
        final draft = await saver(
          id: _draft?.id ?? _newDraftId,
          applicationKey: widget.applicationKey,
          template: template,
          title: _title.trim().isEmpty ? _defaultTitle : _title.trim(),
          formData: Map<String, Object?>.from(
            jsonDecode(jsonEncode(_values)) as Map,
          ),
          attachments: List<OaLocalAttachment>.from(_attachments),
        );
        if (!_ownsDraftPage) return false;
        _draftTimer?.cancel();
        setState(() {
          _draft = draft;
          _draftSavedAt = draft.updatedAt;
          _draftWasRestored = false;
          _hasUnsavedChanges = revision != _draftRevision;
        });
        ref.invalidate(oaDraftsProvider);
        if (!_hasUnsavedChanges) return true;
        // Coalesce edits during the previous write into the next snapshot.
      }
    } catch (error) {
      if (_ownsDraftPage) setState(() => _draftSaveError = error);
    }
    return false;
  }

  Future<void> _handlePop(
    OaApprovalTemplate template,
    bool allowOfflineDraft,
  ) async {
    if (_handlingPop ||
        _submitting ||
        _uploadingAttachment ||
        !_ownsDraftPage) {
      return;
    }
    _draftTimer?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _handlingPop = true);
    try {
      if ((_hasUnsavedChanges || _draftSaveInFlight != null) &&
          allowOfflineDraft) {
        final saved = await _saveDraft(template);
        if (!saved || !_ownsDraftPage) {
          if (mounted && _ownsDraftPage) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('草稿未保存，请重试')));
          }
          return;
        }
      }
      if (!mounted || !_ownsDraftPage) return;
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    } finally {
      if (_ownsDraftPage) setState(() => _handlingPop = false);
    }
  }
}

class _RequesterSummary extends StatelessWidget {
  const _RequesterSummary({
    required this.displayName,
    required this.departmentName,
    required this.avatarKey,
    required this.avatarDataUrl,
    required this.templateVersion,
    required this.draftSavedAt,
    required this.draftStatus,
  });

  final String displayName;
  final String departmentName;
  final String avatarKey;
  final String avatarDataUrl;
  final int templateVersion;
  final DateTime? draftSavedAt;
  final String draftStatus;

  @override
  Widget build(BuildContext context) => MobileSurface(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      children: [
        InitialAvatar(
          key: const Key('approval-requester-avatar'),
          name: displayName,
          radius: 17,
          avatarKey: avatarKey,
          avatarDataUrl: avatarDataUrl,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (departmentName.isNotEmpty)
                Text(
                  departmentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.secondaryText,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'v$templateVersion',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 2),
            // Reserve only the small status line inside the existing summary;
            // a first autosave must not insert a banner and move form fields.
            Visibility(
              visible: draftStatus.isNotEmpty,
              maintainSize: true,
              maintainState: true,
              maintainAnimation: true,
              child: Tooltip(
                message: draftSavedAt == null
                    ? ''
                    : DateFormat('MM-dd HH:mm').format(draftSavedAt!.toLocal()),
                child: Text(
                  draftStatus.isEmpty ? '草稿已保存' : draftStatus,
                  key: const Key('approval-draft-status'),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AttachmentEditor extends StatelessWidget {
  const _AttachmentEditor({
    required this.field,
    required this.items,
    required this.uploading,
    required this.errorText,
    required this.onAdd,
    required this.onDelete,
    required this.onOpen,
  });

  final _FieldDefinition field;
  final List<OaLocalAttachment> items;
  final bool uploading;
  final String? errorText;
  final VoidCallback onAdd;
  final ValueChanged<OaLocalAttachment> onDelete;
  final ValueChanged<OaLocalAttachment> onOpen;

  @override
  Widget build(BuildContext context) => FormField<List<OaLocalAttachment>>(
    initialValue: items,
    validator: (_) {
      if (errorText != null) return errorText;
      if (field.required && items.isEmpty) return '请上传${field.label}';
      if (items.length > field.maxCount) {
        return '${field.label}最多保留 ${field.maxCount} 个附件';
      }
      return null;
    },
    builder: (state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _schemaFieldLabel(field),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${items.length} / ${field.maxCount}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondaryText,
              ),
            ),
            if (!field.isReadOnly) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: uploading
                    ? null
                    : () {
                        onAdd();
                        state.didChange(items);
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(36, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: uploading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file_rounded, size: 18),
                label: Text(
                  !field.multiple && items.isNotEmpty ? '替换文件' : '添加文件',
                ),
              ),
            ],
          ],
        ),
        if (state.errorText != null)
          Text(
            state.errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Material(
              key: ValueKey('approval-attachment-${item.id}'),
              color: const Color(0xFFF6F7F9),
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(item),
                child: SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      const SizedBox(width: 7),
                      _LocalAttachmentThumbnail(
                        attachment: item,
                        imagePreview: field.imagePreview,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fileSize(item.size),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!field.isReadOnly)
                        IconButton(
                          tooltip: '删除附件',
                          onPressed: () {
                            onDelete(item);
                            state.didChange(items);
                          },
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                          ),
                        ),
                      const SizedBox(width: 3),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _LocalAttachmentThumbnail extends StatelessWidget {
  const _LocalAttachmentThumbnail({
    required this.attachment,
    required this.imagePreview,
  });

  final OaLocalAttachment attachment;
  final bool imagePreview;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.contentType.toLowerCase().startsWith('image/');
    if (isImage && imagePreview) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          Uint8List.fromList(attachment.bytes),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const _AttachmentFileIcon(),
        ),
      );
    }
    return const _AttachmentFileIcon();
  }
}

class _AttachmentFileIcon extends StatelessWidget {
  const _AttachmentFileIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(6),
    ),
    alignment: Alignment.center,
    child: const Icon(
      Icons.insert_drive_file_outlined,
      size: 20,
      color: AppColors.primary,
    ),
  );
}

class _LocalImageAttachmentPreview extends StatelessWidget {
  const _LocalImageAttachmentPreview({required this.attachment});

  final OaLocalAttachment attachment;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('approval-local-attachment-preview'),
    backgroundColor: const Color(0xFF101318),
    body: SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  tooltip: '关闭附件预览',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    _fileSize(attachment.size),
                    style: const TextStyle(
                      color: Color(0xFFB8BFCC),
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.memory(
                  Uint8List.fromList(attachment.bytes),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Text(
                    '图片无法预览',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SchemaField extends StatelessWidget {
  const _SchemaField({
    required this.field,
    required this.autovalidateMode,
    required this.value,
    required this.serverError,
    required this.dependencyInvalid,
    required this.calculationError,
    required this.members,
    required this.departments,
    required this.onChanged,
  });

  final _FieldDefinition field;
  final AutovalidateMode autovalidateMode;
  final Object? value;
  final String? serverError;
  final String? calculationError;
  final bool dependencyInvalid;
  final List<ImMember> members;
  final List<ImDepartment> departments;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.type == 'checkbox') {
      return FormField<bool>(
        autovalidateMode: autovalidateMode,
        initialValue: value == true,
        validator: (checked) =>
            serverError ??
            (field.required && checked != true ? '请确认${field.label}' : null),
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_schemaFieldLabel(field)),
              value: state.value ?? false,
              onChanged: field.isReadOnly
                  ? null
                  : (checked) {
                      state.didChange(checked);
                      onChanged(checked);
                    },
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (state.hasError)
              Text(
                state.errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      );
    }
    if (field.type == 'select') {
      return FormField<String>(
        autovalidateMode: autovalidateMode,
        initialValue: value?.toString(),
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.isEmpty ?? true)
                ? '请选择${field.label}'
                : null),
        builder: (state) => InkWell(
          key: ValueKey('schema-${field.id}-select'),
          onTap: field.isReadOnly || field.options.isEmpty
              ? null
              : () async {
                  final selected = await showMobileChoiceSheet<String>(
                    context,
                    title: field.label,
                    selectedValue: state.value,
                    options: field.options
                        .map(
                          (option) =>
                              MobileSheetOption(value: option, label: option),
                        )
                        .toList(),
                  );
                  if (selected == null) return;
                  state.didChange(selected);
                  onChanged(selected);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _schemaFieldLabel(field),
              errorText: serverError ?? state.errorText,
              suffixIcon: field.isReadOnly
                  ? null
                  : const Icon(Icons.expand_more_rounded, size: 20),
            ),
            child: Text(
              state.value?.isNotEmpty == true ? state.value! : '请选择',
              style: TextStyle(
                color: state.value?.isNotEmpty == true
                    ? AppColors.text
                    : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      );
    }
    if (field.type == 'multiSelect') {
      return FormField<List<String>>(
        autovalidateMode: autovalidateMode,
        initialValue: value is List
            ? (value as List).map((item) => item.toString()).toList()
            : const [],
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.isEmpty ?? true)
                ? '请选择${field.label}'
                : null),
        builder: (state) => InkWell(
          key: ValueKey('schema-${field.id}-multi-select'),
          onTap: field.isReadOnly || field.options.isEmpty
              ? null
              : () async {
                  final selected = await showMobileMultiChoiceSheet<String>(
                    context,
                    title: field.label,
                    selectedValues: state.value ?? const <String>[],
                    options: field.options
                        .map(
                          (option) =>
                              MobileSheetOption(value: option, label: option),
                        )
                        .toList(),
                  );
                  if (selected == null) return;
                  state.didChange(selected);
                  onChanged(selected);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _schemaFieldLabel(field),
              errorText: serverError ?? state.errorText,
              suffixIcon: field.isReadOnly
                  ? null
                  : const Icon(Icons.expand_more_rounded, size: 20),
            ),
            child: Text(
              state.value?.isNotEmpty == true ? state.value!.join('、') : '请选择',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: state.value?.isNotEmpty == true
                    ? AppColors.text
                    : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      );
    }
    if (field.type == 'person' || field.type == 'department') {
      final options = field.type == 'person'
          ? members
                .map(
                  (member) => _ReferenceOption(
                    id: member.id,
                    label: member.displayName,
                    description: [
                      member.username,
                      member.departmentName,
                    ].where((item) => item.isNotEmpty).join(' · '),
                  ),
                )
                .toList()
          : _departmentOptions(departments, members);
      return FormField<String>(
        autovalidateMode: autovalidateMode,
        initialValue: value?.toString(),
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.isEmpty ?? true)
                ? '请选择${field.label}'
                : null),
        builder: (state) {
          final selected = options.where((item) => item.id == state.value);
          final label = selected.isEmpty ? '请选择' : selected.first.label;
          return InkWell(
            onTap: field.isReadOnly || options.isEmpty
                ? null
                : () async {
                    final result = await _showReferencePicker(
                      context,
                      title: field.label,
                      options: options,
                      selectedId: state.value,
                    );
                    if (result == null) return;
                    state.didChange(result);
                    onChanged(result);
                  },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: _schemaFieldLabel(field),
                errorText: serverError ?? state.errorText,
                suffixIcon: field.isReadOnly
                    ? null
                    : Icon(
                        field.type == 'person'
                            ? Icons.person_search_outlined
                            : Icons.account_tree_outlined,
                      ),
              ),
              child: Text(
                options.isEmpty ? '暂无可选数据' : label,
                style: TextStyle(
                  color: selected.isEmpty
                      ? AppColors.secondaryText
                      : AppColors.text,
                ),
              ),
            ),
          );
        },
      );
    }
    if (field.type == 'dateRange') {
      final initial = value is List
          ? (value as List).map((item) => item.toString()).toList()
          : const <String>[];
      return FormField<List<String>>(
        autovalidateMode: autovalidateMode,
        initialValue: initial,
        validator: (selected) {
          if (serverError != null) return serverError;
          if (field.required && (selected?.length != 2)) {
            return '请选择${field.label}';
          }
          if (selected?.length == 2) {
            final start = DateTime.tryParse(selected!.first);
            final end = DateTime.tryParse(selected.last);
            if (start != null && end != null && start.isAfter(end)) {
              return '结束日期不能早于开始日期';
            }
          }
          return null;
        },
        builder: (state) => InkWell(
          key: ValueKey('schema-${field.id}-date-range'),
          onTap: field.isReadOnly
              ? null
              : () async {
                  final current = state.value ?? const <String>[];
                  final start = current.isNotEmpty
                      ? DateTime.tryParse(current.first)
                      : null;
                  final end = current.length > 1
                      ? DateTime.tryParse(current.last)
                      : null;
                  final range = await showMobileDateRangePickerSheet(
                    context,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                    initialDateRange: start == null || end == null
                        ? null
                        : DateTimeRange(start: start, end: end),
                  );
                  if (range == null) return;
                  final selected = [
                    DateFormat('yyyy-MM-dd').format(range.start),
                    DateFormat('yyyy-MM-dd').format(range.end),
                  ];
                  state.didChange(selected);
                  onChanged(selected);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _schemaFieldLabel(field),
              errorText: serverError ?? state.errorText,
              suffixIcon: field.isReadOnly
                  ? null
                  : const Icon(Icons.date_range_outlined),
            ),
            child: Text(
              state.value?.length == 2
                  ? '${state.value!.first} 至 ${state.value!.last}'
                  : '请选择',
              style: TextStyle(
                color: state.value?.length == 2
                    ? AppColors.text
                    : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      );
    }
    if (field.type == 'date' || field.type == 'datetime') {
      return FormField<String>(
        autovalidateMode: autovalidateMode,
        initialValue: value?.toString(),
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.isEmpty ?? true)
                ? '请选择${field.label}'
                : null),
        builder: (state) => InkWell(
          key: ValueKey('schema-${field.id}-date'),
          onTap: field.isReadOnly
              ? null
              : () async {
                  final selected = await _pickDateTime(
                    context,
                    includeTime: field.type == 'datetime',
                    current: state.value,
                  );
                  if (selected == null) return;
                  state.didChange(selected);
                  onChanged(selected);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _schemaFieldLabel(field),
              errorText: serverError ?? state.errorText,
              suffixIcon: field.isReadOnly
                  ? null
                  : const Icon(Icons.calendar_month_outlined),
            ),
            child: Text(
              state.value?.isNotEmpty == true
                  ? _dateFieldText(
                      state.value!,
                      includeTime: field.type == 'datetime',
                    )
                  : '请选择',
              style: TextStyle(
                color: state.value?.isNotEmpty == true
                    ? AppColors.text
                    : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      );
    }
    final readOnly = field.isReadOnly;
    final displayValue = field.formatValue(value);
    final textField = TextFormField(
      autovalidateMode: autovalidateMode,
      key: readOnly
          ? ValueKey('schema-${field.id}-$displayValue')
          : ValueKey('schema-${field.id}'),
      initialValue: displayValue,
      readOnly: readOnly,
      canRequestFocus: !readOnly,
      enableInteractiveSelection: !readOnly,
      showCursor: !readOnly,
      keyboardType: field.type == 'number' || field.type == 'amount'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      minLines: field.type == 'textarea' ? 2 : 1,
      maxLines: field.type == 'textarea' ? 5 : 1,
      decoration: InputDecoration(
        labelText: _schemaFieldLabel(field),
        hintText: field.placeholder,
        helperText: field.helperText,
        helperMaxLines: 1,
        errorText: serverError,
        suffixText: field.displayUnit,
      ),
      validator: (text) {
        if (dependencyInvalid) return null;
        if (serverError != null) return serverError;
        if (calculationError != null) {
          return calculationError;
        }
        final missing = text?.trim().isEmpty ?? true;
        if (field.required && missing) return field.validateValue(text);
        if (!missing && (field.type == 'number' || field.type == 'amount')) {
          final number = num.tryParse(text!.trim());
          if (number == null || !number.isFinite) return '请输入有效数字';
          if (field.type == 'amount' && number <= 0) return '金额必须大于 0';
        }
        if (!missing && (field.type == 'text' || field.type == 'textarea')) {
          final validationError = field.validateText(text!.trim());
          if (validationError != null) return validationError;
        }
        return null;
      },
      onChanged: readOnly ? null : onChanged,
    );
    return textField;
  }
}

List<_FieldDefinition> _parseFields(String schemaJson) {
  try {
    final schema = jsonDecode(schemaJson);
    if (schema is! Map || schema['fields'] is! List) return const [];
    return (schema['fields'] as List)
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .where((raw) => raw['id']?.toString().trim().isNotEmpty == true)
        .map(_FieldDefinition.fromJson)
        .toList();
  } on FormatException {
    return const [];
  }
}

String _schemaFieldLabel(_FieldDefinition field) =>
    field.required ? '${field.label} *' : field.label;

final class _FieldDefinition {
  const _FieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    required this.placeholder,
    required this.options,
    required this.readOnly,
    required this.unit,
    required this.calculation,
    required this.defaultValueSource,
    required this.defaultValue,
    required this.validationFormat,
    required this.minLength,
    required this.maxLength,
    required this.multiple,
    required this.maxCount,
    required this.imagePreview,
    required this.durationStartFieldId,
    required this.durationEndFieldId,
    required this.durationUnit,
  });

  factory _FieldDefinition.fromJson(Map<String, Object?> json) =>
      _FieldDefinition(
        id: json['id']!.toString(),
        label: json['label']?.toString().trim().isNotEmpty == true
            ? json['label'].toString()
            : json['id'].toString(),
        type: json['type']?.toString() ?? 'text',
        required: json['required'] == true,
        placeholder: json['placeholder']?.toString(),
        options: json['options'] is List
            ? (json['options'] as List).map((item) => item.toString()).toList()
            : const [],
        readOnly: json['readOnly'] == true,
        unit: json['unit']?.toString().trim() ?? '',
        calculation: json['calculation'] is Map
            ? ApprovalFormCalculation.fromJson(
                (json['calculation'] as Map).cast<String, Object?>(),
              )
            : null,
        defaultValueSource: json['defaultValueSource']?.toString().trim() ?? '',
        defaultValue: json['defaultValue'],
        validationFormat: json['validationFormat']?.toString().trim() ?? '',
        minLength: _schemaInteger(json['minLength'], minimum: 0, maximum: 1000),
        maxLength: _schemaInteger(json['maxLength'], minimum: 0, maximum: 1000),
        multiple: json['multiple'] == true,
        maxCount: json['multiple'] == true
            ? (_schemaInteger(json['maxCount'], minimum: 1, maximum: 20) ?? 20)
            : 1,
        imagePreview: json['imagePreview'] == true,
        durationStartFieldId:
            json['durationStartFieldId']?.toString().trim().isNotEmpty == true
            ? json['durationStartFieldId'].toString()
            : null,
        durationEndFieldId:
            json['durationEndFieldId']?.toString().trim().isNotEmpty == true
            ? json['durationEndFieldId'].toString()
            : null,
        durationUnit: json['durationUnit']?.toString().trim().isNotEmpty == true
            ? json['durationUnit'].toString()
            : null,
      );

  final String id;
  final String label;
  final String type;
  final bool required;
  final String? placeholder;
  final List<String> options;
  final bool readOnly;
  final String unit;
  final ApprovalFormCalculation? calculation;
  final String defaultValueSource;
  final Object? defaultValue;
  final String validationFormat;
  final int? minLength;
  final int? maxLength;
  final bool multiple;
  final int maxCount;
  final bool imagePreview;
  final String? durationStartFieldId;
  final String? durationEndFieldId;
  final String? durationUnit;

  bool get isReadOnly =>
      readOnly || calculation != null || durationUnit != null;

  String? get displayUnit {
    if (unit.isNotEmpty) return unit;
    return switch (durationUnit) {
      'hours' => '小时',
      'days' => '天',
      _ => null,
    };
  }

  String? get helperText => switch (durationUnit) {
    'hours' => '根据起止时间自动计算小时',
    'days' => '根据起止时间自动计算自然日',
    _ => null,
  };

  String formatValue(Object? value) {
    if (value == null) return '';
    if (value is Map || value is Iterable) return '';
    if (calculation != null && value is num) {
      return value.toStringAsFixed(calculation!.scale);
    }
    return value.toString();
  }

  Object? resolveDefault({
    required ImMember? requester,
    required DateTime now,
  }) {
    switch (defaultValueSource) {
      case 'requester' when type == 'person':
        return requester?.id.isNotEmpty == true ? requester!.id : null;
      case 'requester_department' when type == 'department':
        return requester?.departmentId.isNotEmpty == true
            ? requester!.departmentId
            : null;
      case 'today' when type == 'date':
        return DateFormat('yyyy-MM-dd').format(now);
      case 'today' when type == 'dateRange':
        final today = DateFormat('yyyy-MM-dd').format(now);
        return <String>[today, today];
      case 'now' when type == 'datetime':
        return DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(now);
      case 'fixed':
        if (defaultValue is List) {
          return (defaultValue as List)
              .map((item) => item.toString())
              .toList(growable: false);
        }
        return defaultValue;
      default:
        return null;
    }
  }

  String? validateText(String value) {
    final length = value.runes.length;
    if (minLength != null && length < minLength!) {
      return '$label至少输入 $minLength 个字符';
    }
    if (maxLength != null && length > maxLength!) {
      return '$label最多输入 $maxLength 个字符';
    }
    if (validationFormat == 'tron_address' &&
        !RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(value)) {
      return '请输入有效的 TRON 地址';
    }
    return null;
  }

  String? validateValue(Object? value) {
    final missing =
        value == null ||
        value.toString().trim().isEmpty ||
        (value is List && value.isEmpty);
    if (required && (type == 'checkbox' ? value != true : missing)) {
      // A configured read-only value must still be present, but the user
      // cannot supply it by typing. Keep schema requirements intact.
      if (isReadOnly) {
        return calculation != null || durationUnit != null
            ? '$label尚未计算，请检查关联字段'
            : '$label暂无值，请检查表单配置';
      }
      return switch (type) {
        'checkbox' => '请确认$label',
        'select' ||
        'multiSelect' ||
        'person' ||
        'department' ||
        'date' ||
        'datetime' ||
        'dateRange' => '请选择$label',
        _ => '请填写$label',
      };
    }
    if (missing) return null;
    if (type == 'number' || type == 'amount') {
      final number = num.tryParse(value.toString().trim());
      if (number == null || !number.isFinite) return '请输入有效数字';
      if (type == 'amount' && number <= 0) return '金额必须大于 0';
    }
    if (type == 'text' || type == 'textarea') {
      return validateText(value.toString().trim());
    }
    if (type == 'dateRange' && value is List && value.length == 2) {
      final start = DateTime.tryParse(value.first.toString());
      final end = DateTime.tryParse(value.last.toString());
      if (start != null && end != null && start.isAfter(end)) {
        return '结束日期不能早于开始日期';
      }
    }
    return null;
  }
}

int? _schemaInteger(
  Object? value, {
  required int minimum,
  required int maximum,
}) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  if (parsed == null) return null;
  return parsed.clamp(minimum, maximum);
}

final class _ReferenceOption {
  const _ReferenceOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

List<ImMember> _uniqueMembers(Iterable<ImMember> members) {
  final byId = <String, ImMember>{};
  for (final member in members) {
    if (member.id.isNotEmpty) byId[member.id] = member;
  }
  return byId.values.toList();
}

List<_ReferenceOption> _departmentOptions(
  List<ImDepartment> departments,
  List<ImMember> members,
) {
  final byId = <String, _ReferenceOption>{};
  final directoryById = {for (final item in departments) item.id: item};
  final children = <String, List<ImDepartment>>{};
  for (final item in departments) {
    final parentId =
        item.parentId.isNotEmpty && directoryById.containsKey(item.parentId)
        ? item.parentId
        : '';
    children.putIfAbsent(parentId, () => []).add(item);
  }
  int compareDepartment(ImDepartment left, ImDepartment right) {
    final order = left.sortOrder.compareTo(right.sortOrder);
    return order != 0 ? order : left.name.compareTo(right.name);
  }

  for (final items in children.values) {
    items.sort(compareDepartment);
  }
  final visited = <String>{};
  void visit(ImDepartment item, List<String> path) {
    if (!visited.add(item.id)) return;
    final currentPath = [...path, item.name];
    byId[item.id] = _ReferenceOption(
      id: item.id,
      label: currentPath.join(' / '),
      description: item.code,
    );
    for (final child in children[item.id] ?? const <ImDepartment>[]) {
      visit(child, currentPath);
    }
  }

  for (final root in children[''] ?? const <ImDepartment>[]) {
    visit(root, const []);
  }
  for (final item in [...departments]..sort(compareDepartment)) {
    if (!visited.contains(item.id)) visit(item, const []);
  }
  for (final member in members) {
    if (member.departmentId.isEmpty || member.departmentName.isEmpty) continue;
    byId.putIfAbsent(
      member.departmentId,
      () => _ReferenceOption(
        id: member.departmentId,
        label: member.departmentName,
        description: '',
      ),
    );
  }
  return byId.values.toList();
}

Future<String?> _showReferencePicker(
  BuildContext context, {
  required String title,
  required List<_ReferenceOption> options,
  required String? selectedId,
}) => showMobileChoiceSheet<String>(
  context,
  title: title,
  selectedValue: selectedId,
  searchable: true,
  searchHint: '搜索名称、账号或部门',
  emptyText: '没有匹配结果',
  options: options
      .map(
        (item) => MobileSheetOption(
          value: item.id,
          label: item.label,
          subtitle: item.description,
        ),
      )
      .toList(),
);

class ApprovalWorkflowInline extends StatelessWidget {
  const ApprovalWorkflowInline({
    required this.preview,
    required this.loading,
    required this.error,
    required this.templateVersion,
    required this.onRetry,
    super.key,
  });

  final OaWorkflowPreview? preview;
  final bool loading;
  final Object? error;
  final int templateVersion;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final value = preview;
    final metadata = value == null
        ? 'v$templateVersion'
        : [
            value.requesterDepartmentName,
            'v${value.templateVersion}',
          ].where((item) => item.isNotEmpty).join(' · ');
    return Container(
      key: const Key('approval-workflow-inline'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '审批流程',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(right: 7),
                  child: SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
                ),
              Text(
                metadata,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (value == null && loading)
            const _WorkflowInlineStatus(
              icon: Icons.account_tree_outlined,
              label: '正在解析审批人…',
            )
          else if (value == null && error != null)
            _WorkflowInlineStatus(
              icon: Icons.info_outline_rounded,
              label: _workflowPreviewFailureLabel(error!),
              action: IconButton(
                tooltip: '重新解析审批流程',
                onPressed: onRetry,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            )
          else if (value != null && value.nodes.isEmpty)
            const _WorkflowInlineStatus(
              icon: Icons.info_outline_rounded,
              label: '当前流程没有审批节点',
            )
          else if (value != null)
            for (var index = 0; index < value.nodes.length; index++)
              _WorkflowInlineNode(
                key: ValueKey('approval-workflow-node-$index'),
                node: value.nodes[index],
                isLast: index == value.nodes.length - 1,
              ),
        ],
      ),
    );
  }
}

class _WorkflowInlineStatus extends StatelessWidget {
  const _WorkflowInlineStatus({
    required this.icon,
    required this.label,
    this.action,
  });

  final IconData icon;
  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppColors.secondaryText),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.secondaryText,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _WorkflowInlineNode extends StatelessWidget {
  const _WorkflowInlineNode({
    required this.node,
    required this.isLast,
    super.key,
  });

  final OaWorkflowPreviewNode node;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final actorText = _workflowActorsLabel(node.actors);
    final mode = node.actors.length > 1
        ? node.completionMode == 'any'
              ? '或签'
              : '会签'
        : '';
    final detail = [
      _workflowNodeTypeLabel(node.nodeType),
      actorText,
      mode,
    ].where((item) => item.isNotEmpty).join(' · ');
    final statusColor = node.isResolved
        ? AppColors.primary
        : Theme.of(context).colorScheme.error;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.1),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${node.stage}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 1, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 5 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.nodeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.25,
                      color: node.isResolved
                          ? AppColors.secondaryText
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _workflowActorsLabel(List<OaWorkflowPreviewActor> actors) {
  if (actors.isEmpty) return '未匹配处理人';
  final names = actors
      .map(
        (actor) => actor.displayName.trim().isNotEmpty
            ? actor.displayName.trim()
            : actor.userName.trim(),
      )
      .where((name) => name.isNotEmpty)
      .toList();
  final departments = actors
      .map((actor) => actor.departmentName.trim())
      .where((department) => department.isNotEmpty)
      .toSet();
  if (departments.length == 1) {
    return [names.join('、'), departments.single].join(' · ');
  }
  return actors
      .map((actor) {
        final name = actor.displayName.trim().isNotEmpty
            ? actor.displayName.trim()
            : actor.userName.trim();
        return [
          if (name.isNotEmpty) name,
          if (actor.departmentName.trim().isNotEmpty)
            actor.departmentName.trim(),
        ].join(' · ');
      })
      .where((label) => label.isNotEmpty)
      .join('；');
}

String _workflowNodeTypeLabel(String type) =>
    switch (type.trim().toLowerCase()) {
      'cc' => '抄送',
      'service' => '自动处理',
      _ => '审批',
    };

Future<String?> _pickDateTime(
  BuildContext context, {
  required bool includeTime,
  String? current,
}) async {
  final initial = DateTime.tryParse(current ?? '') ?? DateTime.now();
  final date = await showMobileDatePickerSheet(
    context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );
  if (date == null || !context.mounted) return null;
  if (!includeTime) return DateFormat('yyyy-MM-dd').format(date);
  final time = await showMobileTimePickerSheet(
    context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  ).toIso8601String();
}

String _dateFieldText(String value, {required bool includeTime}) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat(includeTime ? 'yyyy/MM/dd HH:mm' : 'yyyy/MM/dd')
      .format(parsed);
}

OaApprovalTemplate? _findTemplate(
  List<OaApprovalTemplate> templates,
  String id,
) {
  for (final template in templates) {
    if (template.id == id) return template;
  }
  return null;
}

String _errorMessage(Object error) {
  if (error is DioException && error.response?.data is Map) {
    final data = error.response!.data as Map;
    final message =
        data['message']?.toString() ?? data['detail']?.toString() ?? '';
    if (message.trim().isNotEmpty) {
      return mobileErrorText(Exception(message), fallback: '操作失败，请稍后重试');
    }
  }
  return mobileErrorText(error, fallback: '操作失败，请稍后重试');
}

bool _isRecoverableWorkflowPreviewError(Object? error) {
  if (error is TimeoutException || error is SocketException) {
    return true;
  }
  if (error is! DioException || CancelToken.isCancel(error)) return false;
  final status = error.response?.statusCode;
  if (status != null) return status >= 500 || status == 408 || status == 429;
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.unknown =>
      error.error is SocketException || error.error is TimeoutException,
    _ => false,
  };
}

String _workflowPreviewFailureLabel(Object error) {
  if (_isRecoverableWorkflowPreviewError(error)) {
    return '网络不可用，表单与草稿已保留';
  }
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 400 || status == 422) {
      return '请检查必填项后重新解析';
    }
  }
  return '暂时无法解析审批流程';
}

final class _SubmissionErrorDetails {
  const _SubmissionErrorDetails({
    required this.message,
    required this.fieldErrors,
  });

  final String message;
  final Map<String, String> fieldErrors;

  String get displayMessage =>
      fieldErrors.isEmpty ? message : fieldErrors.values.toSet().join('；');
}

_SubmissionErrorDetails _submissionError(Object error) {
  final fieldErrors = <String, String>{};
  var message = _errorMessage(error);
  if (error is DioException && error.response?.data is Map) {
    final data = error.response!.data as Map;
    final errors = data['errors'];
    if (errors is List) {
      for (final entry in errors.whereType<Map>()) {
        final target = entry['target']?.toString().trim() ?? '';
        final detail = entry['message']?.toString().trim() ?? '';
        if (target.isNotEmpty && detail.isNotEmpty) {
          fieldErrors[target] = detail;
        }
      }
    }
    if (message == 'Approval form validation failed.' &&
        fieldErrors.isNotEmpty) {
      message = '申请内容校验失败';
    }
  }
  return _SubmissionErrorDetails(message: message, fieldErrors: fieldErrors);
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _attachmentContentType(String? extension) => switch (extension
    ?.toLowerCase()) {
  'pdf' => 'application/pdf',
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'webp' => 'image/webp',
  'heic' || 'heif' => 'image/heic',
  'doc' => 'application/msword',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls' => 'application/vnd.ms-excel',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'txt' => 'text/plain',
  'zip' => 'application/zip',
  _ => 'application/octet-stream',
};
