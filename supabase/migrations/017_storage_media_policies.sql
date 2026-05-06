-- Storage policies for media uploads (chat, posts, voice, attachments, avatars).
-- Run in Supabase SQL editor for your project.

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('post-media', 'post-media', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;

-- chat-media
drop policy if exists "chat-media read" on storage.objects;
create policy "chat-media read"
  on storage.objects for select
  using (bucket_id = 'chat-media');

drop policy if exists "chat-media upload own" on storage.objects;
create policy "chat-media upload own"
  on storage.objects for insert
  with check (
    bucket_id = 'chat-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "chat-media update own" on storage.objects;
create policy "chat-media update own"
  on storage.objects for update
  using (
    bucket_id = 'chat-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "chat-media delete own" on storage.objects;
create policy "chat-media delete own"
  on storage.objects for delete
  using (
    bucket_id = 'chat-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- post-media
drop policy if exists "post-media read" on storage.objects;
create policy "post-media read"
  on storage.objects for select
  using (bucket_id = 'post-media');

drop policy if exists "post-media upload own" on storage.objects;
create policy "post-media upload own"
  on storage.objects for insert
  with check (
    bucket_id = 'post-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "post-media update own" on storage.objects;
create policy "post-media update own"
  on storage.objects for update
  using (
    bucket_id = 'post-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "post-media delete own" on storage.objects;
create policy "post-media delete own"
  on storage.objects for delete
  using (
    bucket_id = 'post-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- media (shared fallback bucket)
drop policy if exists "media read" on storage.objects;
create policy "media read"
  on storage.objects for select
  using (bucket_id = 'media');

drop policy if exists "media upload own" on storage.objects;
create policy "media upload own"
  on storage.objects for insert
  with check (
    bucket_id = 'media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "media update own" on storage.objects;
create policy "media update own"
  on storage.objects for update
  using (
    bucket_id = 'media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "media delete own" on storage.objects;
create policy "media delete own"
  on storage.objects for delete
  using (
    bucket_id = 'media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- avatars (supports path variants: avatars/{uid}/... and avatars/avatars/{uid}/...)
drop policy if exists "avatars read" on storage.objects;
create policy "avatars read"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars upload own" on storage.objects;
create policy "avatars upload own"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text in (
      (storage.foldername(name))[1],
      (storage.foldername(name))[2]
    )
  );

drop policy if exists "avatars update own" on storage.objects;
create policy "avatars update own"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text in (
      (storage.foldername(name))[1],
      (storage.foldername(name))[2]
    )
  );

drop policy if exists "avatars delete own" on storage.objects;
create policy "avatars delete own"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text in (
      (storage.foldername(name))[1],
      (storage.foldername(name))[2]
    )
  );
