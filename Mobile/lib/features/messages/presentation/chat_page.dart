import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../../collaboration/application/im_sync_coordinator.dart';
import 'conversation_detail_page.dart';
import 'message_favorites_page.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.conversationId,
    this.enablePresence = true,
    this.initialResourceTab = 0,
  });

  final String conversationId;
  final bool enablePresence;
  final int initialResourceTab;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  ImRepository? _repository;
  final _controller = TextEditingController();
  bool _sending = false;
  bool _sendingAttachment = false;
  int _lastReadSequence = 0;
  bool _searching = false;
  String _query = '';
  final Set<String> _mentionedMemberIds = <String>{};
  bool _mentionAll = false;
  ImMessage? _replyTo;
  Timer? _presenceTimer;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  int _resourceTab = 0;

  @override
  void initState() {
    super.initState();
    _resourceTab = widget.initialResourceTab.clamp(0, 2);
    if (widget.enablePresence) {
      _repository = ref.read(imRepositoryProvider);
    }
    if (!widget.enablePresence) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshPresence();
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 25),
        (_) => _refreshPresence(),
      );
    });
  }

  Future<void> _refreshPresence() async {
    if (!widget.enablePresence) return;
    try {
      await ref
          .read(imRepositoryProvider)
          .enterConversation(widget.conversationId);
      if (mounted) {
        ref.invalidate(conversationPresenceProvider(widget.conversationId));
      }
    } catch (_) {
      // The next heartbeat retries presence synchronization.
    }
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _repository?.leaveActiveConversation().ignore();
    _controller.dispose();
    super.dispose();
  }

  void _refreshConversationState() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(conversationMessagesProvider(widget.conversationId));
      ref.invalidate(imBootstrapProvider);
    });
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final older = await ref
          .read(imRepositoryProvider)
          .loadOlderMessages(widget.conversationId);
      if (!mounted) return;
      setState(() => _hasOlder = older.length >= 80);
      ref.invalidate(conversationMessagesProvider(widget.conversationId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('历史消息加载失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _retryMessage(ImMessage message) async {
    if (message.clientMessageId.isEmpty) return;
    await ref
        .read(imRepositoryProvider)
        .retryMessage(widget.conversationId, message.clientMessageId);
    _refreshConversationState();
  }

  Future<void> _send() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _sending) return;
    final replyTo = _replyTo;
    setState(() => _sending = true);
    try {
      final message = await ref
          .read(imRepositoryProvider)
          .send(
            widget.conversationId,
            value,
            mentionedMemberIds: _mentionedMemberIds.toList(),
            mentionAll: _mentionAll,
            replyTo: replyTo == null
                ? null
                : ImMessageReply(
                    messageId: replyTo.id,
                    senderId: replyTo.senderId,
                    content: replyTo.content,
                    kind: replyTo.kind,
                    createdAt: replyTo.createdAt,
                    recalledAt: replyTo.recalledAt,
                  ),
          );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _mentionedMemberIds.clear();
        _mentionAll = false;
        _replyTo = null;
      });
      _refreshConversationState();
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) ref.read(imSyncCoordinatorProvider).synchronizeNow();
      });
      if (message.localStatus == ImLocalMessageStatus.failed && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('消息已保存，将在网络恢复后自动重试')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markRead(List<ImMessage> items) async {
    final sequence = items.fold<int>(
      0,
      (latest, item) => item.sequence > latest ? item.sequence : latest,
    );
    if (sequence <= _lastReadSequence) return;
    _lastReadSequence = sequence;
    try {
      await ref
          .read(imRepositoryProvider)
          .markRead(widget.conversationId, sequence);
      _refreshConversationState();
    } catch (_) {
      _lastReadSequence = 0;
    }
  }

  Future<void> _showAttachmentMenu(ImBootstrap? bootstrap) async {
    if (_sendingAttachment) return;
    var isDirectConversation = false;
    if (bootstrap != null) {
      for (final item in bootstrap.conversations) {
        if (item.id == widget.conversationId) {
          isDirectConversation = item.isDirect;
          break;
        }
      }
    }
    final actions = <_AttachmentMenuAction>[
      const _AttachmentMenuAction('image', '图片', Icons.photo_outlined),
      const _AttachmentMenuAction('video', '视频', Icons.videocam_outlined),
      const _AttachmentMenuAction('audio', '音频', Icons.audio_file_outlined),
      const _AttachmentMenuAction(
        'file',
        '文件',
        Icons.insert_drive_file_outlined,
      ),
      _AttachmentMenuAction(
        'contact',
        '联系人',
        Icons.contact_page_outlined,
        enabled: bootstrap != null,
      ),
      if (isDirectConversation)
        const _AttachmentMenuAction('task', '创建任务', Icons.fact_check_outlined),
    ];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '发送内容',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: actions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 72,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                itemBuilder: (context, index) {
                  final item = actions[index];
                  return _AttachmentActionTile(
                    action: item,
                    onTap: item.enabled
                        ? () => Navigator.pop(context, item.value)
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'image') {
      await _pickAndSendImages();
    } else if (action == 'video' || action == 'audio') {
      await _pickAndSendMedia(action);
    } else if (action == 'file') {
      await _pickAndSendFile();
    } else if (action == 'contact' && bootstrap != null) {
      await _pickAndSendContact(bootstrap.contacts);
    } else if (action == 'task') {
      await _createSharedTask();
    }
  }

  Future<void> _pickAndSendMedia(String kind) async {
    final isVideo = kind == 'video';
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: isVideo
          ? const ['mp4', 'm4v', 'webm', 'mov', 'mkv']
          : const ['mp3', 'm4a', 'wav', 'ogg', 'oga', 'flac'],
    );
    if (selected == null || !mounted) return;
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法读取所选${isVideo ? '视频' : '音频'}')),
        );
      }
      return;
    }
    setState(() => _sendingAttachment = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .sendMedia(
            conversationId: widget.conversationId,
            kind: kind,
            fileName: selected.name,
            bytes: bytes,
            contentType: _contentType(
              path.extension(selected.name).replaceFirst('.', ''),
            ),
          );
      _refreshConversationState();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${isVideo ? '视频' : '音频'}发送失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _pickAndSendImages() async {
    final selected = await FilePicker.pickFiles(type: FileType.image);
    if (selected.isEmpty || !mounted) return;
    if (selected.length > 9) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('一次最多发送 9 张图片')));
      return;
    }
    setState(() => _sendingAttachment = true);
    try {
      final files =
          <({String fileName, Uint8List bytes, String contentType})>[];
      for (final item in selected) {
        final bytes = await item.readAsBytes();
        files.add((
          fileName: item.name,
          bytes: bytes,
          contentType: _contentType(
            path.extension(item.name).replaceFirst('.', ''),
          ),
        ));
      }
      await ref
          .read(imRepositoryProvider)
          .sendImages(conversationId: widget.conversationId, files: files);
      _refreshConversationState();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('图片发送失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    final selected = await FilePicker.pickFile();
    if (selected == null || !mounted) return;
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法读取所选文件')));
      }
      return;
    }
    setState(() => _sendingAttachment = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .sendAttachment(
            conversationId: widget.conversationId,
            fileName: selected.name,
            bytes: bytes,
            contentType: _contentType(
              path.extension(selected.name).replaceFirst('.', ''),
            ),
          );
      _refreshConversationState();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('文件发送失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _pickAndSendContact(List<ImMember> contacts) async {
    final member = await showModalBottomSheet<ImMember>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ContactPickerSheet(contacts: contacts),
    );
    if (member == null || !mounted) return;
    setState(() => _sendingAttachment = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .sendContactCard(widget.conversationId, member.id);
      _refreshConversationState();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('联系人分享失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _openAttachment(ImMessage message) async {
    try {
      final attachment = await ref
          .read(imRepositoryProvider)
          .downloadAttachment(message);
      final directory = await getTemporaryDirectory();
      final target = File(
        path.join(directory.path, path.basename(attachment.fileName)),
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
            .showSnackBar(SnackBar(content: Text('附件打开失败：$error')));
      }
    }
  }

  Future<void> _openMediaAttachment(ImMessageAttachment attachment) async {
    try {
      final bytes = await ref
          .read(imRepositoryProvider)
          .downloadMediaAttachment(attachment.id);
      final directory = await getTemporaryDirectory();
      final target = File(
        path.join(directory.path, path.basename(attachment.fileName)),
      );
      await target.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(target.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('媒体打开失败：$error')));
      }
    }
  }

  Future<void> _openConversationLink(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('无法打开链接');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('链接打开失败：$error')));
    }
  }

  void _openConversationImage(ImMessage message) {
    if (message.images.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => _ConversationImagePreview(message: message),
    );
  }

  Future<void> _showEmojiPicker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ['😀', '😂', '😊', '👍', '👏', '🎉', '❤️', '收到']
                .map(
                  (item) => InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.pop(context, item),
                    child: SizedBox.square(
                      dimension: 42,
                      child: Center(
                        child: Text(item, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    _controller.text += emoji;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  Future<void> _showMentionPicker(
    List<ImMember> members,
    ImGroupProfile? profile,
    bool allowMentionAll,
  ) async {
    final choice = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if ((profile?.atEnabled ?? true) && allowMentionAll)
              ListTile(
                leading: const CircleAvatar(child: Text('@')),
                title: const Text('@全体'),
                subtitle: const Text('提醒群内全部成员'),
                onTap: () => Navigator.pop(context, const _MentionChoice.all()),
              ),
            ...members.map(
              (member) => ListTile(
                leading: InitialAvatar(
                  name: member.displayName,
                  radius: 18,
                  avatarDataUrl: member.avatarDataUrl,
                ),
                title: Text(member.displayName),
                subtitle: Text(member.departmentName),
                onTap: () =>
                    Navigator.pop(context, _MentionChoice.member(member)),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice is! _MentionChoice) return;
    if (choice.mentionAll) {
      setState(() {
        _mentionAll = true;
        _controller.text += '@全体 ';
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      });
      return;
    }
    final member = choice.member;
    if (member == null) return;
    setState(() {
      _mentionedMemberIds.add(member.id);
      _controller.text += '@${member.displayName} ';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  Future<void> _showMessageActions(
    ImMessage message,
    bool mine,
    bool isGroup,
    ImBootstrap? bootstrap,
  ) async {
    if (message.id.isEmpty || message.id.startsWith('local-')) return;
    final permissions = bootstrap?.permissions ?? const ImPermissionSnapshot();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (bootstrap?.config.message.reply ?? true)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('回复'),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
            if (mine && permissions.editMessage && message.kind == 'text')
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (mine && permissions.revokeMessage)
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: const Text('撤回'),
                onTap: () => Navigator.pop(context, 'revoke'),
              ),
            if (bootstrap?.config.message.forward ?? true)
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: const Text('转发'),
                onTap: () => Navigator.pop(context, 'forward'),
              ),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('收藏'),
              onTap: () => Navigator.pop(context, 'favorite'),
            ),
            if (isGroup)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('设为群置顶'),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
            if (mine && permissions.readReceipt)
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('查看已读'),
                onTap: () => Navigator.pop(context, 'receipt'),
              ),
            if (permissions.deleteMessage)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text(
                  '删除',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'reply':
          setState(() => _replyTo = message);
        case 'edit':
          await _editMessage(message);
        case 'revoke':
          await ref
              .read(imRepositoryProvider)
              .revokeMessage(widget.conversationId, message.id);
          _refreshConversationState();
        case 'delete':
          await ref.read(imRepositoryProvider).deleteMessage(message.id);
          _refreshConversationState();
        case 'forward':
          await _forwardMessage(message, bootstrap?.conversations ?? const []);
        case 'favorite':
          await ref.read(imRepositoryProvider).addFavorite(message.id);
          ref.invalidate(imFavoritesProvider);
          ref.invalidate(imFavoritesPageProvider);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已收藏')));
          }
        case 'pin':
          await ref.read(imRepositoryProvider).pinMessage(message.id);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已设为群置顶')));
          }
        case 'receipt':
          await _showReadReceipts(message);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  Future<void> _editMessage(ImMessage message) async {
    final controller = TextEditingController(text: message.content);
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2000,
          minLines: 1,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await disposeRouteTextController(controller);
    if (content == null || content.isEmpty || !mounted) return;
    await ref.read(imRepositoryProvider).editMessage(message.id, content);
    _refreshConversationState();
  }

  Future<void> _forwardMessage(
    ImMessage message,
    List<ImConversation> conversations,
  ) async {
    final targets = conversations
        .where((item) => item.id != widget.conversationId)
        .toList();
    final target = await showModalBottomSheet<ImConversation>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: Column(
            children: [
              const Text('转发到', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: targets.length,
                  itemBuilder: (context, index) => ListTile(
                    leading: InitialAvatar(
                      name: targets[index].title,
                      radius: 18,
                    ),
                    title: Text(targets[index].title),
                    onTap: () => Navigator.pop(context, targets[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    await ref.read(imRepositoryProvider).forwardMessage(message.id, target.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已转发到 ${target.title}')));
    }
  }

  Future<void> _showReadReceipts(ImMessage message) async {
    final receipt = await ref
        .read(imRepositoryProvider)
        .messageReadReceipts(message.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
        title: Text(
          '已读 ${receipt.readCount}/${receipt.totalRecipientCount}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: receipt.readers.isEmpty
            ? const Text('暂无已读成员', style: TextStyle(fontSize: 13))
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SizedBox(
                  width: 280,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: receipt.readers.length,
                    itemBuilder: (context, index) {
                      final item = receipt.readers[index];
                      final name = item.displayName.isNotEmpty
                          ? item.displayName
                          : item.username;
                      return ListTile(
                        dense: true,
                        leading: InitialAvatar(name: name, radius: 15),
                        title: Text(name),
                        subtitle: item.readAt == null
                            ? null
                            : Text(
                                DateFormat('MM-dd HH:mm').format(item.readAt!),
                              ),
                      );
                    },
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _createSharedTask() async {
    var taskTitle = '';
    var priority = 'normal';
    final draft = await showModalBottomSheet<_SharedTaskDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            14 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '新建共同任务',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                maxLength: 120,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: '输入任务名称',
                  counterText: '',
                  isDense: true,
                ),
                onChanged: (value) => taskTitle = value,
                onSubmitted: (_) {
                  final title = taskTitle.trim();
                  if (title.isNotEmpty) {
                    Navigator.pop(
                      sheetContext,
                      _SharedTaskDraft(title, priority),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children:
                    const [
                      ('low', '低'),
                      ('normal', '普通'),
                      ('high', '高'),
                      ('urgent', '紧急'),
                    ].map((item) {
                      final selected = priority == item.$1;
                      return ChoiceChip(
                        label: Text(item.$2),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) =>
                            setSheetState(() => priority = item.$1),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: FilledButton(
                        onPressed: () {
                          final title = taskTitle.trim();
                          if (title.isNotEmpty) {
                            Navigator.pop(
                              sheetContext,
                              _SharedTaskDraft(title, priority),
                            );
                          }
                        },
                        child: const Text('创建'),
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
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(oaRepositoryProvider)
          .createTodo(
            title: draft.title,
            priority: draft.priority,
            conversationId: widget.conversationId,
          );
      ref.invalidate(oaBootstrapProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('共同任务已创建')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('任务创建失败：$error')));
      }
    }
  }

  Future<void> _openConversationDetail(
    ImConversation conversation,
    ImMember currentMember,
  ) async {
    final resourceTab = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (routeContext) => ConversationDetailPage(
          conversation: conversation,
          currentMember: currentMember,
          onOpenResource: (tab) => Navigator.of(routeContext).pop(tab),
        ),
      ),
    );
    if (!mounted || resourceTab == null) return;
    setState(() {
      _resourceTab = resourceTab;
      _searching = false;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(imBootstrapProvider).value;
    final oa = ref.watch(oaBootstrapProvider).value;
    final storedConversation = bootstrap?.conversations
        .where((item) => item.id == widget.conversationId)
        .firstOrNull;
    final syntheticDirectMember =
        widget.conversationId.startsWith('demo-direct-')
        ? bootstrap?.contacts
              .where(
                (item) =>
                    item.id ==
                    widget.conversationId.substring('demo-direct-'.length),
              )
              .firstOrNull
        : null;
    final conversation =
        storedConversation ??
        (syntheticDirectMember == null
            ? null
            : ImConversation(
                id: widget.conversationId,
                type: 'direct',
                title: syntheticDirectMember.displayName,
                preview: '',
                updatedAt: DateTime(0),
                unreadCount: 0,
              ));
    final messages = ref.watch(
      conversationMessagesProvider(widget.conversationId),
    );
    final resourceCount =
        messages.asData?.value.where(_isConversationResource).length ?? 0;
    final sharedTasks = (oa?.todos ?? const <OaTodo>[])
        .where(
          (item) =>
              item.conversationId == widget.conversationId &&
              item.status != 'completed' &&
              item.status != 'canceled',
        )
        .toList(growable: false);
    final members = ref
        .watch(conversationMembersProvider(widget.conversationId))
        .value;
    final groupProfile = conversation?.isGroup == true
        ? ref.watch(groupProfileProvider(widget.conversationId)).value
        : null;
    final presence = widget.enablePresence
        ? ref.watch(conversationPresenceProvider(widget.conversationId)).value
        : null;
    final currentMember = bootstrap?.currentMember;
    final directMember = conversation?.isDirect == true
        ? members
                  ?.where((member) => member.id != currentMember?.id)
                  .firstOrNull ??
              bootstrap?.contacts
                  .where((member) => member.displayName == conversation?.title)
                  .firstOrNull
        : null;
    final memberMap = <String, ImMember>{
      for (final member in <ImMember?>[currentMember, ...?members].nonNulls)
        member.id: member,
    };
    ref.listen(conversationMessagesProvider(widget.conversationId), (_, next) {
      next.whenData(_markRead);
    });
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (conversation?.isGroup == true)
              const _GroupAvatar(size: 34)
            else
              InitialAvatar(
                name: directMember?.displayName ?? conversation?.title ?? '会话',
                radius: 17,
                online: presence?.peerOnline ?? directMember?.isOnline,
                avatarDataUrl: directMember?.avatarDataUrl ?? '',
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    directMember?.displayName ?? conversation?.title ?? '会话',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (conversation != null)
                    Text(
                      conversation.isGroup
                          ? presence == null
                                ? '${members?.length ?? 0} 位成员'
                                : '${members?.length ?? 0} 位成员 · ${presence.onlineMemberCount} 人在线'
                          : _directPresenceLabel(directMember, presence),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '我的收藏',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MessageFavoritesPage(),
              ),
            ),
            icon: const Icon(Icons.bookmark_border_rounded),
          ),
          IconButton(
            tooltip: '搜索聊天记录',
            onPressed: () => setState(() {
              _resourceTab = 0;
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: conversation?.isGroup == true ? '群聊详情' : '个人资料',
            onPressed: conversation == null || currentMember == null
                ? null
                : () => _openConversationDetail(conversation, currentMember),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (conversation != null)
            _ChatResourceTabs(
              selectedIndex: _resourceTab,
              fileCount: resourceCount,
              taskCount: sharedTasks.length,
              showTasks: conversation.isDirect,
              onChanged: (value) => setState(() {
                _resourceTab = value;
                if (value != 0) {
                  _searching = false;
                  _query = '';
                }
              }),
            ),
          if (_searching && _resourceTab == 0)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              color: Colors.white,
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: '搜索当前会话',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: '关闭搜索',
                    onPressed: () => setState(() {
                      _searching = false;
                      _query = '';
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ),
          if (_resourceTab == 0 &&
              conversation?.isGroup == true &&
              (groupProfile?.notice.trim().isNotEmpty ?? false))
            InkWell(
              onTap: currentMember == null
                  ? null
                  : () => _openConversationDetail(conversation!, currentMember),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                color: Colors.white,
                child: Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        groupProfile!.notice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: '消息加载失败',
                description: error.toString(),
                onRetry: () => ref.invalidate(
                  conversationMessagesProvider(widget.conversationId),
                ),
              ),
              data: (items) {
                if (_resourceTab == 1) {
                  return _ConversationFilesView(
                    messages: items,
                    onOpenFile: _openAttachment,
                    onOpenImage: _openConversationImage,
                    onOpenMedia: _openMediaAttachment,
                    onOpenLink: _openConversationLink,
                  );
                }
                if (_resourceTab == 2 && conversation?.isDirect == true) {
                  return _ConversationTasksView(
                    tasks: sharedTasks,
                    onCreate: _createSharedTask,
                    onViewAll: () => context.go('/todos'),
                  );
                }
                final query = _query.toLowerCase();
                final visibleItems = query.isEmpty
                    ? items
                    : items
                          .where(
                            (item) =>
                                item.content.toLowerCase().contains(query),
                          )
                          .toList();
                return visibleItems.isEmpty
                    ? const EmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: '没有匹配的消息',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                        itemCount: visibleItems.length,
                        itemBuilder: (context, index) {
                          final item = visibleItems[index];
                          return Column(
                            children: [
                              if (index == 0)
                                Column(
                                  children: [
                                    if (_query.isEmpty)
                                      TextButton.icon(
                                        onPressed: _loadingOlder || !_hasOlder
                                            ? null
                                            : _loadOlderMessages,
                                        icon: _loadingOlder
                                            ? const SizedBox.square(
                                                dimension: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.history_rounded,
                                                size: 17,
                                              ),
                                        label: Text(
                                          _hasOlder ? '加载更早消息' : '没有更早消息',
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: Text(
                                        item.createdAt == null
                                            ? '今天'
                                            : DateFormat('MM-dd HH:mm')
                                                  .format(item.createdAt!),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.weakText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              _MessageBubble(
                                item: item,
                                mine:
                                    item.senderId ==
                                    bootstrap?.currentMember.id,
                                currentMemberName:
                                    bootstrap?.currentMember.displayName ?? '',
                                currentMemberAvatarDataUrl:
                                    bootstrap?.currentMember.avatarDataUrl ??
                                    '',
                                sender: memberMap[item.senderId],
                                showSenderName: conversation?.isGroup == true,
                                onOpenAttachment: item.kind == 'file'
                                    ? () => _openAttachment(item)
                                    : const {
                                            'video',
                                            'audio',
                                          }.contains(item.kind) &&
                                          item.attachments.isNotEmpty
                                    ? () => _openMediaAttachment(
                                        item.attachments.first,
                                      )
                                    : null,
                                onRetry:
                                    item.localStatus ==
                                        ImLocalMessageStatus.failed
                                    ? () => _retryMessage(item)
                                    : null,
                                onLongPress: () => _showMessageActions(
                                  item,
                                  item.senderId == bootstrap?.currentMember.id,
                                  conversation?.isGroup == true,
                                  bootstrap,
                                ),
                              ),
                            ],
                          );
                        },
                      );
              },
            ),
          ),
          if (_resourceTab == 0)
            SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Row(
                  children: [
                    if (conversation?.isGroup == true &&
                        (groupProfile?.atEnabled ?? true) &&
                        (bootstrap?.config.message.mentionMember ?? true))
                      IconButton(
                        tooltip: '提及成员',
                        onPressed: members == null
                            ? null
                            : () => _showMentionPicker(
                                members,
                                groupProfile,
                                bootstrap?.config.message.mentionAll ?? false,
                              ),
                        icon: const Icon(Icons.alternate_email_rounded),
                      ),
                    IconButton(
                      tooltip: '附件',
                      onPressed: _sendingAttachment
                          ? null
                          : () => _showAttachmentMenu(bootstrap),
                      icon: _sendingAttachment
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file_rounded),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: _replyTo == null ? '输入消息' : '回复消息',
                          isDense: true,
                          filled: true,
                          fillColor: Color(0xFFF5F6F8),
                          prefixIcon: _replyTo == null
                              ? null
                              : const Icon(Icons.reply_rounded, size: 18),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      tooltip: '表情',
                      onPressed: _showEmojiPicker,
                      icon: const Icon(Icons.sentiment_satisfied_alt_outlined),
                    ),
                    IconButton.filled(
                      tooltip: '发送',
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
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

final class _SharedTaskDraft {
  const _SharedTaskDraft(this.title, this.priority);

  final String title;
  final String priority;
}

final class _AttachmentMenuAction {
  const _AttachmentMenuAction(
    this.value,
    this.label,
    this.icon, {
    this.enabled = true,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool enabled;
}

class _AttachmentActionTile extends StatelessWidget {
  const _AttachmentActionTile({required this.action, required this.onTap});

  final _AttachmentMenuAction action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? AppColors.primary : AppColors.secondaryText;
    return SizedBox(
      key: ValueKey('chat-attachment-${action.value}'),
      height: 72,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFFEAF2FF)
                    : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(action.icon, size: 20, color: color),
            ),
            const SizedBox(height: 5),
            Text(
              action.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                color: enabled ? AppColors.text : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isConversationFile(ImMessage item) =>
    item.kind == 'file' ||
    item.kind == 'audio' ||
    (item.attachmentName.trim().isNotEmpty &&
        !const {'image', 'video'}.contains(item.kind));

bool _isConversationMedia(ImMessage item) =>
    item.kind == 'image' || item.kind == 'video';

bool _isConversationLink(ImMessage item) => _messageLinks(item).isNotEmpty;

bool _isConversationResource(ImMessage item) =>
    _isConversationFile(item) ||
    _isConversationMedia(item) ||
    _isConversationLink(item);

List<Uri> _messageLinks(ImMessage item) {
  final matches = RegExp(
    r'https?://[^\s<>()]+',
    caseSensitive: false,
  ).allMatches(item.content);
  return matches
      .map((match) => match.group(0) ?? '')
      .map((value) => value.replaceFirst(RegExp(r'[，。；、,.!?]+$'), ''))
      .map(Uri.tryParse)
      .nonNulls
      .where((uri) => uri.hasScheme && uri.host.isNotEmpty)
      .toList(growable: false);
}

class _ChatResourceTabs extends StatelessWidget {
  const _ChatResourceTabs({
    required this.selectedIndex,
    required this.fileCount,
    required this.taskCount,
    required this.showTasks,
    required this.onChanged,
  });

  final int selectedIndex;
  final int fileCount;
  final int taskCount;
  final bool showTasks;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SizedBox(
      height: 38,
      child: Row(
        children: [
          _ResourceTab(
            label: '聊天',
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _ResourceTab(
            label: fileCount == 0 ? '文件' : '文件 $fileCount',
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
          if (showTasks)
            _ResourceTab(
              label: taskCount == 0 ? '任务' : '任务 $taskCount',
              selected: selectedIndex == 2,
              onTap: () => onChanged(2),
            ),
        ],
      ),
    ),
  );
}

class _ResourceTab extends StatelessWidget {
  const _ResourceTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
          if (selected)
            const Positioned(
              left: 24,
              right: 24,
              bottom: 0,
              child: SizedBox(
                height: 2,
                child: ColoredBox(color: AppColors.primary),
              ),
            ),
        ],
      ),
    ),
  );
}

enum _ConversationResourceType { file, media, link }

class _ConversationFilesView extends StatefulWidget {
  const _ConversationFilesView({
    required this.messages,
    required this.onOpenFile,
    required this.onOpenImage,
    required this.onOpenMedia,
    required this.onOpenLink,
  });

  final List<ImMessage> messages;
  final ValueChanged<ImMessage> onOpenFile;
  final ValueChanged<ImMessage> onOpenImage;
  final ValueChanged<ImMessageAttachment> onOpenMedia;
  final ValueChanged<Uri> onOpenLink;

  @override
  State<_ConversationFilesView> createState() => _ConversationFilesViewState();
}

class _ConversationFilesViewState extends State<_ConversationFilesView> {
  _ConversationResourceType _type = _ConversationResourceType.file;

  @override
  Widget build(BuildContext context) {
    final files = widget.messages.where(_isConversationFile).toList();
    final media = widget.messages.where(_isConversationMedia).toList();
    final links = [
      for (final message in widget.messages)
        for (final uri in _messageLinks(message)) (message: message, uri: uri),
    ];
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                _ResourceCategoryTab(
                  label: '文件',
                  count: files.length,
                  selected: _type == _ConversationResourceType.file,
                  onTap: () =>
                      setState(() => _type = _ConversationResourceType.file),
                ),
                _ResourceCategoryTab(
                  label: '图片/视频',
                  count: media.length,
                  selected: _type == _ConversationResourceType.media,
                  onTap: () =>
                      setState(() => _type = _ConversationResourceType.media),
                ),
                _ResourceCategoryTab(
                  label: '链接',
                  count: links.length,
                  selected: _type == _ConversationResourceType.link,
                  onTap: () =>
                      setState(() => _type = _ConversationResourceType.link),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_type) {
            _ConversationResourceType.file => _ConversationResourceList(
              items: files,
              emptyIcon: Icons.folder_open_outlined,
              emptyText: '暂无会话文件',
              iconOf: (item) => item.kind == 'audio'
                  ? Icons.graphic_eq_rounded
                  : Icons.description_outlined,
              nameOf: _conversationFileName,
              trailing: Icons.download_outlined,
              onTap: widget.onOpenFile,
            ),
            _ConversationResourceType.media => _ConversationResourceList(
              items: media,
              emptyIcon: Icons.photo_library_outlined,
              emptyText: '暂无图片或视频',
              iconOf: (item) => item.kind == 'video'
                  ? Icons.videocam_outlined
                  : Icons.photo_outlined,
              nameOf: _conversationMediaName,
              trailing: Icons.open_in_new_rounded,
              onTap: (item) {
                if (item.kind == 'image') {
                  widget.onOpenImage(item);
                } else if (item.attachments.isNotEmpty) {
                  widget.onOpenMedia(item.attachments.first);
                }
              },
            ),
            _ConversationResourceType.link =>
              links.isEmpty
                  ? const EmptyState(
                      icon: Icons.link_off_rounded,
                      title: '暂无会话链接',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: links.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final link = links[index];
                        return ListTile(
                          dense: true,
                          minTileHeight: 54,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: const _ResourceIcon(
                            icon: Icons.link_rounded,
                          ),
                          title: Text(
                            link.uri.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          subtitle: Text(
                            _resourceTime(link.message),
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                          ),
                          onTap: () => widget.onOpenLink(link.uri),
                        );
                      },
                    ),
          },
        ),
      ],
    );
  }
}

class _ResourceCategoryTab extends StatelessWidget {
  const _ResourceCategoryTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      canRequestFocus: false,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            count == 0 ? label : '$label $count',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
          if (selected)
            const Positioned(
              left: 34,
              right: 34,
              bottom: 0,
              child: SizedBox(
                height: 2,
                child: ColoredBox(color: AppColors.primary),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ConversationResourceList extends StatelessWidget {
  const _ConversationResourceList({
    required this.items,
    required this.emptyIcon,
    required this.emptyText,
    required this.iconOf,
    required this.nameOf,
    required this.trailing,
    required this.onTap,
  });

  final List<ImMessage> items;
  final IconData emptyIcon;
  final String emptyText;
  final IconData Function(ImMessage) iconOf;
  final String Function(ImMessage) nameOf;
  final IconData trailing;
  final ValueChanged<ImMessage> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return EmptyState(icon: emptyIcon, title: emptyText);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          dense: true,
          minTileHeight: 54,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: _ResourceIcon(icon: iconOf(item)),
          title: Text(
            nameOf(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            _resourceTime(item),
            style: const TextStyle(fontSize: 10.5),
          ),
          trailing: Icon(trailing, size: 19),
          onTap: () => onTap(item),
        );
      },
    );
  }
}

class _ResourceIcon extends StatelessWidget {
  const _ResourceIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 18, color: AppColors.primary),
  );
}

String _conversationFileName(ImMessage item) {
  final name = item.kind == 'audio' && item.attachments.isNotEmpty
      ? item.attachments.first.fileName
      : item.attachmentName.trim().isEmpty
      ? item.content.replaceFirst(RegExp(r'^附件[：:]\s*'), '')
      : item.attachmentName;
  return name.trim().isEmpty ? '工作附件' : name;
}

String _conversationMediaName(ImMessage item) {
  if (item.kind == 'image') {
    if (item.images.isEmpty) return '会话图片';
    if (item.images.length == 1) return item.images.first.fileName;
    return '${item.images.first.fileName} 等 ${item.images.length} 张图片';
  }
  return item.attachments.isEmpty ? '会话视频' : item.attachments.first.fileName;
}

String _resourceTime(ImMessage item) => item.createdAt == null
    ? '会话资源'
    : DateFormat('yyyy/MM/dd HH:mm').format(item.createdAt!);

class _ConversationImagePreview extends ConsumerWidget {
  const _ConversationImagePreview({required this.message});

  final ImMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = message.images.first;
    final bytes = ref.watch(
      imMessageImageProvider((messageId: message.id, imageId: image.id)),
    );
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          bytes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 42,
              ),
            ),
            data: (data) => InteractiveViewer(
              child: Image.memory(data, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 28,
            right: 12,
            child: IconButton.filledTonal(
              tooltip: '关闭预览',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTasksView extends StatelessWidget {
  const _ConversationTasksView({
    required this.tasks,
    required this.onCreate,
    required this.onViewAll,
  });

  final List<OaTodo> tasks;
  final VoidCallback onCreate;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '共同任务',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: onViewAll, child: const Text('查看全部')),
          const SizedBox(width: 2),
          SizedBox(
            height: 34,
            child: FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('新建'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (tasks.isEmpty)
        const SizedBox(
          height: 220,
          child: Center(
            child: Text(
              '暂无共同任务',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
        )
      else
        ...tasks.map(
          (task) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MobileSurface(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _taskPriorityColor(task.priority),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (task.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            task.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    task.dueAt == null
                        ? '未排期'
                        : DateFormat('MM/dd').format(task.dueAt!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

Color _taskPriorityColor(String priority) => switch (priority) {
  'urgent' => AppColors.error,
  'high' => const Color(0xFFF08C2E),
  'low' => const Color(0xFF22A06B),
  _ => AppColors.primary,
};

String _directPresenceLabel(
  ImMember? member,
  ImConversationPresence? presence,
) {
  final parts = [
    member?.departmentName ?? '',
    member?.username ?? '',
  ].where((value) => value.isNotEmpty).toList();
  if (presence == null) return parts.join(' · ');
  if (presence.peerOnline) {
    parts.add('在线');
  } else if (presence.peerLastSeenAt == null) {
    parts.add('离线');
  } else {
    parts.add(
      '离线 · ${DateFormat('MM-dd HH:mm').format(presence.peerLastSeenAt!)} 最后在线',
    );
  }
  return parts.join(' · ');
}

final class _MentionChoice {
  const _MentionChoice.all() : member = null, mentionAll = true;
  const _MentionChoice.member(ImMember value)
    : member = value,
      mentionAll = false;

  final ImMember? member;
  final bool mentionAll;
}

List<InlineSpan> _messageSpans(ImMessage item, Color color) {
  final labels = item.mentions
      .map(
        (mention) => mention.isMentionAll ? '@全体' : '@${mention.displayName}',
      )
      .toSet()
      .toList();
  if (labels.isEmpty) {
    return [
      TextSpan(
        text: item.content,
        style: TextStyle(color: color),
      ),
    ];
  }
  final spans = <InlineSpan>[];
  final pattern = RegExp(labels.map(RegExp.escape).join('|'));
  var cursor = 0;
  for (final match in pattern.allMatches(item.content)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(
          text: item.content.substring(cursor, match.start),
          style: TextStyle(color: color),
        ),
      );
    }
    spans.add(
      TextSpan(
        text: match.group(0),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
    cursor = match.end;
  }
  if (cursor < item.content.length) {
    spans.add(
      TextSpan(
        text: item.content.substring(cursor),
        style: TextStyle(color: color),
      ),
    );
  }
  return spans;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.item,
    required this.mine,
    required this.currentMemberName,
    required this.currentMemberAvatarDataUrl,
    required this.sender,
    required this.showSenderName,
    required this.onOpenAttachment,
    required this.onRetry,
    required this.onLongPress,
  });

  final ImMessage item;
  final bool mine;
  final String currentMemberName;
  final String currentMemberAvatarDataUrl;
  final ImMember? sender;
  final bool showSenderName;
  final VoidCallback? onOpenAttachment;
  final VoidCallback? onRetry;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!mine) ...[
          InitialAvatar(
            name: sender?.displayName ?? item.senderId,
            radius: 20,
            avatarDataUrl: sender?.avatarDataUrl ?? '',
          ),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!mine && showSenderName) ...[
                Text(
                  sender?.displayName ?? '群成员',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              InkWell(
                onTap: onOpenAttachment,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: mine ? AppColors.primary : Colors.white,
                    border: mine ? null : Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: item.recalledAt != null
                      ? Text(
                          '消息已撤回',
                          style: TextStyle(
                            color: mine ? Colors.white : AppColors.text,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.replyTo != null)
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 250,
                                ),
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.only(left: 7),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: AppColors.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  item.replyTo!.recalledAt != null
                                      ? '消息已撤回'
                                      : item.replyTo!.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: mine
                                        ? Colors.white70
                                        : AppColors.secondaryText,
                                  ),
                                ),
                              ),
                            if (item.kind == 'file')
                              _AttachmentContent(item: item, mine: mine)
                            else if (const {
                                  'video',
                                  'audio',
                                }.contains(item.kind) &&
                                item.attachments.isNotEmpty)
                              _MediaMessageContent(message: item, mine: mine)
                            else if (item.kind == 'image' &&
                                item.images.isNotEmpty)
                              _ImageMessageContent(message: item)
                            else if (item.kind == 'contact' &&
                                item.contactCard != null)
                              _ContactCardContent(
                                card: item.contactCard!,
                                mine: mine,
                              )
                            else
                              Text.rich(
                                TextSpan(
                                  children: _messageSpans(
                                    item,
                                    mine ? Colors.white : AppColors.text,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              if (mine && item.localStatus != ImLocalMessageStatus.sent) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.localStatus == ImLocalMessageStatus.failed
                            ? Icons.error_outline_rounded
                            : Icons.schedule_rounded,
                        size: 14,
                        color: item.localStatus == ImLocalMessageStatus.failed
                            ? AppColors.error
                            : AppColors.secondaryText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.localStatus == ImLocalMessageStatus.failed
                            ? '发送失败，点此重试'
                            : '发送中',
                        style: TextStyle(
                          fontSize: 11,
                          color: item.localStatus == ImLocalMessageStatus.failed
                              ? AppColors.error
                              : AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (mine) ...[
          const SizedBox(width: 9),
          InitialAvatar(
            name: currentMemberName.isEmpty ? item.senderId : currentMemberName,
            radius: 20,
            avatarDataUrl: currentMemberAvatarDataUrl,
          ),
        ],
      ],
    ),
  );
}

class _ImageMessageContent extends ConsumerWidget {
  const _ImageMessageContent({required this.message});

  final ImMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = message.images.take(9).toList();
    return SizedBox(
      width: images.length == 1 ? 210 : 240,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: images.length == 1 ? 1 : 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          mainAxisExtent: images.length == 1 ? 180 : 78,
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          final image = images[index];
          final bytes = ref.watch(
            imMessageImageProvider((messageId: message.id, imageId: image.id)),
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: bytes.when(
              loading: () => const ColoredBox(
                color: Color(0xFFE9EDF3),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, _) => const ColoredBox(
                color: Color(0xFFE9EDF3),
                child: Icon(Icons.broken_image_outlined),
              ),
              data: (data) => InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog.fullscreen(
                    backgroundColor: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          child: Image.memory(data, fit: BoxFit.contain),
                        ),
                        Positioned(
                          top: 28,
                          right: 12,
                          child: IconButton.filledTonal(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: Image.memory(data, fit: BoxFit.cover),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MediaMessageContent extends ConsumerWidget {
  const _MediaMessageContent({required this.message, required this.mine});

  final ImMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachment = message.attachments.first;
    final video = message.kind == 'video';
    final color = mine ? Colors.white : AppColors.primary;
    return SizedBox(
      width: video ? 220 : 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (video && attachment.coverObjectId.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 220,
                height: 120,
                child: ref
                    .watch(
                      imMediaAttachmentProvider((
                        attachmentId: attachment.id,
                        cover: true,
                      )),
                    )
                    .when(
                      loading: () => const ColoredBox(
                        color: Color(0xFFE9EDF3),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, _) => const ColoredBox(
                        color: Color(0xFFE9EDF3),
                        child: Icon(Icons.videocam_outlined),
                      ),
                      data: (bytes) => Image.memory(bytes, fit: BoxFit.cover),
                    ),
              ),
            ),
          Row(
            children: [
              Icon(
                video ? Icons.play_circle_outline : Icons.graphic_eq_rounded,
                color: color,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (attachment.durationSeconds != null)
                          '${attachment.durationSeconds!.round()} 秒',
                        _fileSize(attachment.size),
                      ].join(' · '),
                      style: TextStyle(
                        color: mine ? Colors.white70 : AppColors.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: color, size: 18),
            ],
          ),
          if (message.content.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message.content, style: TextStyle(color: color)),
          ],
        ],
      ),
    );
  }
}

class _AttachmentContent extends StatelessWidget {
  const _AttachmentContent({required this.item, required this.mine});

  final ImMessage item;
  final bool mine;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.insert_drive_file_rounded,
        color: mine ? Colors.white : AppColors.primary,
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.attachmentName.isEmpty ? item.content : item.attachmentName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mine ? Colors.white : AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.attachmentSize != null)
              Text(
                _fileSize(item.attachmentSize!),
                style: TextStyle(
                  fontSize: 11,
                  color: mine ? Colors.white70 : AppColors.secondaryText,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Icon(
        Icons.download_rounded,
        size: 18,
        color: mine ? Colors.white : AppColors.secondaryText,
      ),
    ],
  );
}

class _ContactCardContent extends StatelessWidget {
  const _ContactCardContent({required this.card, required this.mine});

  final ImContactCard card;
  final bool mine;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      InitialAvatar(name: card.displayName, radius: 20),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mine ? Colors.white : AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              [
                card.departmentName,
                card.username,
              ].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: mine ? Colors.white70 : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({required this.contacts});

  final List<ImMember> contacts;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final contacts = widget.contacts
        .where(
          (item) =>
              query.isEmpty ||
              item.displayName.toLowerCase().contains(query) ||
              item.username.toLowerCase().contains(query) ||
              item.departmentName.toLowerCase().contains(query),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          children: [
            const Text(
              '分享联系人',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索姓名、部门或账号',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final member = contacts[index];
                  return ListTile(
                    leading: InitialAvatar(
                      name: member.displayName,
                      radius: 21,
                      avatarDataUrl: member.avatarDataUrl,
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(
                      [
                        member.departmentName,
                        member.username,
                      ].where((value) => value.isNotEmpty).join(' · '),
                    ),
                    onTap: () => Navigator.pop(context, member),
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

String _contentType(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'bmp' => 'image/bmp',
  'mp4' || 'm4v' => 'video/mp4',
  'webm' => 'video/webm',
  'mov' => 'video/quicktime',
  'mkv' => 'video/x-matroska',
  'mp3' => 'audio/mpeg',
  'm4a' => 'audio/mp4',
  'wav' => 'audio/wav',
  'ogg' || 'oga' => 'audio/ogg',
  'flac' => 'audio/flac',
  'pdf' => 'application/pdf',
  'doc' => 'application/msword',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls' => 'application/vnd.ms-excel',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'zip' => 'application/zip',
  'txt' => 'text/plain',
  _ => 'application/octet-stream',
};

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.groups_rounded,
      size: size * .62,
      color: AppColors.primary,
    ),
  );
}
