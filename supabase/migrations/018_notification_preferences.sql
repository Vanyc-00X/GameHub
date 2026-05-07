-- Настройки in-app уведомлений: общие типы + mute конкретных чатов.

alter table public."Notification"
  add column if not exists type text not null default 'new_message',
  add column if not exists payload jsonb not null default '{}'::jsonb,
  add column if not exists read_at timestamptz;

alter table public."Notification"
  alter column title drop not null;

create index if not exists notification_user_unread_idx
  on public."Notification" (user_id, read_at, created_at desc);

create table if not exists public."NotificationPreference" (
  user_id          uuid primary key references public."User"(id) on delete cascade,
  chats_enabled    boolean not null default true,
  auctions_enabled boolean not null default true,
  feed_enabled     boolean not null default true,
  updated_at       timestamptz not null default now()
);

alter table public."NotificationPreference" enable row level security;

drop policy if exists "NotificationPreference read own" on public."NotificationPreference";
create policy "NotificationPreference read own"
  on public."NotificationPreference" for select
  using (auth.uid() = user_id);

drop policy if exists "NotificationPreference upsert own" on public."NotificationPreference";
create policy "NotificationPreference upsert own"
  on public."NotificationPreference" for insert
  with check (auth.uid() = user_id);

drop policy if exists "NotificationPreference update own" on public."NotificationPreference";
create policy "NotificationPreference update own"
  on public."NotificationPreference" for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public."ChatNotificationMute" (
  user_id    uuid not null references public."User"(id) on delete cascade,
  chat_id    bigint not null references public."Chat"(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, chat_id)
);

alter table public."ChatNotificationMute" enable row level security;

drop policy if exists "ChatNotificationMute read own" on public."ChatNotificationMute";
create policy "ChatNotificationMute read own"
  on public."ChatNotificationMute" for select
  using (auth.uid() = user_id);

drop policy if exists "ChatNotificationMute insert own" on public."ChatNotificationMute";
create policy "ChatNotificationMute insert own"
  on public."ChatNotificationMute" for insert
  with check (auth.uid() = user_id);

drop policy if exists "ChatNotificationMute delete own" on public."ChatNotificationMute";
create policy "ChatNotificationMute delete own"
  on public."ChatNotificationMute" for delete
  using (auth.uid() = user_id);

create or replace function public._notifications_topic_enabled(
  target_user uuid,
  topic text
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case topic
    when 'chats' then coalesce(p.chats_enabled, true)
    when 'auctions' then coalesce(p.auctions_enabled, true)
    when 'feed' then coalesce(p.feed_enabled, true)
    else true
  end
  from (select 1) s
  left join public."NotificationPreference" p on p.user_id = target_user;
$$;

create or replace function public._chat_notifications_muted(
  target_user uuid,
  target_chat bigint
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public."ChatNotificationMute" m
    where m.user_id = target_user
      and m.chat_id = target_chat
  );
$$;

create or replace function public._notify_new_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public."Notification" (user_id, type, payload)
  select
    cm.user_id,
    'new_message',
    jsonb_build_object(
      'chat_id',    new.chat_id,
      'message_id', new.id,
      'sender_id',  new.sender_id,
      'preview',    left(coalesce(new.content,''), 120)
    )
  from public."ChatMember" cm
  where cm.chat_id = new.chat_id
    and cm.user_id <> new.sender_id
    and public._notifications_topic_enabled(cm.user_id, 'chats')
    and not public._chat_notifications_muted(cm.user_id, new.chat_id);
  return new;
end;
$$;

do $$
begin
  if to_regclass('public."Message"') is not null then
    drop trigger if exists trg_notify_new_message on public."Message";
    create trigger trg_notify_new_message
      after insert on public."Message"
      for each row execute function public._notify_new_message();
  end if;
end $$;

create or replace function public._notify_new_bid()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  owner uuid;
begin
  select owner_id into owner from public."Auction_items" where id = new.auction_id;
  if owner is null
     or owner = new.user_id
     or not public._notifications_topic_enabled(owner, 'auctions') then
    return new;
  end if;

  insert into public."Notification" (user_id, type, payload)
  values (
    owner,
    'new_bid',
    jsonb_build_object(
      'auction_id', new.auction_id,
      'bidder_id',  new.user_id,
      'new_price',  new.new_price
    )
  );
  return new;
end;
$$;

do $$
begin
  if to_regclass('public."Bid_auction"') is not null then
    drop trigger if exists trg_notify_new_bid on public."Bid_auction";
    create trigger trg_notify_new_bid
      after insert on public."Bid_auction"
      for each row execute function public._notify_new_bid();
  end if;
end $$;

create or replace function public._notify_auction_finalized()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.winner_id is not null
     and (old.winner_id is null or old.winner_id <> new.winner_id) then

    if public._notifications_topic_enabled(new.winner_id, 'auctions') then
      insert into public."Notification" (user_id, type, payload)
      values (
        new.winner_id,
        'auction_won',
        jsonb_build_object('auction_id', new.id, 'owner_id', new.owner_id)
      );
    end if;

    if new.owner_id is not null
       and new.owner_id <> new.winner_id
       and public._notifications_topic_enabled(new.owner_id, 'auctions') then
      insert into public."Notification" (user_id, type, payload)
      values (
        new.owner_id,
        'auction_ended',
        jsonb_build_object('auction_id', new.id, 'winner_id', new.winner_id)
      );
    end if;
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public."Auction_items"') is not null then
    drop trigger if exists trg_notify_auction_finalized on public."Auction_items";
    create trigger trg_notify_auction_finalized
      after update on public."Auction_items"
      for each row execute function public._notify_auction_finalized();
  end if;
end $$;

create or replace function public._notify_new_rating()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public._notifications_topic_enabled(new.target_id, 'auctions') then
    return new;
  end if;

  insert into public."Notification" (user_id, type, payload)
  values (
    new.target_id,
    'new_rating',
    jsonb_build_object(
      'rater_id',  new.rater_id,
      'auction_id', new.auction_id,
      'stars',     new.stars,
      'role',      new.role
    )
  );
  return new;
end;
$$;

do $$
begin
  if to_regclass('public."User_rating"') is not null then
    drop trigger if exists trg_notify_new_rating on public."User_rating";
    create trigger trg_notify_new_rating
      after insert on public."User_rating"
      for each row execute function public._notify_new_rating();
  end if;
end $$;

create or replace function public.create_feed_notification(
  target_post_id bigint,
  notification_type text,
  notification_payload jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
  actor uuid := auth.uid();
begin
  if actor is null
     or notification_type not in ('post_liked', 'post_commented', 'post_quoted') then
    return;
  end if;

  select user_id into owner
  from public."Post"
  where id = target_post_id;

  if owner is null
     or owner = actor
     or not public._notifications_topic_enabled(owner, 'feed') then
    return;
  end if;

  insert into public."Notification" (user_id, type, payload)
  values (
    owner,
    notification_type,
    coalesce(notification_payload, '{}'::jsonb) || jsonb_build_object(
      'post_id', target_post_id,
      'sender_id', actor
    )
  );
end;
$$;
