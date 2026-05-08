import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uuid/uuid.dart';

import '../database/post_content_codec.dart';
import '../database/services/draft_service.dart';
import '../database/services/media_service.dart';
import '../database/services/tag_service.dart';
import 'mini_page/user_profile_page.dart';
import '../widgets/attachment_tile.dart';
import '../widgets/voice_player.dart';

final supabase = Supabase.instance.client;

/// Лента: текст, фото, цитаты, голосовые посты, вложения, хэштеги и фильтр по тегам.
class BottomFeed extends StatefulWidget {
  const BottomFeed({super.key});

  @override
  State<BottomFeed> createState() => _BottomFeedState();
}

class _BottomFeedState extends State<BottomFeed> {
  List<Map<String, dynamic>> _posts = [];
  Set<int> _likedPostIds = {};
  PostDraft? _savedDraft;
  bool _isLoading = true;
  final _postController = TextEditingController();
  final _feedSearchController = TextEditingController();
  final List<String> _draftImages = [];
  final List<AttachmentMeta> _draftAttachments = [];
  String? _draftAudioUrl;
  int? _draftAudioMs;
  Map<String, dynamic>? _currentUserProfile;
  Map<String, dynamic>? _quoteFrom;

  // Голосовая запись поста
  final _recorder = AudioRecorder();
  bool _recording = false;
  DateTime? _recordStartedAt;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTicker;
  String? _recordingPath;

  // Теги
  List<Map<String, dynamic>> _popularTags = [];
  String? _activeTag;
  Set<int>? _tagFilterPostIds;
  List<Map<String, dynamic>> _categories = [];
  int? _activeCategoryId;
  int? _composerCategoryId;

  late final RealtimeChannel _postSub;
  late final RealtimeChannel _likeSub;
  late final RealtimeChannel _commentSub;

  @override
  void initState() {
    super.initState();
    _feedSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _postController.addListener(_scheduleDraftSave);
    _fetchPosts();
    _loadPopularTags();
    _loadCategories();
    _loadDraft();
    _loadCurrentUserProfile();
    _subscribeToChanges();
  }

  Timer? _draftTimer;
  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), _persistDraft);
  }

  Future<void> _persistDraft() async {
    await DraftService.instance.save(
      PostDraft(
        text: _postController.text,
        imageUrls: List.from(_draftImages),
        audioUrl: _draftAudioUrl,
        audioDurationMs: _draftAudioMs,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _loadDraft() async {
    final d = await DraftService.instance.load();
    if (!mounted) return;
    if (d == null || d.isEmpty) return;
    if (_postController.text.isNotEmpty || _draftImages.isNotEmpty) return;
    setState(() => _savedDraft = d);
  }

  Future<void> _loadCurrentUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final row = await supabase
          .from('User')
          .select('username, login, avatar')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _currentUserProfile = Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('Не удалось загрузить профиль для composer: $e');
    }
  }

  Future<void> _restoreDraft() async {
    final d = _savedDraft;
    if (d == null) return;
    setState(() {
      _postController.text = d.text;
      _draftImages
        ..clear()
        ..addAll(d.imageUrls);
      _draftAudioUrl = d.audioUrl;
      _draftAudioMs = d.audioDurationMs;
      _savedDraft = null;
    });
  }

  Future<void> _discardSavedDraft() async {
    await DraftService.instance.clear();
    if (!mounted) return;
    setState(() => _savedDraft = null);
  }

  Future<void> _loadPopularTags() async {
    final tags = await TagService.instance.popular(limit: 10);
    if (!mounted) return;
    setState(() => _popularTags = tags);
  }

  Future<void> _loadCategories() async {
    try {
      final rows = await supabase
          .from('PostCategory')
          .select('id, name')
          .order('sort_order', ascending: true);
      if (!mounted) return;
      setState(() => _categories = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      debugPrint('Ошибка загрузки категорий: $e');
    }
  }

  Future<void> _applyTagFilter(String? tagName) async {
    if (tagName == null) {
      setState(() {
        _activeTag = null;
        _tagFilterPostIds = null;
      });
      return;
    }
    final ids = await TagService.instance.postIdsByTag(tagName);
    if (!mounted) return;
    setState(() {
      _activeTag = tagName;
      _tagFilterPostIds = ids.toSet();
    });
  }

  void _applyCategoryFilter(int? categoryId) {
    setState(() => _activeCategoryId = categoryId);
  }

  List<Map<String, dynamic>> _visiblePosts() {
    Iterable<Map<String, dynamic>> list = _posts;
    if (_tagFilterPostIds != null) {
      list = list.where(
        (post) => _tagFilterPostIds!.contains((post['id'] as num).toInt()),
      );
    }
    if (_activeCategoryId != null) {
      list = list.where(
        (post) => (post['category_id'] as num?)?.toInt() == _activeCategoryId,
      );
    }
    final q = _feedSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return list.toList();
    return list.where((post) {
      final user = post['user'] as Map<String, dynamic>? ?? {};
      final un = (user['username'] as String? ?? '').toLowerCase();
      final ln = (user['login'] as String? ?? '').toLowerCase();
      final raw = post['content'] as String? ?? '';
      final d = decodePostContent(raw);
      final searchBlob = [
        d.text,
        raw,
        un,
        '@$ln',
        d.tags.join(' '),
      ].join(' ').toLowerCase();
      return searchBlob.contains(q);
    }).toList();
  }

  Future<void> _syncLikedFlags(List<int> postIds) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null || postIds.isEmpty) {
      _likedPostIds = {};
      return;
    }
    final rows = await supabase
        .from('PostLike')
        .select('post_id')
        .eq('user_id', me);
    final want = postIds.toSet();
    final set = <int>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final pid = (r['post_id'] as num).toInt();
      if (want.contains(pid)) set.add(pid);
    }
    _likedPostIds = set;
  }

  Future<void> _syncLikeCount(int postId) async {
    final rows = await supabase
        .from('PostLike')
        .select('id')
        .eq('post_id', postId);
    final n = List.from(rows).length;
    try {
      await supabase.from('Post').update({'like': n}).eq('id', postId);
    } catch (_) {
      /* колонка like может быть зарезервирована в RLS */
    }
  }

  Future<void> _fetchPosts() async {
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .from('Post')
          .select('''
            id,
            created_at,
            content,
            like,
            user_id,
            category_id,
            category:PostCategory!category_id (id, name),
            user:User!user_id (username, avatar, login),
            likes:PostLike!post_id (count),
            comments:Comment!post_id (count)
          ''')
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data);
      final ids = list.map((e) => (e['id'] as num).toInt()).toList();
      await _syncLikedFlags(ids);

      setState(() {
        _posts = list;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки постов: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Лента: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToChanges() {
    _postSub = supabase
        .channel('post_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'Post',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();

    _likeSub = supabase
        .channel('like_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'PostLike',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();

    _commentSub = supabase
        .channel('comment_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'Comment',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();
  }

  Future<void> _toggleLike(int postId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final existing = await supabase
          .from('PostLike')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing != null) {
        await supabase.from('PostLike').delete().eq('id', existing['id']);
        _likedPostIds.remove(postId);
      } else {
        await supabase.from('PostLike').insert({
          'user_id': user.id,
          'post_id': postId,
        });
        _likedPostIds.add(postId);
        await _notifyPostOwner(postId, 'post_liked', {
          'post_id': postId,
          'sender_id': user.id,
        });
      }
      await _syncLikeCount(postId);
      await _fetchPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка лайка: $e')));
      }
    }
  }

  Future<void> _addComment(
    int postId,
    String text, {
    int? parentCommentId,
    Map<String, dynamic>? quoteSnapshot,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    try {
      final row = {
        'user_id': user.id,
        'post_id': postId,
        'parent_comment_id': parentCommentId,
        'content': _encodeComment(
          text.trim(),
          quoteSnapshot: quoteSnapshot,
        ),
      };
      try {
        await supabase.from('Comment').insert(row);
      } catch (e) {
        // Fallback for DBs where threaded comments migration isn't applied yet.
        await supabase.from('Comment').insert({
          'user_id': user.id,
          'post_id': postId,
          'content': row['content'],
        });
      }
      await _notifyPostOwner(postId, 'post_commented', {
        'post_id': postId,
        'sender_id': user.id,
        'preview': text.trim(),
      });
      await _fetchPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Комментарий: $e')));
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;
    try {
      final uploaded = await MediaService.instance.uploadPostMedia(
        file: File(x.path),
        contentType: 'image/jpeg',
      );
      if (uploaded == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось загрузить фото: проверьте storage бакеты',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _draftImages.add(uploaded.url));
      _scheduleDraftSave();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Загрузка фото: $e')));
      }
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      if (file.path == null) return;

      final uploaded = await MediaService.instance.uploadPostMedia(
        file: File(file.path!),
      );
      if (uploaded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось загрузить файл')),
          );
        }
        return;
      }
      setState(() {
        _draftAttachments.add(
          AttachmentMeta(
            url: uploaded.url,
            name: uploaded.name,
            sizeBytes: uploaded.sizeBytes,
            mime: uploaded.mime,
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Файл: $e')));
      }
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

    final dur = _recordDuration;
    final file = path != null ? File(path) : null;

    setState(() {
      _recording = false;
      _recordDuration = Duration.zero;
      _recordStartedAt = null;
      _recordingPath = null;
    });

    if (discard || file == null || dur.inMilliseconds < 400) {
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      return;
    }

    final uploaded = await MediaService.instance.uploadPostMedia(
      file: file,
      contentType: 'audio/m4a',
    );
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}

    if (uploaded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить голос')),
        );
      }
      return;
    }

    setState(() {
      _draftAudioUrl = uploaded.url;
      _draftAudioMs = dur.inMilliseconds;
    });
    _scheduleDraftSave();
  }

  Future<void> _publishPost() async {
    final base = _postController.text.trim();
    final hasContent =
        base.isNotEmpty ||
        _draftImages.isNotEmpty ||
        _draftAttachments.isNotEmpty ||
        _draftAudioUrl != null ||
        _quoteFrom != null;
    if (!hasContent) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Войдите в аккаунт')));
      return;
    }

    Map<String, dynamic>? qs;
    int? qid;
    if (_quoteFrom != null) {
      final idRaw = _quoteFrom!['id'];
      qid = idRaw is int ? idRaw : (idRaw as num).toInt();
      final u = _quoteFrom!['user'] as Map<String, dynamic>? ?? {};
      qs = {
        'id': qid,
        'text': _previewText((_quoteFrom!['content'] as String?) ?? ''),
        'user': u['username'] ?? u['login'] ?? '',
        'login': u['login'],
      };
    }

    final tags = TagService.instance.parseTags(base);
    final encoded = encodePostContent(
      PostContentData(
        text: base,
        imageUrls: List.from(_draftImages),
        quotePostId: qid,
        quoteSnapshot: qs,
        audioUrl: _draftAudioUrl,
        audioDurationMs: _draftAudioMs,
        attachments: List.from(_draftAttachments),
        tags: tags,
      ),
    );

    try {
      final inserted = await supabase
          .from('Post')
          .insert({
            'user_id': user.id,
            'content': encoded,
            'category_id': _composerCategoryId,
          })
          .select('id')
          .single();
      final postId = (inserted['id'] as num).toInt();
      if (tags.isNotEmpty) {
        await TagService.instance.upsertPostTags(postId: postId, names: tags);
        await _loadPopularTags();
      }
      if (qid != null) {
        await _notifyPostOwner(qid, 'post_quoted', {
          'post_id': qid,
          'quote_post_id': postId,
          'sender_id': user.id,
          'preview': base,
        });
      }

      _postController.clear();
      setState(() {
        _draftImages.clear();
        _draftAttachments.clear();
        _draftAudioUrl = null;
        _draftAudioMs = null;
        _quoteFrom = null;
        _composerCategoryId = null;
      });
      await DraftService.instance.clear();
      await _fetchPosts();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Пост опубликован')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _notifyPostOwner(
    int postId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    try {
      await supabase.rpc(
        'create_feed_notification',
        params: {
          'target_post_id': postId,
          'notification_type': type,
          'notification_payload': payload,
        },
      );
    } catch (e) {
      debugPrint('Feed notification skipped: $e');
    }
  }

  void _showComments(int postId) {
    final controller = TextEditingController();
    var ver = 0;
    int? replyToId;
    Map<String, dynamic>? replyToSnapshot;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1430),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setModal) {
              Future<List<Map<String, dynamic>>> load() async {
                try {
                  final r = await supabase
                      .from('Comment')
                      .select('''
                        id, user_id, parent_comment_id, content, created_at,
                        user:User!user_id (username, login, avatar)
                      ''')
                      .eq('post_id', postId)
                      .order('created_at', ascending: true);
                  return List<Map<String, dynamic>>.from(r);
                } catch (_) {
                  final r = await supabase
                      .from('Comment')
                      .select('''
                        id, user_id, content, created_at,
                        user:User!user_id (username, login, avatar)
                      ''')
                      .eq('post_id', postId)
                      .order('created_at', ascending: true);
                  final list = List<Map<String, dynamic>>.from(r);
                  for (final c in list) {
                    c['parent_comment_id'] = null;
                  }
                  return list;
                }
              }

              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Комментарии',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      key: ValueKey(ver),
                      future: load(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final comments = snapshot.data!;
                        final byParent = <int?, List<Map<String, dynamic>>>{};
                        for (final c in comments) {
                          final parent = (c['parent_comment_id'] as num?)?.toInt();
                          byParent.putIfAbsent(parent, () => []).add(c);
                        }
                        Widget buildTree(int? parentId, int depth) {
                          final items = byParent[parentId] ?? const [];
                          return Column(
                            children: items.map((c) {
                              final u = c['user'] as Map<String, dynamic>? ?? {};
                              final name = (u['username'] as String?) ?? 'user';
                              final login = (u['login'] as String?) ?? '';
                              final decoded = _decodeComment(
                                c['content'] as String? ?? '',
                              );
                              final created = DateTime.tryParse(
                                c['created_at'] as String? ?? '',
                              );
                              final uid = c['user_id'] as String?;
                              final commentId = (c['id'] as num).toInt();
                              return Padding(
                                padding: EdgeInsets.only(left: depth * 18.0, bottom: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: uid == null
                                            ? null
                                            : () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => UserProfilePage(userId: uid),
                                                  ),
                                                );
                                              },
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: const Color(0xFF7C3AED),
                                              child: Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                                style: const TextStyle(color: Colors.white),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                login.isNotEmpty ? '$name @$login' : name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            if (created != null)
                                              Text(
                                                timeago.format(created, locale: 'ru'),
                                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (decoded.quoteSnapshot != null) ...[
                                        const SizedBox(height: 6),
                                        _CommentQuoteTree(snapshot: decoded.quoteSnapshot!),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(
                                        decoded.text,
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () {
                                            replyToId = commentId;
                                            replyToSnapshot = {
                                              'comment_id': commentId,
                                              'user': name,
                                              'text': decoded.text,
                                              if (decoded.quoteSnapshot != null)
                                                'quote': decoded.quoteSnapshot,
                                            };
                                            controller.text = '@$name ';
                                            setModal(() {});
                                          },
                                          child: const Text('Ответить'),
                                        ),
                                      ),
                                      buildTree(commentId, depth + 1),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        }
                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [buildTree(null, 0)],
                        );
                      },
                    ),
                  ),
                  if (replyToSnapshot != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ответ на ${replyToSnapshot!['user']}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                            onPressed: () {
                              replyToId = null;
                              replyToSnapshot = null;
                              setModal(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      MediaQuery.of(context).viewInsets.bottom + 20,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Комментарий...',
                              hintStyle: const TextStyle(color: Colors.grey),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.1),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Color(0xFF7C3AED),
                          ),
                          onPressed: () async {
                            await _addComment(
                              postId,
                              controller.text,
                              parentCommentId: replyToId,
                              quoteSnapshot: replyToSnapshot,
                            );
                            controller.clear();
                            replyToId = null;
                            replyToSnapshot = null;
                            ver++;
                            setModal(() {});
                            await _fetchPosts();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    _draftTimer?.cancel();
    _recorder.dispose();
    _postSub.unsubscribe();
    _likeSub.unsubscribe();
    _commentSub.unsubscribe();
    _postController.removeListener(_scheduleDraftSave);
    _postController.dispose();
    _feedSearchController.dispose();
    super.dispose();
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final me = supabase.auth.currentUser;
    final visible = _visiblePosts();

    return RefreshIndicator(
      color: const Color(0xFF7C3AED),
      onRefresh: () async {
        await _fetchPosts();
        await _loadPopularTags();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Лента',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Посты, фото, голос, файлы и хэштеги',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _feedSearchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Поиск: текст, #тег, @логин, имя...',
                      hintStyle: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.grey,
                        size: 22,
                      ),
                      suffixIcon: _feedSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 20,
                              ),
                              onPressed: () {
                                _feedSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _categoriesRow(),
                  const SizedBox(height: 10),
                  _tagsRow(),
                  const SizedBox(height: 12),
                  if (_quoteFrom != null) _quoteChip(),
                  if (_savedDraft != null) _draftBanner(),
                  _composer(me, _currentUserProfile),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (_posts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    'Пока нет постов',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    _activeTag != null
                        ? 'Нет постов с тегом #$_activeTag'
                        : 'Ничего не найдено по «${_feedSearchController.text.trim()}»',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final post = visible[index];
                final postId = (post['id'] as num).toInt();
                final userData = post['user'] as Map<String, dynamic>? ?? {};
                final username =
                    userData['username'] as String? ?? 'Пользователь';
                final login = userData['login'] as String? ?? '';
                final avatarUrl = userData['avatar'] as String?;
                final userId = post['user_id'] as String?;
                final time = timeago.format(
                  DateTime.parse(post['created_at'] as String),
                  locale: 'ru',
                );
                final rawContent = post['content'] as String? ?? '';
                final parsed = decodePostContent(rawContent);
                final category =
                    post['category'] as Map<String, dynamic>?;

                final likesCount = (() {
                  final likes = post['likes'];
                  if (likes is List && likes.isNotEmpty) {
                    return (likes[0]['count'] as int?) ?? 0;
                  }
                  return 0;
                })();

                final commentsCount = (() {
                  final c = post['comments'];
                  if (c is List && c.isNotEmpty) {
                    return (c[0]['count'] as int?) ?? 0;
                  }
                  return 0;
                })();

                return _PostCardX(
                  postId: postId,
                  username: username,
                  login: login,
                  avatarUrl: avatarUrl,
                  time: time,
                  parsed: parsed,
                  rawFallback: rawContent,
                  likes: likesCount,
                  comments: commentsCount,
                  liked: _likedPostIds.contains(postId),
                  onLike: () => _toggleLike(postId),
                  onComment: () {
                    _showComments(postId);
                  },
                  onQuote: () {
                    setState(() {
                      _quoteFrom = {
                        'id': postId,
                        'content': parsed.text.isNotEmpty
                            ? parsed.text
                            : _previewText(rawContent),
                        'user': userData,
                      };
                    });
                  },
                  onTag: (t) => _applyTagFilter(t),
                  categoryName: category?['name'] as String?,
                  onOpenUser: userId == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfilePage(userId: userId),
                            ),
                          );
                        },
                );
              }, childCount: visible.length),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _tagsRow() {
    if (_popularTags.isEmpty && _activeTag == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _tagChip(
            label: 'Все',
            active: _activeTag == null,
            onTap: () => _applyTagFilter(null),
          ),
          if (_activeTag != null &&
              !_popularTags.any((t) => t['name'].toString() == _activeTag))
            _tagChip(
              label: '#$_activeTag',
              active: true,
              onTap: () => _applyTagFilter(null),
            ),
          for (final t in _popularTags)
            _tagChip(
              label: '#${t['name']}',
              active: _activeTag == t['name'].toString(),
              onTap: () => _applyTagFilter(t['name'].toString()),
            ),
        ],
      ),
    );
  }

  Widget _categoriesRow() {
    if (_categories.isEmpty && _activeCategoryId == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _tagChip(
            label: 'Все категории',
            active: _activeCategoryId == null,
            onTap: () => _applyCategoryFilter(null),
          ),
          for (final c in _categories)
            _tagChip(
              label: c['name'].toString(),
              active: _activeCategoryId == (c['id'] as num).toInt(),
              onTap: () => _applyCategoryFilter((c['id'] as num).toInt()),
            ),
        ],
      ),
    );
  }

  Widget _tagChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF7C3AED)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _quoteChip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B69).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.format_quote, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Цитата: ${_previewText(_quoteFrom!['content'] as String? ?? '')}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            onPressed: () => setState(() => _quoteFrom = null),
          ),
        ],
      ),
    );
  }

  Widget _draftBanner() {
    final d = _savedDraft!;
    final preview = d.text.trim().isNotEmpty
        ? d.text.trim()
        : (d.imageUrls.isNotEmpty
              ? '📷 ${d.imageUrls.length} фото'
              : (d.audioUrl != null ? '🎤 голосовое' : 'черновик'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B69).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Есть черновик',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _restoreDraft,
            child: const Text(
              'Продолжить',
              style: TextStyle(color: Color(0xFF7C3AED)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            onPressed: _discardSavedDraft,
          ),
        ],
      ),
    );
  }

  String? _composerHashtagQuery() {
    final text = _postController.text;
    final m = RegExp(r'(?:^|\s)#([\p{L}\p{N}_]{1,40})$', unicode: true)
        .firstMatch(text);
    if (m == null) return null;
    return m.group(1)?.toLowerCase();
  }

  Widget _composer(User? me, Map<String, dynamic>? profile) {
    final avatarUrl = profile?['avatar'] as String?;
    final username = profile?['username'] as String?;
    final login = profile?['login'] as String?;
    final fallback = username?.isNotEmpty == true
        ? username![0].toUpperCase()
        : (login?.isNotEmpty == true
              ? login![0].toUpperCase()
              : (me?.email?.isNotEmpty == true
                    ? me!.email![0].toUpperCase()
                    : '?'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF7C3AED),
                radius: 20,
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                        fallback,
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _postController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Что нового? Пиши #теги...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                    border: InputBorder.none,
                  ),
                  minLines: 2,
                  maxLines: 6,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _tagChip(
                  label: 'Без категории',
                  active: _composerCategoryId == null,
                  onTap: () => setState(() => _composerCategoryId = null),
                ),
                for (final c in _categories)
                  _tagChip(
                    label: c['name'].toString(),
                    active: _composerCategoryId == (c['id'] as num).toInt(),
                    onTap: () => setState(
                      () => _composerCategoryId = (c['id'] as num).toInt(),
                    ),
                  ),
              ],
            ),
          ),
          if (_composerHashtagQuery() != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._popularTags
                    .where(
                      (t) => t['name']
                          .toString()
                          .startsWith(_composerHashtagQuery()!),
                    )
                    .take(5)
                    .map(
                      (t) => ActionChip(
                        label: Text('#${t['name']}'),
                        onPressed: () {
                          final q = _composerHashtagQuery()!;
                          _postController.text = _postController.text.replaceFirst(
                            RegExp(
                              '#$q\$',
                              caseSensitive: false,
                              unicode: true,
                            ),
                            '#${t['name']} ',
                          );
                          _postController.selection = TextSelection.collapsed(
                            offset: _postController.text.length,
                          );
                          setState(() {});
                        },
                      ),
                    ),
                ActionChip(
                  label: Text('Создать #${_composerHashtagQuery()!}'),
                  onPressed: () {
                    final q = _composerHashtagQuery()!;
                    if (!_postController.text.endsWith(' ')) {
                      _postController.text = '${_postController.text} ';
                    }
                    _postController.text = _postController.text.replaceAll(
                      RegExp('#$q\\s*\$', caseSensitive: false, unicode: true),
                      '#$q ',
                    );
                    _postController.selection = TextSelection.collapsed(
                      offset: _postController.text.length,
                    );
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
          if (_draftImages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _draftImages
                  .map(
                    (u) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            u,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () => setState(() => _draftImages.remove(u)),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ],
          if (_draftAudioUrl != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: VoicePlayer(
                    url: _draftAudioUrl!,
                    durationMs: _draftAudioMs,
                    background: const Color(0xFF0F0F1A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => setState(() {
                    _draftAudioUrl = null;
                    _draftAudioMs = null;
                  }),
                ),
              ],
            ),
          ],
          if (_draftAttachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _draftAttachments
                  .map(
                    (a) => Stack(
                      children: [
                        AttachmentTile(meta: a),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: InkWell(
                            onTap: () =>
                                setState(() => _draftAttachments.remove(a)),
                            child: const Icon(
                              Icons.cancel,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ],
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.fiber_manual_record,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Запись ${_fmtDur(_recordDuration)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _stopRecording(discard: true),
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                  ),
                  IconButton(
                    onPressed: () => _stopRecording(discard: false),
                    icon: const Icon(Icons.check, color: Color(0xFF7C3AED)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: _pickImage,
                icon: const Icon(
                  Icons.image_outlined,
                  color: Color(0xFF7C3AED),
                ),
                tooltip: 'Фото',
              ),
              IconButton(
                onPressed: _pickAttachment,
                icon: const Icon(Icons.attach_file, color: Color(0xFF7C3AED)),
                tooltip: 'Файл',
              ),
              if (_draftAudioUrl == null && !_recording)
                IconButton(
                  onPressed: _startRecording,
                  icon: const Icon(Icons.mic, color: Color(0xFF7C3AED)),
                  tooltip: 'Голос',
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: _publishPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Опубликовать',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _previewText(String s) {
  if (s.startsWith('GHPOST:')) {
    final d = decodePostContent(s);
    return d.text.isNotEmpty
        ? d.text
        : (s.length > 80 ? '${s.substring(0, 80)}…' : s);
  }
  return s.length > 120 ? '${s.substring(0, 120)}…' : s;
}

const String _commentPrefix = 'GHCOMMENT:';

String _encodeComment(String text, {Map<String, dynamic>? quoteSnapshot}) {
  if (quoteSnapshot == null || quoteSnapshot.isEmpty) return text;
  return '$_commentPrefix${jsonEncode({'t': text, 'qs': quoteSnapshot})}';
}

_CommentPayload _decodeComment(String raw) {
  final s = raw.trim();
  if (!s.startsWith(_commentPrefix)) return _CommentPayload(text: raw);
  try {
    final body = s.substring(_commentPrefix.length);
    final map = Map<String, dynamic>.from(jsonDecode(body) as Map);
    return _CommentPayload(
      text: map['t']?.toString() ?? '',
      quoteSnapshot: map['qs'] is Map
          ? Map<String, dynamic>.from(map['qs'] as Map)
          : null,
    );
  } catch (_) {
    return _CommentPayload(text: raw);
  }
}

class _CommentPayload {
  final String text;
  final Map<String, dynamic>? quoteSnapshot;
  const _CommentPayload({required this.text, this.quoteSnapshot});
}

class _CommentQuoteTree extends StatelessWidget {
  final Map<String, dynamic> snapshot;
  const _CommentQuoteTree({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final user = (snapshot['user'] as String?) ?? 'Комментарий';
    final text = _previewText((snapshot['text'] as String?) ?? '');
    final nested = snapshot['quote'] is Map
        ? Map<String, dynamic>.from(snapshot['quote'] as Map)
        : null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.35), width: 2),
        ),
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$user:',
            style: const TextStyle(
              color: Color(0xFFBDA8FF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (text.isNotEmpty)
            Text(
              text,
              style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.3),
            ),
          if (nested != null) ...[
            const SizedBox(height: 6),
            _CommentQuoteTree(snapshot: nested),
          ],
        ],
      ),
    );
  }
}

class _PostCardX extends StatelessWidget {
  final int postId;
  final String username;
  final String login;
  final String? avatarUrl;
  final String time;
  final PostContentData parsed;
  final String rawFallback;
  final int likes;
  final int comments;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onQuote;
  final ValueChanged<String> onTag;
  final VoidCallback? onOpenUser;
  final String? categoryName;

  const _PostCardX({
    required this.postId,
    required this.username,
    required this.login,
    required this.avatarUrl,
    required this.time,
    required this.parsed,
    required this.rawFallback,
    required this.likes,
    required this.comments,
    required this.liked,
    required this.onLike,
    required this.onComment,
    required this.onQuote,
    required this.onTag,
    this.onOpenUser,
    this.categoryName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: const Border(
          top: BorderSide(color: Color(0xFF2F3336), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onOpenUser,
                borderRadius: BorderRadius.circular(20),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF7C3AED),
                  backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                      ? NetworkImage(avatarUrl!)
                      : null,
                  child: avatarUrl == null || avatarUrl!.isEmpty
                      ? const Icon(Icons.person, color: Colors.white, size: 22)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: onOpenUser,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: username,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' @$login · $time',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (parsed.text.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        parsed.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ] else if (!parsed.hasMedia &&
                        !parsed.hasQuote &&
                        !parsed.hasVoice &&
                        !parsed.hasAttachments) ...[
                      const SizedBox(height: 6),
                      Text(
                        _stripCodec(rawFallback),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if ((categoryName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Категория: $categoryName',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (parsed.hasQuote) _QuoteBlock(data: parsed),
                    if (parsed.hasMedia) ...[
                      const SizedBox(height: 10),
                      ...parsed.imageUrls.map(
                        (u) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  u,
                                  width: constraints.maxWidth,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerLeft,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Text('…'),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                    if (parsed.hasVoice) ...[
                      const SizedBox(height: 10),
                      VoicePlayer(
                        url: parsed.audioUrl!,
                        durationMs: parsed.audioDurationMs,
                      ),
                    ],
                    if (parsed.hasAttachments) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: parsed.attachments
                            .map((a) => AttachmentTile(meta: a))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onComment,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$comments',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: onQuote,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.repeat,
                        size: 18,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Цитата',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: onLike,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: liked ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likes',
                        style: TextStyle(
                          color: liked ? Colors.red : Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _stripCodec(String raw) {
    if (raw.startsWith('GHPOST:')) {
      return decodePostContent(raw).text;
    }
    return raw;
  }
}

class _QuoteBlock extends StatelessWidget {
  final PostContentData data;

  const _QuoteBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    final s = data.quoteSnapshot;
    final preview = _previewText(s?['text'] as String? ?? '');
    final u = s?['user'] as String? ?? s?['login'] as String? ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF536471)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (u.isNotEmpty)
            Text(
              u,
              style: const TextStyle(
                color: Color(0xFF7C3AED),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (preview.isNotEmpty)
            Text(
              preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }
}
