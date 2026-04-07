import 'package:supabase_flutter/supabase_flutter.dart';

class UserTable {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> addUserTable({
    required String userId,
    required String username,
    required String email,
    String? fullName,
    String? avatar,
  }) async {
    try {
      await _client.from('User').insert({
        'id': userId,
        'username': username,
        'email': email,
        'login': username.toLowerCase(),
        'password': '', // Supabase Auth хранит пароль сам, сюда лучше не писать
        'username': username,
        'avatar': avatar ?? '',
        'scope': 0,
      });
    } catch (e) {
      print('Ошибка при создании профиля пользователя: $e');
    }
  }

  Future<void> updateAvatar(String userId, String avatarUrl) async {
    await _client.from('User').update({'avatar': avatarUrl}).eq('id', userId);
  }

  Future<void> updateUsername(String userId, String newUsername) async {
    await _client.from('User').update({'username': newUsername}).eq('id', userId);
  }
}