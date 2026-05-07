import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_preferences_service.dart';

final SupabaseClient _sb = Supabase.instance.client;

/// In-app уведомления через Supabase Realtime.
/// Работает, пока приложение открыто — это намеренный выбор (без FCM).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final StreamController<List<Map<String, dynamic>>> _ctrl =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<int> _unread = StreamController<int>.broadcast();

  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _cache = const [];
  Future<void>? _init;
  Stream<List<Map<String, dynamic>>>? _streamCache;

  Stream<List<Map<String, dynamic>>> stream() {
    _init ??= _ensurePipeline();
    return _streamCache ??= _withReplay();
  }

  Stream<int> unreadCount() {
    _init ??= _ensurePipeline();
    return _unread.stream;
  }

  int get currentUnread => _cache.where((n) => n['read_at'] == null).length;

  Stream<List<Map<String, dynamic>>> _withReplay() {
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      controller.add(List<Map<String, dynamic>>.from(_cache));
      final sub = _ctrl.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: false,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Future<void> _ensurePipeline() async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      _emit(const []);
      return;
    }

    try {
      await Future<void>.delayed(Duration.zero);
      await _load();
    } catch (e) {
      debugPrint('NotificationService load error: $e');
      _emit(const []);
    }

    if (_channel != null) return;

    final channelName = 'notifs:${user.id}';
    _channel = _sb
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'Notification',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            _shouldShow(row).then((show) {
              if (!show) return;
              final next = [row, ..._cache];
              _emit(next);
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'Notification',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            final id = row['id'];
            final next = _cache
                .map((n) => n['id'].toString() == id.toString() ? row : n)
                .toList();
            _emit(next);
          },
        )
        .subscribe((status, [err]) {
          debugPrint(
            'NotificationService channel=$channelName status=$status err=$err',
          );
        });
  }

  Future<void> _load() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    final rows = await _sb
        .from('Notification')
        .select('id, type, payload, read_at, created_at, user_id')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(100);
    final visible = <Map<String, dynamic>>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      if (await _shouldShow(row)) visible.add(row);
    }
    _emit(visible);
  }

  Future<void> refresh() async {
    try {
      await _load();
    } catch (e) {
      debugPrint('NotificationService refresh error: $e');
    }
  }

  Future<void> markRead(List<dynamic> ids) async {
    if (ids.isEmpty) return;
    try {
      await _sb
          .from('Notification')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .inFilter('id', ids);
    } catch (e) {
      debugPrint('NotificationService markRead error: $e');
    }
  }

  Future<void> markAllRead() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _sb
          .from('Notification')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', uid)
          .filter('read_at', 'is', null);
    } catch (e) {
      debugPrint('NotificationService markAllRead error: $e');
    }
  }

  Future<void> createForUser({
    required String userId,
    required String type,
    required NotificationTopic topic,
    Map<String, dynamic> payload = const {},
    int? chatId,
  }) async {
    final currentUserId = _sb.auth.currentUser?.id;
    if (currentUserId == null || currentUserId == userId) return;

    final prefs = NotificationPreferencesService.instance;
    final topicEnabled = await prefs.isTopicEnabled(topic, userId);
    if (!topicEnabled) return;
    if (chatId != null && await prefs.isChatMuted(chatId, userId: userId)) {
      return;
    }

    try {
      await _sb.from('Notification').insert({
        'user_id': userId,
        'type': type,
        'payload': payload,
      });
    } catch (e) {
      debugPrint('NotificationService createForUser error: $e');
    }
  }

  Future<void> createForUsers({
    required Iterable<String> userIds,
    required String type,
    required NotificationTopic topic,
    Map<String, dynamic> payload = const {},
    int? chatId,
  }) async {
    for (final userId in userIds.toSet()) {
      await createForUser(
        userId: userId,
        type: type,
        topic: topic,
        payload: payload,
        chatId: chatId,
      );
    }
  }

  Future<bool> _shouldShow(Map<String, dynamic> notification) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;

    final type = notification['type']?.toString() ?? '';
    final payload = notification['payload'];
    final data = payload is Map ? Map<String, dynamic>.from(payload) : const {};
    final topic = _topicForType(type);
    final prefs = NotificationPreferencesService.instance;

    if (!await prefs.isTopicEnabled(topic, uid)) return false;

    final chatId = int.tryParse('${data['chat_id'] ?? ''}');
    if (topic == NotificationTopic.chats &&
        chatId != null &&
        await prefs.isChatMuted(chatId)) {
      return false;
    }

    return true;
  }

  NotificationTopic _topicForType(String type) {
    return switch (type) {
      'new_message' => NotificationTopic.chats,
      'new_bid' ||
      'auction_won' ||
      'auction_ended' ||
      'new_rating' => NotificationTopic.auctions,
      'post_liked' ||
      'post_commented' ||
      'post_quoted' => NotificationTopic.feed,
      _ => NotificationTopic.feed,
    };
  }

  void _emit(List<Map<String, dynamic>> list) {
    _cache = list;
    if (!_ctrl.isClosed) _ctrl.add(list);
    final unread = list.where((n) => n['read_at'] == null).length;
    if (!_unread.isClosed) _unread.add(unread);
  }

  void disposeAll() {
    _channel?.unsubscribe();
    _channel = null;
    _init = null;
    _streamCache = null;
    _cache = const [];
  }
}
