import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_table/user_table.dart';

class AuthServices {
  final _client = Supabase.instance.client;
  final _userTable = UserTable();

  // ? Описание
  Future<User?> signIn(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      // На случай аккаунтов, созданных до триггера on_auth_user_created.
      await ensureProfile();
      return response.user;
    } on AuthException catch (e) {
      debugPrint('Login error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected login error: $e');
      rethrow;
    }
  }

  // ? Регистрирует пользователя в auth.users и гарантирует создание
  // профиля в public."User". Серверный триггер on_auth_user_created
  // отрабатывает всегда (в т.ч. при включённом email-подтверждении);
  // клиентский insert — это подстраховка на случай, если миграция
  // ещё не накатана и сессия уже есть.
  Future<User?> signUp(
    String email,
    String password, {
    String? username,
  }) async {
    try {
      final safeEmail = email.trim();
      final safeUsername = (username == null || username.trim().isEmpty)
          ? safeEmail.split('@').first
          : username.trim();

      final response = await _client.auth.signUp(
        email: safeEmail,
        password: password,
        data: {'username': safeUsername},
      );

      final user = response.user;
      if (user != null && _client.auth.currentSession != null) {
        await _userTable.ensureProfile(
          userId: user.id,
          username: safeUsername,
          email: safeEmail,
        );
      }

      return user;
    } on AuthException catch (e) {
      debugPrint('Register error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected register error: $e');
      rethrow;
    }
  }

  // Создаёт запись в public."User", если её ещё нет (на случай входа
  // со старого аккаунта, для которого триггер не сработал).
  Future<void> ensureProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    DateTime? dob;
    final rawDob = user.userMetadata?['date_of_birth'];
    if (rawDob != null) {
      try {
        dob = DateTime.parse(rawDob.toString());
      } catch (_) {}
    }
    await _userTable.ensureProfile(
      userId: user.id,
      username:
          (user.userMetadata?['username'] as String?)?.trim().isNotEmpty == true
          ? user.userMetadata!['username'] as String
          : (user.email?.split('@').first ?? 'user'),
      email: user.email ?? '',
      dateOfBirth: dob,
    );
  }

  // ? Описание
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ? Описание
  User? get currentUser => _client.auth.currentUser;

  // ? Описание
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}
