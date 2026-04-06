import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthServices {
  final _client = Supabase.instance.client;

  /// Хэширование пароля (SHA-256)
  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// ✅ РЕГИСТРАЦИЯ (signUp) — используйте этот метод!
  Future<User?> signUp({
    required String email,
    required String password,
    required String login,
    required String username,
  }) async {
    try {
      final hashedPassword = _hashPassword(password);
      
      // 1️⃣ Вставляем в public.users с хэшированным паролем
      final response = await _client
          .from('users')
          .insert({
            'email': email,
            'login': login,
            'username': username,
            'password': hashedPassword,
          })
          .select()
          .maybeSingle();

      if (response == null) {
        debugPrint('❌ Регистрация не удалась: нет ответа от сервера');
        return null;
      }

      debugPrint('✅ Регистрация успешна: $email');
      
      // 2️⃣ Возвращаем фиктивного User для совместимости
      // (т.к. мы не используем auth.users, создаём объект вручную)
      return User(
        id: response['id'] ?? '',
        email: email,
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      
    } on PostgrestException catch (e) {
      debugPrint('❌ Ошибка БД при регистрации: ${e.message}');
      if (e.message.contains('duplicate key')) {
        throw AuthException('Пользователь с таким email или логином уже существует');
      }
      rethrow;
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      rethrow;
    }
  }

  /// ✅ ВХОД (signIn) — используйте этот метод!
  Future<User?> signIn(String email, String password) async {
    try {
      final hashedPassword = _hashPassword(password);
      
      // Ищем пользователя по email и сверяем хэш пароля
      final user = await _client
          .from('users')
          .select()
          .eq('email', email)
          .eq('password', hashedPassword)
          .maybeSingle();

      if (user == null) {
        debugPrint('❌ Неверный email или пароль');
        throw AuthException('Неверный email или пароль');
      }

      debugPrint('✅ Вход успешен: $email');
      
      // Возвращаем User объект
      return User(
        id: user['id'] ?? '',
        email: user['email'],
        aud: 'authenticated',
        createdAt: user['created_at'] ?? DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      
    } catch (e) {
      debugPrint('❌ Ошибка при входе: $e');
      rethrow;
    }
  }

  /// Выход из системы (очищаем локальные данные)
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Текущий пользователь (всегда null, т.к. не используем auth)
  User? get currentUser => _client.auth.currentUser;

  /// Поток изменений авторизации
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Получить профиль пользователя из public.users
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      return await _client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
    } catch (e) {
      debugPrint('❌ Ошибка получения профиля: $e');
      return null;
    }
  }

  /// Получить пользователя по login
  Future<Map<String, dynamic>?> getUserByLogin(String login) async {
    try {
      return await _client
          .from('users')
          .select()
          .eq('login', login)
          .maybeSingle();
    } catch (e) {
      debugPrint('❌ Ошибка поиска по login: $e');
      return null;
    }
  }
}