import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final _client = Supabase.instance.client;

  Future<Map<String, dynamic>> getProfileData(String userId) async {
    final user = await _client
        .from('User')
        .select('id, email, login, username, scope, avatar, created_at')
        .eq('id', userId)
        .maybeSingle();

    if (user == null) {
      throw Exception('Профиль не найден в базе данных');
    }

    final posts = await _client
        .from('Post')
        .select('id')
        .eq('user_id', userId);
    final postsCount = posts.length;

    final auctions = await _client
        .from('Auction_items')
        .select('id, is_active')
        .eq('owner_id', userId);
    
    final activeAuctions = auctions.where((a) => a['is_active'] == true).length;
    final completedAuctions = auctions.length - activeAuctions;

    return {
      'user': user,
      'postsCount': postsCount,
      'activeAuctions': activeAuctions,
      'completedAuctions': completedAuctions,
      'rating': 4.9,
      'joinedAt': user['created_at'],
    };
  }

  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    try {
      final response = await _client
          .from('Notification')
          .select('id, title, content, is_watched, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      
      return response;
    } catch (e) {
      print('❌ Ошибка загрузки уведомлений: $e');
      return [];
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _client
          .from('Notification')
          .update({'is_watched': true})
          .eq('id', notificationId);
    } catch (e) {
      print('❌ Ошибка обновления уведомления: $e');
    }
  }

  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      await _client
          .from('Notification')
          .update({'is_watched': true})
          .eq('user_id', userId)
          .eq('is_watched', false);
    } catch (e) {
      print('❌ Ошибка обновления всех уведомлений: $e');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}