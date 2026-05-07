import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient _sb = Supabase.instance.client;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    debugPrint(
      '🔔 BG push: ${message.messageId} type=${message.data['type']} '
      'chat=${message.data['chat_id']} title=${message.notification?.title}',
    );
  } catch (e) {
    debugPrint('Firebase background init skipped: $e');
  }
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _ready = false;
  FirebaseMessaging? _messaging;

  Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _requestPermissions();
      _listenAuthAndToken();
      _listenForegroundMessages();
      await saveTokenForCurrentUser();
      _ready = true;
      debugPrint('🔔 PushNotificationService: ready');
    } catch (e, st) {
      debugPrint('PushNotificationService disabled: $e');
      debugPrint('$st');
    }
  }

  Future<void> _requestPermissions() async {
    final settings = await _messaging?.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      '🔔 FCM permission: ${settings?.authorizationStatus}',
    );
  }

  void _listenAuthAndToken() {
    _sb.auth.onAuthStateChange.listen((event) {
      debugPrint('🔔 auth event ${event.event}, refreshing FCM token');
      saveTokenForCurrentUser();
    });
    _messaging?.onTokenRefresh.listen((token) {
      debugPrint('🔔 FCM onTokenRefresh: ${token.substring(0, 12)}…');
      _saveToken(token);
    });
  }

  void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        '🔔 FG push: ${message.notification?.title ?? message.data['type']} '
        'data=${message.data}',
      );
    });
  }

  Future<void> saveTokenForCurrentUser() async {
    final messaging = _messaging;
    if (messaging == null) {
      debugPrint('🔔 saveTokenForCurrentUser: messaging is null, skip');
      return;
    }
    try {
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('🔔 FCM getToken returned null/empty');
        return;
      }
      debugPrint('🔔 FCM token: ${token.substring(0, 12)}… len=${token.length}');
      await _saveToken(token);
    } catch (e) {
      debugPrint('FCM token read skipped: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null || token.isEmpty) {
      debugPrint('🔔 _saveToken skip: userId=$userId tokenLen=${token.length}');
      return;
    }

    try {
      await _sb.from('DevicePushToken').upsert({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      debugPrint('🔔 DevicePushToken upserted for $userId');
    } catch (e) {
      debugPrint('FCM token save skipped: $e');
    }
  }
}
