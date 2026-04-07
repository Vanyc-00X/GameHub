import '/database/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthServices {
  final Supabase supabase = Supabase.instance;

  Future<LocalUser?> singIn(String email, String password)async{
    try {

      AuthResponse userGet = await supabase.client.auth.signInWithPassword(
        password : password, 
        email: email
        );

        User user = userGet.user!;

      return LocalUser.fromSupabase(user);
    } catch (e) {
      return null;
    }
  }

    Future<LocalUser?> singUp(String email, String password)async{
    try {

      AuthResponse userGet = await supabase.client.auth.signUp(
        password : password, 
        email: email
        );

        User user = userGet.user!;

      return LocalUser.fromSupabase(user);
    } catch (e) {
      return null;
    }
  }

  Future logOut()async{
    try{
      await supabase.client.auth.signOut();
    } catch (e) {
      return;
    }
  }

  Future recoveryPassword(String email) async {
    try {
      await supabase.client.auth.resetPasswordForEmail(email);
    } catch (e) {
      return;
    }
  }
}