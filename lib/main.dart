import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'check.dart';
import 'auth_page.dart';
import 'forgot_password.dart';
import 'home.dart';
import 'reg_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://tvjggbkxmgbdtcfxggza.supabase.co',
    anonKey: 'sb_publishable_Kp7LtHGXD6zG4wLU_9B01Q_499L7I0V',
  );
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GameVault',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        primaryColor: Colors.orange,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const CheckPage(),
        '/auth': (context) => const AuthPage(),
        '/reg': (context) => const RegPage(),
        '/home': (context) => const HomePage(),
        '/forgot': (context) => const RecoveryPage(),
      },
    );
  }
}