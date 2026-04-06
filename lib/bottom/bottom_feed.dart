import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

final supabase = Supabase.instance.client;

class BottomFeed extends StatefulWidget {
  const BottomFeed({super.key});

  @override
  State<BottomFeed> createState() => _BottomFeedState();
}

class _BottomFeedState extends State<BottomFeed> {
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  final TextEditingController _postController = TextEditingController();

  late final RealtimeChannel _postSub;
  late final RealtimeChannel _likeSub;
  late final RealtimeChannel _commentSub;

  @override
  void initState() {
    super.initState();
    _fetchPosts();
    _subscribeToChanges();
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
            user:User!user_id (username, avatar),
            likes:PostLike!post_id (count),
            comments:Comment!post_id (count)
          ''')
          .order('created_at', ascending: false);

      setState(() {
        _posts = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('Ошибка загрузки постов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить ленту')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToChanges() {
    _postSub = supabase.channel('post_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'Post',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();

    _likeSub = supabase.channel('like_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'PostLike',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();

    _commentSub = supabase.channel('comment_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'Comment',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();
  }

  // === ЛАЙКИ ===
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
      } else {
        await supabase.from('PostLike').insert({
          'user_id': user.id,
          'post_id': postId,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка лайка: $e')),
        );
      }
    }
  }

  // === КОММЕНТАРИИ ===
  Future<void> _addComment(int postId, String text) async {
    final user = supabase.auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    try {
      await supabase.from('Comment').insert({
        'user_id': user.id,
        'post_id': postId,
        'content': text.trim(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки комментария')),
        );
      }
    }
  }

  void _showComments(int postId) {
    final controller = TextEditingController();

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
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text("Комментарии", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: supabase
                      .from('Comment')
                      .stream(primaryKey: ['id'])
                      .eq('post_id', postId)
                      .order('created_at'),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final comments = snapshot.data!;

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: comments.length,
                      itemBuilder: (context, i) {
                        final c = comments[i];
                        return ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xFF7C3AED), child: Text('👤')),
                          title: const Text('Пользователь', style: TextStyle(color: Colors.white)),
                          subtitle: Text(c['content'] ?? '', style: const TextStyle(color: Colors.white70)),
                          trailing: Text(
                            timeago.format(DateTime.parse(c['created_at']), locale: 'ru'),
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Напишите комментарий...",
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF7C3AED)),
                      onPressed: () async {
                        await _addComment(postId, controller.text);
                        controller.clear();
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _publishPost() async {
    final content = _postController.text.trim();
    if (content.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Войдите в аккаунт')));
      return;
    }

    try {
      await supabase.from('Post').insert({'user_id': user.id, 'content': content});
      _postController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пост опубликован')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  void dispose() {
    _postSub.unsubscribe();
    _likeSub.unsubscribe();
    _commentSub.unsubscribe();
    _postController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 60, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Лента", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                Text("Новости, обсуждения и сделки", style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),

          // Composer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF7C3AED),
                        radius: 20,
                        child: Text(supabase.auth.currentUser?.email?.isNotEmpty == true ? supabase.auth.currentUser!.email![0].toUpperCase() : "😎"),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _postController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "Поделитесь мыслями или предложением...",
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                            border: InputBorder.none,
                          ),
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ActionButton(icon: "📷"),
                      _ActionButton(icon: "🎮"),
                      _ActionButton(icon: "🔗"),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _publishPost,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Опубликовать", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text("🔥 Популярное сегодня", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(height: 12),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator()))
          else if (_posts.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(50), child: Text("Пока нет постов", style: TextStyle(color: Colors.grey))))
          else
            ..._posts.map((post) {
              final postId = post['id'] as int;
              final userData = post['user'] as Map<String, dynamic>? ?? {};
              final username = userData['username'] ?? 'Пользователь';
              final avatar = userData['avatar'] ?? '🎮';
              final time = timeago.format(DateTime.parse(post['created_at'] as String), locale: 'ru');
              final content = post['content'] as String;

              // Правильное извлечение количества лайков и комментариев
              final likesCount = (post['likes'] is List && post['likes'].isNotEmpty)
                  ? (post['likes'][0]['count'] as int? ?? 0)
                  : 0;

              final commentsCount = (post['comments'] is List && post['comments'].isNotEmpty)
                  ? (post['comments'][0]['count'] as int? ?? 0)
                  : 0;

              return _PostCard(
                postId: postId,
                avatar: avatar,
                username: username,
                time: time,
                content: content,
                likes: likesCount.toString(),
                comments: commentsCount.toString(),
                onLike: () => _toggleLike(postId),
                onComment: () => _showComments(postId),
              );
            }).toList(),
        ],
      ),
    );
  }
}

// ====================== Вспомогательные виджеты ======================

class _ActionButton extends StatelessWidget {
  final String icon;
  const _ActionButton({required this.icon, super.key});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: Text(icon, style: const TextStyle(fontSize: 20)),
      );
}

class _PostCard extends StatelessWidget {
  final int postId;
  final String avatar, username, time, content, likes, comments;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const _PostCard({
    super.key,
    required this.postId,
    required this.avatar,
    required this.username,
    required this.time,
    required this.content,
    required this.likes,
    required this.comments,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1430),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: const Color(0xFF7C3AED), radius: 19, child: Text(avatar, style: const TextStyle(fontSize: 18))),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(content, style: const TextStyle(color: Colors.white70, height: 1.4)),
          const SizedBox(height: 16),
          Row(
            children: [
              GestureDetector(onTap: onLike, child: _PostAction(icon: "❤️", count: likes, color: Colors.redAccent)),
              const SizedBox(width: 24),
              GestureDetector(onTap: onComment, child: _PostAction(icon: "💬", count: comments)),
              const Spacer(),
              const Icon(Icons.share_outlined, color: Colors.grey, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostAction extends StatelessWidget {
  final String icon;
  final String count;
  final Color? color;

  const _PostAction({required this.icon, required this.count, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: TextStyle(fontSize: 18, color: color)),
        const SizedBox(width: 6),
        Text(count, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}