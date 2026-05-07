import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient _sb = Supabase.instance.client;

enum NotificationTopic {
  chats('chats'),
  auctions('auctions'),
  feed('feed');

  final String key;
  const NotificationTopic(this.key);
}

class NotificationPreferences {
  final bool chats;
  final bool auctions;
  final bool feed;

  const NotificationPreferences({
    this.chats = true,
    this.auctions = true,
    this.feed = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      chats: json['chats_enabled'] as bool? ?? true,
      auctions: json['auctions_enabled'] as bool? ?? true,
      feed: json['feed_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson(String userId) {
    return {
      'user_id': userId,
      'chats_enabled': chats,
      'auctions_enabled': auctions,
      'feed_enabled': feed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  bool enabled(NotificationTopic topic) {
    return switch (topic) {
      NotificationTopic.chats => chats,
      NotificationTopic.auctions => auctions,
      NotificationTopic.feed => feed,
    };
  }

  NotificationPreferences copyWith({bool? chats, bool? auctions, bool? feed}) {
    return NotificationPreferences(
      chats: chats ?? this.chats,
      auctions: auctions ?? this.auctions,
      feed: feed ?? this.feed,
    );
  }
}

class NotificationPreferencesService {
  NotificationPreferencesService._();
  static final instance = NotificationPreferencesService._();

  NotificationPreferences? _cache;
  final Set<int> _mutedChatIds = {};

  Future<NotificationPreferences> loadPreferences({
    bool refresh = false,
  }) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return const NotificationPreferences();
    if (!refresh && _cache != null) return _cache!;

    try {
      final row = await _sb
          .from('NotificationPreference')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      _cache = row == null
          ? const NotificationPreferences()
          : NotificationPreferences.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('NotificationPreferences load fallback: $e');
      _cache = const NotificationPreferences();
    }

    return _cache!;
  }

  Future<void> savePreferences(NotificationPreferences preferences) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return;

    _cache = preferences;

    try {
      await _sb
          .from('NotificationPreference')
          .upsert(preferences.toJson(userId), onConflict: 'user_id');
    } catch (e) {
      debugPrint('NotificationPreferences save skipped: $e');
    }
  }

  Future<bool> isTopicEnabled(NotificationTopic topic, String userId) async {
    final currentUserId = _sb.auth.currentUser?.id;
    if (currentUserId == userId) {
      return (await loadPreferences()).enabled(topic);
    }

    try {
      final row = await _sb
          .from('NotificationPreference')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return true;
      return NotificationPreferences.fromJson(
        Map<String, dynamic>.from(row),
      ).enabled(topic);
    } catch (e) {
      debugPrint('NotificationPreferences topic fallback: $e');
      return true;
    }
  }

  Future<bool> isChatMuted(int chatId, {String? userId}) async {
    final uid = userId ?? _sb.auth.currentUser?.id;
    if (uid == null) return false;
    if (uid == _sb.auth.currentUser?.id && _mutedChatIds.contains(chatId)) {
      return true;
    }

    try {
      final row = await _sb
          .from('ChatNotificationMute')
          .select('chat_id')
          .eq('user_id', uid)
          .eq('chat_id', chatId)
          .maybeSingle();
      final muted = row != null;
      if (muted && uid == _sb.auth.currentUser?.id) _mutedChatIds.add(chatId);
      return muted;
    } catch (e) {
      debugPrint('Chat mute read fallback: $e');
      return false;
    }
  }

  Future<void> setChatMuted(int chatId, bool muted) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return;

    if (muted) {
      _mutedChatIds.add(chatId);
    } else {
      _mutedChatIds.remove(chatId);
    }

    try {
      if (muted) {
        await _sb.from('ChatNotificationMute').upsert({
          'user_id': userId,
          'chat_id': chatId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,chat_id');
      } else {
        await _sb
            .from('ChatNotificationMute')
            .delete()
            .eq('user_id', userId)
            .eq('chat_id', chatId);
      }
    } catch (e) {
      debugPrint('Chat mute write skipped: $e');
    }
  }
}
