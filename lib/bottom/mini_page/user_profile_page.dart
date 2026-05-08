import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../database/services/chat_service.dart';
import '../../database/services/rating_service.dart';
import 'chat_screen.dart';

/// Профиль пользователя по [userId] и кнопка «Начать чат».
class UserProfilePage extends StatefulWidget {
  final String userId;

  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  static const List<String> _userTables = ['User', 'users', 'user', '"User"'];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _row;
  bool _startingChat = false;

  RatingStats _ratingStats = const RatingStats.empty();
  List<Map<String, dynamic>> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? r;
      for (final t in _userTables) {
        try {
          final row = await Supabase.instance.client
              .from(t)
              .select('id, login, username, avatar, scope, created_at, date_of_birth')
              .eq('id', widget.userId)
              .maybeSingle();
          if (row != null) {
            r = Map<String, dynamic>.from(row);
            break;
          }
        } catch (_) {}
      }
      final stats = await RatingService.instance.getStats(widget.userId);
      final reviews =
          await RatingService.instance.latestReviews(widget.userId, limit: 10);
      if (!mounted) return;
      setState(() {
        _row = r;
        _ratingStats = stats;
        _reviews = reviews;
        _loading = false;
        if (r == null) _error = 'Пользователь не найден';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _startChat() async {
    final login = _row?['login'] as String?;
    if (login == null || login.isEmpty) return;

    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите в аккаунт')),
      );
      return;
    }
    if (me == widget.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Это ваш профиль')),
      );
      return;
    }

    setState(() => _startingChat = true);
    try {
      final chat = await ChatService().createPrivateChat(login);
      if (!mounted) return;
      if (chat == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать чат')),
        );
        return;
      }
      final name = (_row?['username'] as String?) ?? login;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: (chat['id'] as num).toInt(),
            chatName: name,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  Future<void> _shareLogin() async {
    final login = (_row?['login'] as String?)?.trim();
    if (login == null || login.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: 'Профиль в GameHub: @$login'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Профиль'),
        actions: [
          IconButton(
            onPressed: _shareLogin,
            tooltip: 'Поделиться логином',
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final u = _row!;
    final login = u['login'] as String? ?? '';
    final name = u['username'] as String? ?? '';
    final avatar = u['avatar'] as String?;
    final scope = (u['scope'] as num?)?.toInt() ?? 0;

    final isSelf =
        Supabase.instance.client.auth.currentUser?.id == widget.userId;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFF7C3AED),
            backgroundImage:
                (avatar != null && avatar.isNotEmpty && avatar.startsWith('http'))
                    ? NetworkImage(avatar)
                    : null,
            child: (avatar == null || avatar.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '👤',
                    style: const TextStyle(fontSize: 40, color: Colors.white),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '@$login',
            style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 16),
          ),
        ),
        const SizedBox(height: 24),
        _ratingTile(),
        const SizedBox(height: 12),
        _tile(Icons.stars, 'Очки', '$scope ⭐'),
        if (_reviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Последние отзывы',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final r in _reviews) _reviewCard(r),
        ],
        if (!isSelf) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startingChat ? null : _startChat,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _startingChat
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.chat_bubble_outline),
              label: Text(_startingChat ? '…' : 'Начать чат'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ratingTile() {
    final avg = _ratingStats.avgStars;
    final count = _ratingStats.count;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rate_rounded, color: Color(0xFFF59E0B)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Рейтинг',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                count == 0
                    ? 'Пока нет отзывов'
                    : '${avg.toStringAsFixed(1)} · $count отзыв(ов)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: List.generate(5, (i) {
              final active = i < avg.round();
              return Icon(
                active ? Icons.star_rounded : Icons.star_border_rounded,
                color: active ? const Color(0xFFF59E0B) : Colors.white24,
                size: 18,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final stars = (r['stars'] as num?)?.toInt() ?? 0;
    final comment = (r['comment'] as String?) ?? '';
    final role = (r['role'] as String?) ?? '';
    DateTime? created;
    try {
      created = DateTime.parse(r['created_at'].toString());
    } catch (_) {}
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(5, (i) {
                  final active = i < stars;
                  return Icon(
                    active ? Icons.star_rounded : Icons.star_border_rounded,
                    color:
                        active ? const Color(0xFFF59E0B) : Colors.white24,
                    size: 16,
                  );
                }),
              ),
              const SizedBox(width: 8),
              Text(
                role == 'seller' ? 'как продавец' : 'как покупатель',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Spacer(),
              if (created != null)
                Text(
                  timeago.format(created, locale: 'ru'),
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7C3AED)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
