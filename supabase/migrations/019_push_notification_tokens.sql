-- FCM-токены устройств для фоновых push-уведомлений.
-- Клиент сохраняет токен при входе; Edge Function использует его для отправки.

create table if not exists public."DevicePushToken" (
  id         bigserial primary key,
  user_id    uuid not null references public."User"(id) on delete cascade,
  token      text not null unique,
  platform   text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_push_token_user_idx
  on public."DevicePushToken" (user_id, updated_at desc);

alter table public."DevicePushToken" enable row level security;

drop policy if exists "DevicePushToken read own" on public."DevicePushToken";
create policy "DevicePushToken read own"
  on public."DevicePushToken" for select
  using (auth.uid() = user_id);

drop policy if exists "DevicePushToken insert own" on public."DevicePushToken";
create policy "DevicePushToken insert own"
  on public."DevicePushToken" for insert
  with check (auth.uid() = user_id);

drop policy if exists "DevicePushToken update own" on public."DevicePushToken";
create policy "DevicePushToken update own"
  on public."DevicePushToken" for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "DevicePushToken delete own" on public."DevicePushToken";
create policy "DevicePushToken delete own"
  on public."DevicePushToken" for delete
  using (auth.uid() = user_id);
