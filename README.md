# GameHub

Flutter-приложение GameHub: лента, чаты, аукционы, профиль и push-уведомления (Firebase Cloud Messaging + Supabase).

## Запуск

```powershell
flutter pub get
flutter run
```

При первом запуске на Android устройстве/эмуляторе нужно положить `android/app/google-services.json` (см. ниже).

## Настройка push-уведомлений

Уведомления состоят из двух связанных частей:

1. **Внутри приложения** (in-app) — Realtime-канал Supabase (`Notification`-таблица + DB-триггеры). Работает «из коробки» после применения миграций.
2. **Push-уведомления** (FCM) — приходят, даже когда приложение свёрнуто или закрыто. Требует Firebase + Service Account на стороне Supabase.

### 1. Применение миграций Supabase

```powershell
npx supabase link --project-ref <YOUR_PROJECT_REF>
npx supabase db push
```

### 2. Firebase: подключение Android

1. Открой [Firebase Console](https://console.firebase.google.com/) и создай (или выбери) проект.
2. Добавь Android-приложение с пакетом `com.example.gamehub` (см. `android/app/build.gradle.kts` → `applicationId`).
3. Скачай `google-services.json` и положи его в `android/app/google-services.json`. Этот файл **не коммитится**, он уже в `.gitignore`.
4. Убедись, что в `android/app/build.gradle.kts` подключён `com.google.gms.google-services`, а в `android/settings.gradle.kts` — `com.google.gms.google-services` plugin.

В `AndroidManifest.xml` уже добавлено разрешение `POST_NOTIFICATIONS` (нужно для Android 13+).

### 3. Firebase: Service Account для FCM HTTP v1

Google с июня 2024 г. отключает Legacy-API (`fcm/send`). Используем **FCM HTTP v1** через Service Account.

1. Firebase Console → **Project Settings** → вкладка **Service accounts** → **Generate new private key** → скачать JSON (например, `gamehub-XXXXX-firebase-adminsdk-fbsvc-XXXXXXXXXXX.json`).
2. Этот файл — **секрет**. Он уже добавлен в `.gitignore` (паттерн `**/firebase-adminsdk*.json`). Не коммить.
3. Загрузи его в Supabase как секрет `FCM_SERVICE_ACCOUNT` (одной компактной строкой, чтобы не было проблем с переносами):

   ```powershell
   $obj = Get-Content -Raw ".\gamehub-XXXXX-firebase-adminsdk-fbsvc-XXXXXXXXXXX.json" | ConvertFrom-Json
   $oneLine = $obj | ConvertTo-Json -Compress -Depth 10
   "FCM_SERVICE_ACCOUNT=$oneLine" | Set-Content -NoNewline -Encoding utf8 .\.fcm-secret.env
   npx supabase secrets set --env-file .\.fcm-secret.env
   Remove-Item .\.fcm-secret.env
   ```

4. Деплой Edge Function:

   ```powershell
   npx supabase functions deploy send-message-push --no-verify-jwt
   ```

5. (Опционально) удалить устаревший Legacy-ключ:

   ```powershell
   npx supabase secrets unset FCM_SERVER_KEY
   ```

### 4. Проверка push end-to-end

Прямой вызов Edge Function (подставь свой `chat_id`, `sender_id` и `Bearer`-ключ — anon/publishable):

```powershell
$body = @{ record = @{ id = 999999; chat_id = 12; sender_id = "<UUID_отправителя>"; content = "TEST v1 push" } } | ConvertTo-Json -Depth 5
Invoke-RestMethod `
  -Uri "https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/send-message-push" `
  -Method POST -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer <SUPABASE_PUBLISHABLE_OR_ANON_KEY>" } `
  -Body $body | ConvertTo-Json -Depth 8
```

Ожидаемый ответ:

```json
{
  "provider": "fcm_v1",
  "sent": 1,
  "results": [
    {
      "status": 200,
      "body": { "name": "projects/<id>/messages/0:..." },
      "token": "..."
    }
  ]
}
```

На устройстве в этот момент должен прийти баннер уведомления.

### 5. Архитектура push-потока

```
Message INSERT
   │
   ▼
trg_message_push_pg_net  (Postgres trigger)
   │  net.http_post → Edge Function
   ▼
send-message-push (Deno)
   │  читает ChatMember, NotificationPreference,
   │  ChatNotificationMute, DevicePushToken
   │  подписывает JWT Service Account → access_token
   ▼
FCM HTTP v1 (messages:send)
   │
   ▼
Android-устройство (firebase_messaging)
```

### 6. Клиентская часть

- `lib/database/services/push_notification_service.dart` — инициализирует Firebase, получает FCM-токен, апсёртит в `DevicePushToken`, обрабатывает foreground/background сообщения. Если `google-services.json` отсутствует — сервис безопасно отключается (приложение не падает).
- `lib/database/services/notification_preferences_service.dart` — настройки пользователя (топики `chats` / `auctions` / `feed`, mute конкретного чата).
- `lib/bottom/mini_page/notification_settings_page.dart` — экран «Настроить уведомления» (Профиль → одноимённая кнопка).
- `lib/bottom/mini_page/chat_screen.dart` — кнопка mute/unmute в `AppBar` чата.

### 7. Полезные диагностические команды

```powershell
# Список секретов и их digests
npx supabase secrets list

# Версии задеплоенных функций
npx supabase functions list

# Кол-во сохранённых FCM-токенов
echo "select count(*) from public.\"DevicePushToken\";" | npx supabase db query --linked -f -

# Последние HTTP-ответы pg_net (вызовы Edge Function из триггера)
@"
select id, status_code, error_msg, content::text as body, created
from net._http_response
where created > now() - interval '1 hour'
order by created desc
limit 10;
"@ | Set-Content -NoNewline .\_q.sql; npx supabase db query --linked -f .\_q.sql -o table; Remove-Item .\_q.sql
```
