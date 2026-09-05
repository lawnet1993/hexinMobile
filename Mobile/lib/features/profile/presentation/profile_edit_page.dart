import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../../core/media/mobile_image_compressor.dart';
import '../../../core/media/mobile_upload_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

typedef ProfileAvatarSelection = ({String name, String path, Uint8List bytes});

typedef ProfileAvatarCropper = Future<ProfileAvatarSelection?> Function(
  ProfileAvatarSelection source,
);

final profileAvatarPickerProvider =
    Provider<Future<ProfileAvatarSelection?> Function()>(
      (ref) => () async {
        final file = await withMobileFileAccess(
          () => FilePicker.pickFile(
            type: FileType.custom,
            allowedExtensions: const [
              'jpg',
              'jpeg',
              'png',
              'webp',
              'heic',
              'heif',
            ],
          ),
        );
        if (file == null) return null;
        final length = await withMobileFileAccess(file.length);
        validateMobileUploadSourceLength(MobileUploadKind.avatar, length);
        return (
          name: file.name,
          path: file.path ?? '',
          bytes: await withMobileFileAccess(file.readAsBytes),
        );
      },
    );

final profileAvatarCropperProvider = Provider<ProfileAvatarCropper>(
  (ref) => (source) async {
    if (source.path.isEmpty) return source;
    final cropped = await ImageCropper().cropImage(
      sourcePath: source.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: 768,
      maxHeight: 768,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪头像',
          toolbarColor: Colors.white,
          toolbarWidgetColor: AppColors.text,
          activeControlsWidgetColor: AppColors.primary,
          backgroundColor: Colors.black,
          lockAspectRatio: true,
          hideBottomControls: false,
          cropStyle: CropStyle.circle,
        ),
        IOSUiSettings(
          title: '裁剪头像',
          doneButtonTitle: '完成',
          cancelButtonTitle: '取消',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: CropStyle.circle,
        ),
      ],
    );
    if (cropped == null) return null;
    return (
      name: '${_fileStem(source.name)}.jpg',
      path: cropped.path,
      bytes: await cropped.readAsBytes(),
    );
  },
);

const _profileAvatarOptions = <(String, String)>[
  ('person', '阿晨'),
  ('work', '阿周'),
  ('badge', '林叔'),
  ('support', '小夏'),
  ('security', '若岚'),
];

class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _nickname = TextEditingController();
  final _signature = TextEditingController();
  ImMemberProfile? _profile;
  MobileSession? _editingSession;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _saving = false;
  bool _avatarSaving = false;
  bool _syncing = false;
  bool _usingCachedProfile = false;
  bool _dirty = false;
  String _avatarKey = '';
  String _avatarDataUrl = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authControllerProvider, (_, next) {
      final editing = _editingSession;
      if (editing != null && next.value?.isSameSession(editing) != true) {
        final current = next.value;
        if (current != null &&
            current.userId == editing.userId &&
            current.deviceId == editing.deviceId &&
            current.username == editing.username) {
          // Keep unsaved text on token rotation, but never accept the old
          // request's result. A later explicit Save binds the new session.
          ++_loadGeneration;
          setState(() {
            _editingSession = current;
            _saving = _avatarSaving = _syncing = false;
            _usingCachedProfile = true;
          });
        } else {
          _invalidateSession();
        }
      }
    });
    _load();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    var session = ref.read(authControllerProvider).value;
    if (session == null) {
      try {
        session = await ref.read(authControllerProvider.future);
      } catch (_) {
        session = null;
      }
      if (!mounted || generation != _loadGeneration) return;
    }
    if (session == null) {
      setState(() {
        _loading = false;
        _error = '暂时无法读取个人资料';
      });
      return;
    }
    if (!_isCurrent(session)) {
      _invalidateSession();
      return;
    }
    _editingSession = session;
    final cachedMember = ref.read(imBootstrapProvider).value?.currentMember;
    final member = cachedMember?.id == session.userId ? cachedMember : null;
    if (_profile == null) {
      _applyProfile(
        ImMemberProfile(
          id: session.userId,
          displayName: member?.displayName ?? session.displayName,
          nickname: member?.displayName ?? session.displayName,
          username: member?.username ?? session.username,
          departmentName: member?.departmentName ?? '',
          avatarKey: member?.avatarKey ?? '',
          avatarDataUrl: member?.avatarDataUrl ?? '',
        ),
      );
    }
    setState(() {
      _loading = false;
      _syncing = true;
      _usingCachedProfile = true;
    });
    try {
      final profile = await ref
          .read(imMemberProfileLoaderProvider)(_profile!.id)
          .timeout(const Duration(seconds: 5));
      if (!_isCurrent(session) || generation != _loadGeneration) return;
      if (profile.id != session.userId) {
        throw StateError('个人资料归属不匹配');
      }
      setState(() {
        if (_dirty) {
          _profile = profile;
          _avatarKey = profile.avatarKey;
          _avatarDataUrl = profile.avatarDataUrl;
        } else {
          _applyProfile(profile);
        }
        _usingCachedProfile = false;
      });
    } catch (_) {
      if (_isCurrent(session) && generation == _loadGeneration) {
        setState(() => _usingCachedProfile = true);
      }
    } finally {
      if (_isCurrent(session) && generation == _loadGeneration) {
        setState(() => _syncing = false);
      }
    }
  }

  bool _isCurrent(MobileSession session) =>
      mounted &&
      ref.read(authControllerProvider).value?.isSameSession(session) == true;

  void _invalidateSession() {
    if (!mounted) return;
    ++_loadGeneration;
    setState(() {
      _nickname.clear();
      _signature.clear();
      _avatarKey = '';
      _avatarDataUrl = '';
      _profile = null;
      _dirty = false;
      _loading = _saving = _avatarSaving = _syncing = false;
      _error = '登录状态已更新，请返回后重试';
    });
  }

  void _applyProfile(ImMemberProfile profile) {
    _profile = profile;
    _nickname.text = profile.nickname.isNotEmpty
        ? profile.nickname
        : profile.displayName;
    _signature.text = profile.signature;
    _avatarKey = profile.avatarKey;
    _avatarDataUrl = profile.avatarDataUrl;
    _dirty = false;
  }

  Future<void> _chooseAvatar() async {
    final session = _editingSession;
    if (_avatarSaving || _saving || session == null || !_isCurrent(session)) {
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => _AvatarLibraryDialog(selectedKey: _avatarKey),
    );
    if (!mounted || choice == null || !_isCurrent(session)) return;
    if (choice == 'custom') {
      await _pickCustomAvatar(session);
    } else {
      await _setPresetAvatar(session, choice);
    }
  }

  Future<void> _setPresetAvatar(MobileSession session, String key) async {
    if (_avatarSaving || _saving || !_isCurrent(session)) return;
    setState(() => _avatarSaving = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .updateAvatar(avatarKey: key, expectedSession: session);
      if (!mounted || !_isCurrent(session)) return;
      ref.invalidate(imBootstrapProvider);
      setState(() {
        _avatarKey = key;
        _avatarDataUrl = '';
      });
    } on SessionChangedException {
      if (_isCurrent(session)) _invalidateSession();
    } catch (error) {
      if (mounted && _isCurrent(session)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('头像更新失败', error))),
        );
      }
    } finally {
      if (_isCurrent(session)) setState(() => _avatarSaving = false);
    }
  }

  Future<void> _pickCustomAvatar(MobileSession session) async {
    if (_avatarSaving || _saving || !_isCurrent(session)) return;
    setState(() => _avatarSaving = true);
    try {
      final selected = await ref.read(profileAvatarPickerProvider)();
      if (!mounted || selected == null || !_isCurrent(session)) return;
      final file = await ref.read(profileAvatarCropperProvider)(selected);
      if (!mounted || file == null || !_isCurrent(session)) return;
      final prepared = await ref
          .read(mobileImageCompressorProvider)
          .prepare(
            fileName: file.name,
            bytes: file.bytes,
            contentType: mobileImageContentType(file.name),
            purpose: MobileImagePurpose.avatar,
          );
      if (!mounted || !_isCurrent(session)) return;
      final bytes = prepared.bytes;
      if (bytes.length > 290000) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片压缩后仍然过大，请更换图片')));
        return;
      }
      final dataUrl =
          'data:${prepared.contentType};base64,${base64Encode(bytes)}';
      await ref
          .read(imRepositoryProvider)
          .updateAvatar(
            avatarKey: 'custom',
            avatarDataUrl: dataUrl,
            expectedSession: session,
          );
      if (!mounted || !_isCurrent(session)) return;
      ref.invalidate(imBootstrapProvider);
      setState(() {
        _avatarKey = 'custom';
        _avatarDataUrl = dataUrl;
      });
    } on SessionChangedException {
      if (_isCurrent(session)) _invalidateSession();
    } catch (error) {
      if (mounted && _isCurrent(session)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileUploadErrorText('头像更新失败', error))),
        );
      }
    } finally {
      if (_isCurrent(session)) setState(() => _avatarSaving = false);
    }
  }

  Future<void> _save() async {
    final session = _editingSession;
    if (_saving || _avatarSaving || session == null || !_isCurrent(session)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .updateProfile(
            nickname: _nickname.text,
            signature: _signature.text,
            expectedSession: session,
          );
      if (!mounted || !_isCurrent(session)) return;
      ref.invalidate(imBootstrapProvider);
      _dirty = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
      Navigator.pop(context);
    } on SessionChangedException {
      if (_isCurrent(session)) _invalidateSession();
    } catch (error) {
      if (mounted && _isCurrent(session)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('保存失败', error))),
        );
      }
    } finally {
      if (_isCurrent(session)) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('个人资料')),
    body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : _error != null
        ? Center(child: Text(_error!, style: const TextStyle(fontSize: 13)))
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Center(
                child: InkWell(
                  key: const Key('profile-avatar-picker'),
                  borderRadius: BorderRadius.circular(32),
                  onTap:
                      _saving ||
                          _avatarSaving ||
                          _syncing ||
                          _usingCachedProfile
                      ? null
                      : _chooseAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InitialAvatar(
                        name: _nickname.text.isEmpty
                            ? (_profile?.displayName ?? '')
                            : _nickname.text,
                        avatarKey: _avatarKey,
                        avatarDataUrl: _avatarDataUrl,
                        radius: 26,
                      ),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: _syncing || _usingCachedProfile
                              ? AppColors.weakText
                              : AppColors.primary,
                          child: _avatarSaving
                              ? const SizedBox.square(
                                  dimension: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_outlined,
                                  size: 11,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_syncing || _usingCachedProfile) ...[
                _ProfileSyncState(
                  syncing: _syncing,
                  onRetry: _syncing ? null : _load,
                ),
                const SizedBox(height: 10),
              ],
              MobileSurface(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '昵称',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      key: const Key('profile-nickname-field'),
                      height: 40,
                      child: TextField(
                        controller: _nickname,
                        readOnly: _saving,
                        maxLength: 128,
                        onChanged: (_) => _markDirty(),
                        decoration: _profileInputDecoration('请输入昵称'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '个性签名',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      key: const Key('profile-signature-field'),
                      height: 72,
                      child: TextField(
                        controller: _signature,
                        readOnly: _saving,
                        maxLength: 280,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        onChanged: (_) => _markDirty(),
                        decoration: _profileInputDecoration('填写个性签名'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        key: const Key('profile-save-button'),
                        width: 104,
                        height: 36,
                        child: FilledButton(
                          onPressed: _saving || _avatarSaving || !_dirty
                              ? null
                              : _save,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(_saving ? '保存中…' : '保存'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
  );

  void _markDirty() {
    if (_dirty || !mounted) return;
    setState(() => _dirty = true);
  }
}

String _fileStem(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

class _AvatarLibraryDialog extends StatelessWidget {
  const _AvatarLibraryDialog({required this.selectedKey});

  final String selectedKey;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28),
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: SizedBox(
      width: 312,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '选择头像',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 1.08,
              mainAxisSpacing: 8,
              crossAxisSpacing: 6,
              children: [
                for (final option in _profileAvatarOptions)
                  _AvatarLibraryItem(
                    label: option.$2,
                    selected: selectedKey == option.$1,
                    onTap: () => Navigator.pop(context, option.$1),
                    child: InitialAvatar(
                      name: option.$2,
                      avatarKey: option.$1,
                      radius: 21,
                    ),
                  ),
                _AvatarLibraryItem(
                  label: '相册',
                  selected: selectedKey == 'custom',
                  onTap: () => Navigator.pop(context, 'custom'),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF0F3F8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AvatarLibraryItem extends StatelessWidget {
  const _AvatarLibraryItem({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 29,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: child,
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10.5,
            color: selected ? AppColors.primary : AppColors.secondaryText,
          ),
        ),
      ],
    ),
  );
}

InputDecoration _profileInputDecoration(String hintText) => InputDecoration(
  hintText: hintText,
  counterText: '',
  filled: true,
  fillColor: const Color(0xFFF4F6F9),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
  border: const OutlineInputBorder(
    borderSide: BorderSide.none,
    borderRadius: BorderRadius.all(Radius.circular(8)),
  ),
  enabledBorder: const OutlineInputBorder(
    borderSide: BorderSide.none,
    borderRadius: BorderRadius.all(Radius.circular(8)),
  ),
  focusedBorder: const OutlineInputBorder(
    borderSide: BorderSide(color: AppColors.primary),
    borderRadius: BorderRadius.all(Radius.circular(8)),
  ),
);

class _ProfileSyncState extends StatelessWidget {
  const _ProfileSyncState({required this.syncing, required this.onRetry});

  final bool syncing;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('profile-sync-state'),
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6F9),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        if (syncing)
          const SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          )
        else
          const Icon(
            Icons.cloud_off_outlined,
            size: 15,
            color: AppColors.secondaryText,
          ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            syncing ? '资料同步中' : '当前显示本机资料',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.secondaryText,
            ),
          ),
        ),
        if (!syncing)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('重新同步', style: TextStyle(fontSize: 12)),
          ),
      ],
    ),
  );
}
