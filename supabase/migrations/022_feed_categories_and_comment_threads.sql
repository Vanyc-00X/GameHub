-- Категории для статей (Post) + древовидные комментарии с цитированием.

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

alter table if exists public."Post"
  add column if not exists category_id bigint references public."PostCategory"(id) on delete set null;

create index if not exists post_category_idx on public."Post"(category_id, created_at desc);

alter table public."PostCategory" enable row level security;

drop policy if exists "PostCategory read all" on public."PostCategory";
create policy "PostCategory read all"
  on public."PostCategory" for select using (true);

drop policy if exists "PostCategory insert authenticated" on public."PostCategory";
create policy "PostCategory insert authenticated"
  on public."PostCategory" for insert with check (auth.uid() is not null);

alter table if exists public."Comment"
  add column if not exists parent_comment_id bigint references public."Comment"(id) on delete cascade;

create index if not exists comment_parent_idx on public."Comment"(post_id, parent_comment_id, created_at asc);
