import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/oa_local_store.dart';
import '../../collaboration/domain/collaboration_models.dart';

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
  String _title = '';
  bool _submitting = false;
  bool _previewing = false;
  bool _uploadingAttachment = false;
  bool _draftLoaded = false;
  OaApprovalDraft? _draft;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadDraft);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          description: error.toString(),
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
    final defaultTitle = '${data.displayName}的${template.name}';
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
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(template.name)),
      body: Theme(
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
                avatarDataUrl: requester?.avatarDataUrl ?? '',
                templateVersion: template.version,
              ),
              const SizedBox(height: 8),
              MobileSurface(
                key: const Key('approval-form-surface'),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextFormField(
                      key: ValueKey('approval-title-$_draftLoaded'),
                      initialValue: _title.isEmpty ? defaultTitle : _title,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: '申请标题',
                        counterText: '',
                      ),
                      validator: _requiredText,
                      onChanged: (value) {
                        _title = value;
                        _scheduleDraftSave(template, allowOfflineDraft);
                      },
                    ),
                    const SizedBox(height: 8),
                    for (final field in fields) ...[
                      if (field.type == 'attachment' || field.type == 'file')
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
                          onAdd: () => _pickAttachment(
                            field.id,
                            template,
                            allowOfflineDraft,
                          ),
                          onDelete: (attachment) => _deleteAttachment(
                            attachment,
                            template,
                            allowOfflineDraft,
                          ),
                        )
                      else
                        _SchemaField(
                          field: field,
                          value: _values[field.id],
                          serverError: _serverFieldErrors[field.id],
                          members: members,
                          departments: departments,
                          onChanged: (value) {
                            setState(() {
                              _values[field.id] = value;
                              _serverFieldErrors.remove(field.id);
                              _recalculateDurations(fields);
                            });
                            _scheduleDraftSave(template, allowOfflineDraft);
                          },
                        ),
                      const SizedBox(height: 10),
                    ],
                    if (fields.isEmpty)
                      const EmptyState(
                        icon: Icons.description_outlined,
                        title: '当前模板没有可填写字段',
                      ),
                    if (fields.isNotEmpty)
                      SizedBox(
                        key: const Key('approval-workflow-button'),
                        height: 40,
                        child: Material(
                          color: const Color(0xFFF1F6FF),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _previewing
                                ? null
                                : () => _previewWorkflow(template),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_previewing)
                                  const SizedBox.square(
                                    dimension: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.account_tree_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                const SizedBox(width: 8),
                                const Text(
                                  '查看审批流程',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
              if (allowOfflineDraft) ...[
                SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    key: const Key('approval-draft-button'),
                    onPressed: _submitting
                        ? null
                        : () => _saveDraft(template, showFeedback: true),
                    style: OutlinedButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存草稿'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: FilledButton.icon(
                    key: const Key('approval-submit-button'),
                    onPressed: _submitting
                        ? null
                        : () => _submit(
                            template,
                            _title.trim().isEmpty
                                ? defaultTitle
                                : _title.trim(),
                            allowOfflineDraft,
                          ),
                    style: FilledButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: const Text('提交申请'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(
    OaApprovalTemplate template,
    String title,
    bool allowOfflineDraft,
  ) async {
    if (!_formKey.currentState!.validate()) return;
    _draftTimer?.cancel();
    setState(() => _submitting = true);
    try {
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

  Future<void> _previewWorkflow(OaApprovalTemplate template) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _previewing = true);
    try {
      final preview = await ref
          .read(oaRepositoryProvider)
          .previewWorkflow(
            applicationKey: widget.applicationKey,
            template: template,
            formData: _values,
          );
      if (mounted) {
        setState(() => _previewing = false);
        await _showWorkflowPreview(context, preview);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted && _previewing) setState(() => _previewing = false);
    }
  }

  void _recalculateDurations(List<_FieldDefinition> fields) {
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
      if (start == null || end == null || !end.isAfter(start)) {
        _values.remove(field.id);
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
        _draftLoaded = true;
      });
      return;
    }
    try {
      final draft = await ref
          .read(oaRepositoryProvider)
          .draftForTemplate(widget.templateId);
      if (!mounted) return;
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
        }
        _draftLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _draftLoaded = true);
    }
  }

  Future<void> _pickAttachment(
    String formFieldId,
    OaApprovalTemplate template,
    bool allowOfflineDraft,
  ) async {
    if (_attachments.length >= 20) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('单个申请最多添加 20 个附件')));
      return;
    }
    final selected = await FilePicker.pickFile();
    if (selected == null || !mounted) return;
    setState(() => _uploadingAttachment = true);
    try {
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法读取所选文件')));
        }
        return;
      }
      if (bytes.length > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('单个附件不能超过 20 MB')));
        }
        return;
      }
      final attachment = OaLocalAttachment(
        id: const Uuid().v4(),
        fileName: selected.name,
        contentType: _attachmentContentType(
          path.extension(selected.name).replaceFirst('.', ''),
        ),
        bytes: bytes,
        formFieldId: formFieldId,
      );
      if (mounted) {
        setState(() => _attachments.add(attachment));
        _scheduleDraftSave(template, allowOfflineDraft);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  void _deleteAttachment(
    OaLocalAttachment attachment,
    OaApprovalTemplate template,
    bool allowOfflineDraft,
  ) {
    setState(() => _attachments.remove(attachment));
    _scheduleDraftSave(template, allowOfflineDraft);
  }

  void _scheduleDraftSave(OaApprovalTemplate template, bool allowOfflineDraft) {
    if (!allowOfflineDraft || !_draftLoaded) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 600),
      () => _saveDraft(template),
    );
  }

  Future<void> _saveDraft(
    OaApprovalTemplate template, {
    bool showFeedback = false,
  }) async {
    try {
      final draft = await ref
          .read(oaRepositoryProvider)
          .saveDraft(
            id: _draft?.id,
            applicationKey: widget.applicationKey,
            template: template,
            title: _title.trim(),
            formData: _values,
            attachments: _attachments,
          );
      _draft = draft;
      ref.invalidate(oaDraftsProvider);
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('草稿已保存')));
      }
    } catch (error) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
  }
}

class _RequesterSummary extends StatelessWidget {
  const _RequesterSummary({
    required this.displayName,
    required this.departmentName,
    required this.avatarDataUrl,
    required this.templateVersion,
  });

  final String displayName;
  final String departmentName;
  final String avatarDataUrl;
  final int templateVersion;

  @override
  Widget build(BuildContext context) => MobileSurface(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      children: [
        InitialAvatar(
          name: displayName,
          radius: 17,
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
        Text(
          'v$templateVersion',
          style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
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
    required this.onAdd,
    required this.onDelete,
  });

  final _FieldDefinition field;
  final List<OaLocalAttachment> items;
  final bool uploading;
  final VoidCallback onAdd;
  final ValueChanged<OaLocalAttachment> onDelete;

  @override
  Widget build(BuildContext context) => FormField<List<OaLocalAttachment>>(
    initialValue: items,
    validator: (_) =>
        field.required && items.isEmpty ? '请上传${field.label}' : null,
    builder: (state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                field.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${items.length} / 20',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondaryText,
              ),
            ),
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
              label: const Text('添加文件'),
            ),
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
          (item) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_fileSize(item.size)),
            trailing: IconButton(
              tooltip: '删除附件',
              onPressed: () {
                onDelete(item);
                state.didChange(items);
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SchemaField extends StatelessWidget {
  const _SchemaField({
    required this.field,
    required this.value,
    required this.serverError,
    required this.members,
    required this.departments,
    required this.onChanged,
  });

  final _FieldDefinition field;
  final Object? value;
  final String? serverError;
  final List<ImMember> members;
  final List<ImDepartment> departments;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.type == 'checkbox') {
      return FormField<bool>(
        initialValue: value == true,
        validator: (checked) =>
            serverError ??
            (field.required && checked != true ? '请确认${field.label}' : null),
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(field.label),
              value: state.value ?? false,
              onChanged: (checked) {
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
      return DropdownButtonFormField<String>(
        initialValue: value?.toString(),
        decoration: InputDecoration(
          labelText: field.label,
          errorText: serverError,
        ),
        items: field.options
            .map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            )
            .toList(),
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.isEmpty ?? true)
                ? '请选择${field.label}'
                : null),
        onChanged: onChanged,
      );
    }
    if (field.type == 'multiSelect') {
      return FormField<List<String>>(
        initialValue: value is List
            ? (value as List).map((item) => item.toString()).toList()
            : const [],
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.isEmpty ?? true)
                ? '请选择${field.label}'
                : null),
        builder: (state) => InputDecorator(
          decoration: InputDecoration(
            labelText: field.label,
            errorText: serverError ?? state.errorText,
          ),
          child: Wrap(
            spacing: 8,
            children: field.options.map((option) {
              final selected = state.value?.contains(option) == true;
              return FilterChip(
                label: Text(option),
                selected: selected,
                onSelected: (checked) {
                  final next = [...?state.value];
                  checked ? next.add(option) : next.remove(option);
                  state.didChange(next);
                  onChanged(next);
                },
              );
            }).toList(),
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
            onTap: options.isEmpty
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
                labelText: field.label,
                errorText: serverError ?? state.errorText,
                suffixIcon: Icon(
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
        initialValue: initial,
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.length != 2)
                ? '请选择${field.label}'
                : null),
        builder: (state) => InkWell(
          onTap: () async {
            final current = state.value ?? const <String>[];
            final start = current.isNotEmpty
                ? DateTime.tryParse(current.first)
                : null;
            final end = current.length > 1
                ? DateTime.tryParse(current.last)
                : null;
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
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
              labelText: field.label,
              errorText: serverError ?? state.errorText,
              suffixIcon: const Icon(Icons.date_range_outlined),
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
        initialValue: value?.toString(),
        validator: (selected) =>
            serverError ??
            (field.required && (selected?.isEmpty ?? true)
                ? '请选择${field.label}'
                : null),
        builder: (state) => InkWell(
          onTap: () async {
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
              labelText: field.label,
              errorText: serverError ?? state.errorText,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
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
    return TextFormField(
      key: ValueKey('schema-${field.id}-${value ?? ''}'),
      initialValue: value?.toString(),
      readOnly: field.durationUnit != null,
      keyboardType: field.type == 'number' || field.type == 'amount'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      minLines: field.type == 'textarea' ? 2 : 1,
      maxLines: field.type == 'textarea' ? 5 : 1,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder,
        errorText: serverError,
        prefixText: field.type == 'amount' ? '¥ ' : null,
        suffixText: field.durationUnit == 'hours'
            ? '小时'
            : field.durationUnit == 'days'
            ? '天'
            : null,
      ),
      validator: (text) {
        if (serverError != null) return serverError;
        final missing = text?.trim().isEmpty ?? true;
        if (field.required && missing) return '请填写${field.label}';
        if (!missing && (field.type == 'number' || field.type == 'amount')) {
          final number = num.tryParse(text!.trim());
          if (number == null) return '请输入有效数字';
          if (field.type == 'amount' && number <= 0) return '金额必须大于 0';
        }
        return null;
      },
      onChanged: onChanged,
    );
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

final class _FieldDefinition {
  const _FieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    required this.placeholder,
    required this.options,
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
  final String? durationStartFieldId;
  final String? durationEndFieldId;
  final String? durationUnit;
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
}) async {
  final searchController = TextEditingController();
  var query = '';
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) => StatefulBuilder(
        builder: (context, setSheetState) {
          final normalized = query.trim().toLowerCase();
          final filtered = options
              .where(
                (item) =>
                    normalized.isEmpty ||
                    item.label.toLowerCase().contains(normalized) ||
                    item.description.toLowerCase().contains(normalized),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '搜索名称、账号或部门',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setSheetState(() => query = value),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('没有匹配结果'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                item.label.isEmpty ? '?' : item.label[0],
                              ),
                            ),
                            title: Text(item.label),
                            subtitle: item.description.isEmpty
                                ? null
                                : Text(item.description),
                            trailing: item.id == selectedId
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: AppColors.primary,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, item.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
  await disposeRouteTextController(searchController);
  return result;
}

Future<void> _showWorkflowPreview(
  BuildContext context,
  OaWorkflowPreview preview,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => ApprovalWorkflowPreviewSheet(preview: preview),
);

class ApprovalWorkflowPreviewSheet extends StatelessWidget {
  const ApprovalWorkflowPreviewSheet({required this.preview, super.key});

  final OaWorkflowPreview preview;

  @override
  Widget build(BuildContext context) {
    final maximumHeight = MediaQuery.sizeOf(context).height * 0.72;
    final contentHeight = 72.0 + preview.nodes.length * 76.0;
    final sheetHeight = contentHeight.clamp(220.0, maximumHeight);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 8, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '审批流程',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${preview.requesterDepartmentName} · v${preview.templateVersion}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: preview.nodes.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 66),
                itemBuilder: (context, index) {
                  final node = preview.nodes[index];
                  final actorText = _workflowActorsLabel(node.actors);
                  final mode = node.actors.length > 1
                      ? node.completionMode == 'any'
                            ? '或签'
                            : '会签'
                      : '';
                  return ListTile(
                    dense: true,
                    minTileHeight: 76,
                    minVerticalPadding: 6,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: node.isResolved
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.errorContainer,
                      foregroundColor: node.isResolved
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.error,
                      child: Text('${node.stage}'),
                    ),
                    title: Text(
                      node.nodeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        _workflowNodeTypeLabel(node.nodeType),
                        actorText,
                        mode,
                      ].where((item) => item.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: node.isResolved
                            ? AppColors.secondaryText
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    trailing: node.isResolved
                        ? const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 20,
                            color: AppColors.primary,
                          )
                        : Icon(
                            Icons.error_outline_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.error,
                          ),
                  );
                },
              ),
            ),
          ],
        ),
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
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );
  if (date == null || !context.mounted) return null;
  if (!includeTime) return DateFormat('yyyy-MM-dd').format(date);
  final time = await showTimePicker(
    context: context,
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

String? _requiredText(String? value) =>
    (value?.trim().isEmpty ?? true) ? '请填写申请标题' : null;

String _errorMessage(Object error) {
  if (error is DioException && error.response?.data is Map) {
    final data = error.response!.data as Map;
    final message =
        data['message']?.toString() ?? data['detail']?.toString() ?? '';
    if (message.trim().isNotEmpty) return message;
  }
  return error.toString().replaceFirst('Exception: ', '');
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
  'doc' => 'application/msword',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls' => 'application/vnd.ms-excel',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'txt' => 'text/plain',
  'zip' => 'application/zip',
  _ => 'application/octet-stream',
};
