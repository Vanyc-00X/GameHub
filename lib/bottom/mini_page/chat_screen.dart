import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uuid/uuid.dart';

import '../../database/message_content_codec.dart';
import '../../database/services/chat_service.dart';
import '../../database/services/media_service.dart';
import '../../database/services/notification_preferences_service.dart';
import '../../widgets/attachment_tile.dart';
import '../../widgets/voice_player.dart';

final supabase = Supabase.instance.client;

/// Экран отдельного чата с текстом, голосом и файловыми вложениями.
class ChatScreen extends StatefulWidget {
  final int chatId;
  final String chatName;

  const ChatScreen({super.key, required this.chatId, required this.chatName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatService = ChatService();
  final _recorder = AudioRecorder();

  bool _recording = false;
  bool _canceling = false;
  String? _recordingPath;
  DateTime? _recordStartedAt;
  Timer? _recordTicker;
  Duration _recordDuration = Duration.zero;

  bool _sending = false;
  bool _muted = false;

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await _sendEncoded(MessageContentData(text: text));
  }

  @override
  void initState() {
    super.initState();
    _loadMuteState();
  }

  Future<void> _loadMuteState() async {
    final muted = await NotificationPreferencesService.instance.isChatMuted(
      widget.chatId,
    );
    if (!mounted) return;
    setState(() => _muted = muted);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    await NotificationPreferencesService.instance.setChatMuted(
      widget.chatId,
      next,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Уведомления этого чата отключены'
              : 'Уведомления этого чата включены',
        ),
      ),
    );
  }

  Future<void> _sendEncoded(MessageContentData data) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _chatService.sendMessage(
        chatId: widget.chatId,
        content: encodeMessageContent(data),
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка отправки: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, '${const Uuid().v4()}.m4a');
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
        path: path,
      );
      _recordingPath = path;
      _recordStartedAt = DateTime.now();
      _recordDuration = Duration.zero;
      _canceling = false;
      _recordTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_recordStartedAt != null) {
          setState(() {
            _recordDuration = DateTime.now().difference(_recordStartedAt!);
          });
        }
      });
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Запись: $e')));
      }
    }
  }

  Future<void> _stopRecording({required bool discard}) async {
    _recordTicker?.cancel();
    _recordTicker = null;

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _recordingPath;
    }

    final duration = _recordDuration;
    final file = (path != null) ? File(path) : null;

    setState(() {
      _recording = false;
      _canceling = false;
      _recordDuration = Duration.zero;
      _recordStartedAt = null;
      _recordingPath = null;
    });

    if (discard || file == null || duration.inMilliseconds < 400) {
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      return;
    }

    final uploaded = await MediaService.instance.uploadChatMedia(
      chatId: widget.chatId,
      file: file,
      contentType: 'audio/m4a',
    );

    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}

    if (uploaded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить голосовое')),
        );
      }
      return;
    }

    await _sendEncoded(
      MessageContentData(
        audioUrl: uploaded.url,
        audioDurationMs: duration.inMilliseconds,
      ),
    );
  }

  Future<void> _pickAttachment() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final path = f.path;
      if (path == null) return;

      final uploaded = await MediaService.instance.uploadChatMedia(
        chatId: widget.chatId,
        file: File(path),
      );
      if (uploaded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось загрузить файл')),
          );
        }
        return;
      }
      await _sendEncoded(
        MessageContentData(
          text: _messageController.text.trim(),
          attachments: [
            AttachmentMeta(
              url: uploaded.url,
              name: uploaded.name,
              sizeBytes: uploaded.sizeBytes,
              mime: uploaded.mime,
            ),
          ],
        ),
      );
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Файл: $e')));
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    _recorder.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatName),
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _muted ? 'Включить уведомления' : 'Заглушить чат',
            onPressed: _toggleMute,
            icon: Icon(
              _muted
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.messagesStream(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Ошибка: ${snapshot.error}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Нет сообщений',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == currentUserId;
                    final data = decodeMessageContent(
                      msg['content']?.toString(),
                    );
                    final time = timeago.format(
                      DateTime.parse(msg['created_at'] as String),
                      locale: 'ru',
                    );

                    return _MessageBubble(isMe: isMe, data: data, time: time);
                  },
                );
              },
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _inputBar() {
    final padding = const EdgeInsets.fromLTRB(12, 8, 12, 20);
    final decoration = BoxDecoration(
      color: const Color(0xFF1A1430),
      border: Border(
        top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
    );

    if (_recording) {
      return Container(
        padding: padding,
        decoration: decoration,
        child: Row(
          children: [
            Icon(
              Icons.mic,
              color: _canceling ? Colors.redAccent : const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _canceling
                    ? 'Отпустите для отмены'
                    : 'Запись... ${_fmtDur(_recordDuration)}',
                style: TextStyle(
                  color: _canceling ? Colors.redAccent : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _stopRecording(discard: true),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
            IconButton(
              onPressed: () => _stopRecording(discard: false),
              icon: const Icon(Icons.send, color: Color(0xFF7C3AED)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: padding,
      decoration: decoration,
      child: Row(
        children: [
          IconButton(
            onPressed: _sending ? null : _pickAttachment,
            icon: const Icon(Icons.attach_file, color: Colors.grey),
            tooltip: 'Файл',
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Напишите сообщение...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _sendText(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 4),
          if (_messageController.text.trim().isEmpty)
            GestureDetector(
              onLongPress: _startRecording,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Удерживайте для записи голосового'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF7C3AED),
                ),
                child: const Icon(Icons.mic, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF7C3AED)),
              onPressed: _sending ? null : _sendText,
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isMe;
  final MessageContentData data;
  final String time;

  const _MessageBubble({
    required this.isMe,
    required this.data,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe
        ? const Color(0xFF7C3AED)
        : Colors.white.withValues(alpha: 0.08);
    final textColor = isMe ? Colors.white : Colors.white70;

    final items = <Widget>[];

    if (data.hasText) {
      items.add(
        Text(data.text, style: TextStyle(color: textColor, fontSize: 16)),
      );
    }

    if (data.hasImages) {
      for (final u in data.imageUrls) {
        if (items.isNotEmpty) items.add(const SizedBox(height: 6));
        items.add(
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              u,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        );
      }
    }

    if (data.hasVoice) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 6));
      items.add(
        VoicePlayer(
          url: data.audioUrl!,
          durationMs: data.audioDurationMs,
          background: isMe
              ? Colors.white.withValues(alpha: 0.18)
              : const Color(0xFF0F0F1A),
        ),
      );
    }

    if (data.hasAttachments) {
      for (final a in data.attachments) {
        if (items.isNotEmpty) items.add(const SizedBox(height: 6));
        items.add(
          AttachmentTile(
            meta: a,
            background: isMe
                ? Colors.white.withValues(alpha: 0.18)
                : const Color(0xFF0F0F1A),
          ),
        );
      }
    }

    if (items.isEmpty) {
      items.add(Text('...', style: TextStyle(color: textColor)));
    }

    items.add(const SizedBox(height: 4));
    items.add(
      Text(
        time,
        style: TextStyle(
          fontSize: 11,
          color: isMe ? Colors.white70 : Colors.grey,
        ),
      ),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: items,
        ),
      ),
    );
  }
}
