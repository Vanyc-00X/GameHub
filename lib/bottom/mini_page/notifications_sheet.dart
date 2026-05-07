import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../database/services/notification_service.dart';
import '../../database/services/profile_service.dart';

/// Лист уведомлений: Realtime-стрим из Supabase + разметка по типам.
class NotificationsSheet extends StatefulWidget {
  final ProfileService profileService;

  const NotificationsSheet({super.key, required this.profileService});

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = NotificationService.instance.stream();
    NotificationService.instance.refresh();
  }

  Future<void> _markAll() async {
    await NotificationService.instance.markAllRead();
  }

  Future<void> _markOne(Map<String, dynamic> n) async {
    if (n['read_at'] != null) return;
    await NotificationService.instance.markRead([n['id']]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Уведомления',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              TextButton(
                onPressed: _markAll,
                child: const Text(
                  'Все прочитаны',
                  style: TextStyle(color: Color(0xFF7C3AED)),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'Пока нет уведомлений',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: const Color(0xFF7C3AED),
                  onRefresh: () => NotificationService.instance.refresh(),
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (context, index) {
                      final n = items[index];
                      final isRead =
                          n['read_at'] != null || n['is_watched'] == true;
                      final view = _describe(n);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? Colors.grey.withValues(alpha: 0.3)
                              : view.color,
                          child: Icon(view.icon, size: 18, color: Colors.white),
                        ),
                        title: Text(
                          view.title,
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          view.subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Text(
                          _fmtTime(n['created_at']?.toString()),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                        onTap: () => _markOne(n),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  _NotifView _describe(Map<String, dynamic> n) {
    final type = n['type']?.toString() ?? '';
    final payload = n['payload'];
    final Map<String, dynamic> data = payload is Map
        ? Map<String, dynamic>.from(payload)
        : const {};

    switch (type) {
      case 'new_message':
        return _NotifView(
          icon: Icons.chat_bubble,
          color: const Color(0xFF7C3AED),
          title: 'Новое сообщение',
          subtitle: (data['preview'] as String?) ?? '',
        );
      case 'new_bid':
        final price = data['new_price'];
        return _NotifView(
          icon: Icons.gavel,
          color: const Color(0xFFEC4899),
          title: 'Новая ставка',
          subtitle: price != null
              ? 'Цена: $price ⭐'
              : 'Кто-то сделал ставку по вашему лоту',
        );
      case 'auction_won':
        return _NotifView(
          icon: Icons.emoji_events,
          color: const Color(0xFF34D399),
          title: 'Вы выиграли аукцион!',
          subtitle: 'Свяжитесь с продавцом',
        );
      case 'auction_ended':
        return _NotifView(
          icon: Icons.event_available,
          color: const Color(0xFFF59E0B),
          title: 'Ваш аукцион завершён',
          subtitle: 'Проверьте победителя и оцените сделку',
        );
      case 'new_rating':
        final stars = data['stars'];
        return _NotifView(
          icon: Icons.star_rate_rounded,
          color: const Color(0xFFF59E0B),
          title: 'Новая оценка',
          subtitle: stars != null ? 'Вам поставили $stars ⭐' : '',
        );
      case 'post_liked':
        return _NotifView(
          icon: Icons.favorite,
          color: const Color(0xFFEC4899),
          title: 'Ваш пост понравился',
          subtitle: 'Кто-то поставил лайк вашему посту',
        );
      case 'post_commented':
        return _NotifView(
          icon: Icons.mode_comment_outlined,
          color: const Color(0xFF7C3AED),
          title: 'Новый комментарий',
          subtitle: (data['preview'] as String?) ?? '',
        );
      case 'post_quoted':
        return _NotifView(
          icon: Icons.format_quote,
          color: const Color(0xFF34D399),
          title: 'Ваш пост процитировали',
          subtitle: (data['preview'] as String?) ?? '',
        );
      default:
        return _NotifView(
          icon: Icons.notifications,
          color: const Color(0xFF7C3AED),
          title: (n['title'] as String?) ?? 'Событие',
          subtitle: (n['content'] as String?) ?? '',
        );
    }
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    try {
      return timeago.format(DateTime.parse(iso), locale: 'ru');
    } catch (_) {
      return iso;
    }
  }
}

class _NotifView {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _NotifView({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
}
