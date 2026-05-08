import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'check.dart';
import 'forgot_password.dart';
import 'home.dart';
import 'reg_page.dart';
import 'database/services/push_notification_service.dart';
import 'widgets/swipe_back_wrapper.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// ? Системная панель «Назад/Домой/Обзор»: [MainActivity.kt] + SystemChrome после кадра (Flutter иначе сбрасывает insets).
void _applyHideAndroidNav() {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarDividerColor: Color(0x00000000),
    ),
  );
}

// ? Инициализация приложения и Supabase-клиента
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tvjggbkxmgbdtcfxggza.supabase.co',
    anonKey: 'sb_publishable_Kp7LtHGXD6zG4wLU_9B01Q_499L7I0V',
  );
  await PushNotificationService.instance.initialize();

  runApp(const MainApp());
}

// ? Корневой виджет приложения с настройкой темы и маршрутов
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyHideAndroidNav());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyHideAndroidNav();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'GameHub',
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
      builder: (context, child) {
        return SwipeBackWrapper(
          navigatorKey: rootNavigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
