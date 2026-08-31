import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _nickname = TextEditingController();
  final _signature = TextEditingController();
  ImMemberProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _avatarSaving = false;
  String _avatarDataUrl = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final member = ref.read(imBootstrapProvider).value?.currentMember;
    if (member == null) {
      setState(() {
        _loading = false;
        _error = '未获取到当前成员';
      });
      return;
    }
    try {
      final profile = await ref
          .read(imRepositoryProvider)
          .memberProfile(member.id);
      if (!mounted) return;
      _profile = profile;
      _nickname.text = profile.nickname.isNotEmpty
          ? profile.nickname
          : profile.displayName;
      _signature.text = profile.signature;
      _avatarDataUrl = profile.avatarDataUrl;
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (_avatarSaving) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 290000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请选择小于 290 KB 的图片')));
      return;
    }
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpeg';
    final mime = extension == 'jpg' ? 'jpeg' : extension;
    final dataUrl = 'data:image/$mime;base64,${base64Encode(bytes)}';
    setState(() => _avatarSaving = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .updateAvatar(avatarKey: 'custom', avatarDataUrl: dataUrl);
      ref.invalidate(imBootstrapProvider);
      if (mounted) setState(() => _avatarDataUrl = dataUrl);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('头像更新失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _avatarSaving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .updateProfile(nickname: _nickname.text, signature: _signature.text);
      ref.invalidate(imBootstrapProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
                  borderRadius: BorderRadius.circular(36),
                  onTap: _avatarSaving ? null : _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InitialAvatar(
                        name: _nickname.text.isEmpty
                            ? (_profile?.displayName ?? '')
                            : _nickname.text,
                        avatarDataUrl: _avatarDataUrl,
                        radius: 30,
                      ),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.primary,
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
                                  size: 12,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nickname,
                maxLength: 128,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  isDense: true,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _signature,
                maxLength: 280,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '个性签名',
                  isDense: true,
                ),
              ),
              if ((_profile?.username ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '账号  ${_profile!.username}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
  );
}
