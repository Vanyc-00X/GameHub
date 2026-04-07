import 'package:supabase_flutter/supabase_flutter.dart';

class LocalUser {
  final String id;
  final String? email;

  LocalUser({
    required this.id,
    this.email,
  });

  factory LocalUser.fromSupabase(User user) {
    return LocalUser(
      id: user.id,
      email: user.email,
    );
  }
}