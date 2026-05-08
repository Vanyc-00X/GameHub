import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rating_service.dart';
import '../user_table/user_table.dart';

class ProfileService {
  final _client = Supabase.instance.client;
  final _userTable = UserTable();
  static const List<String> _userTables = ['User', 'users', 'user', '"User"'];

  // ? Описание
  Future<Map<String, dynamic>> getProfileData(String userId) async {
    final current = _client.auth.currentUser;
    if (current != null && current.id == userId) {
      await _userTable.ensureProfile(
        userId: current.id,
        username:
            (current.userMetadata?['username'] as String?)?.trim().isNotEmpty ==
                true
            ? current.userMetadata!['username'] as String
            : (current.email?.split('@').first ?? 'user'),
        email: current.email ?? '',
      );
    }

    final user =
        await _selectUserById(userId) ?? _fallbackFromAuthCurrent(userId);

    if (user == null) {
      throw Exception('Профиль не найден в базе данных');
    }

    final posts = await _client.from('Post').select('id').eq('user_id', userId);
    final postsCount = posts.length;

    final auctions = await _client
        .from('Auction_items')
        .select('id, is_active')
        .eq('owner_id', userId);

    final activeAuctions = auctions.where((a) => a['is_active'] == true).length;
    final completedAuctions = auctions.length - activeAuctions;

    final scope = (user['scope'] as num?)?.toInt() ?? 0;
    final stats = await RatingService.instance.getStats(userId);
    return {
      'user': user,
      'points': scope,
      'postsCount': postsCount,
      'activeAuctions': activeAuctions,
      'completedAuctions': completedAuctions,
      'rating': stats.avgStars,
      'ratingCount': stats.count,
      'joinedAt': user['created_at'],
    };
  }

  Future<Map<String, dynamic>?> _selectUserById(String userId) async {
    for (final table in _userTables) {
      try {
        final row = await _client
            .from(table)
            .select('id, email, login, username, scope, avatar, created_at')
            .eq('id', userId)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row);
      } catch (e) {
        debugPrint('ProfileService user table miss "$table": $e');
      }
    }
    return null;
  }

  Map<String, dynamic>? _fallbackFromAuthCurrent(String userId) {
    final current = _client.auth.currentUser;
    if (current == null || current.id != userId) return null;
    final meta = current.userMetadata ?? const {};
    final username = (meta['username'] as String?)?.trim();
    final avatar = (meta['avatar'] as String?)?.trim();
    return {
      'id': current.id,
      'email': current.email ?? '',
      'login':
          (meta['login'] as String?)?.trim() ??
          (current.email?.split('@').first ?? 'user'),
      'username': (username == null || username.isEmpty)
          ? (current.email?.split('@').first ?? 'Пользователь')
          : username,
      'scope': 0,
      'avatar': (avatar == null || avatar.isEmpty) ? null : avatar,
      'created_at': current.createdAt,
    };
  }

  /// Таблица [Notification] в схеме; при отличии регистра в PostgREST пробуем [notification].
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    Future<List<Map<String, dynamic>>> run(String table) async {
      final response = await _client
          .from(table)
          .select('id, title, content, is_watched, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response as List);
    }

    try {
      return await run('Notification');
    } catch (e) {
      debugPrint('getNotifications(Notification): $e');
    }
    try {
      return await run('notification');
    } catch (e) {
      debugPrint('getNotifications(notification): $e');
      rethrow;
    }
  }

  Future<void> markNotificationAsRead(dynamic notificationId) async {
    for (final t in ['Notification', 'notification']) {
      try {
        await _client
            .from(t)
            .update({'is_watched': true})
            .eq('id', notificationId);
        return;
      } catch (e) {
        debugPrint('markNotificationAsRead from $t: $e');
      }
    }
  }

  Future<void> markAllNotificationsAsRead(String userId) async {
    for (final t in ['Notification', 'notification']) {
      try {
        await _client
            .from(t)
            .update({'is_watched': true})
            .eq('user_id', userId);
        return;
      } catch (e) {
        debugPrint('markAll from $t: $e');
      }
    }
  }

  // ? Описание
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
