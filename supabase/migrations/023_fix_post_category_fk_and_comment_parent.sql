-- Fix relation metadata for Post -> PostCategory and threaded comments.
-- Needed when a previous migration version was marked applied but columns/FKs were not present.

create table if not exists public."PostCategory" (
  id bigserial primary key,
  name text not null unique,
  sort_order int not null default 100,
  created_at timestamptz not null default now()
);

insert into public."PostCategory" (name, sort_order)
values
  ('Новости', 10),
  ('Обзоры', 20),
  ('Гайды', 30),
  ('Аукционы', 40),
  ('Обсуждение', 50)
on conflict (name) do nothing;

alter table public."Post"
  add column if not exists category_id bigint;

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'Post'
      and c.conname = 'post_category_id_fkey'
  ) then
    alter table public."Post"
      add constraint post_category_id_fkey
      foreign key (category_id) references public."PostCategory"(id) on delete set null;
  end if;
end $$;

create index if not exists post_category_idx on public."Post"(category_id, created_at desc);

alter table public."Comment"
  add column if not exists parent_comment_id bigint;

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'Comment'
      and c.conname = 'comment_parent_comment_id_fkey'
  ) then
    alter table public."Comment"
      add constraint comment_parent_comment_id_fkey
      foreign key (parent_comment_id) references public."Comment"(id) on delete cascade;
  end if;
end $$;

create index if not exists comment_parent_idx on public."Comment"(post_id, parent_comment_id, created_at asc);
