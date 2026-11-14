-- Subscrições Premium confirmadas pelo servidor junto da Google Play e da
-- App Store. O telemóvel só lê a sua própria linha; só o servidor escreve.
create table if not exists public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  platform text not null check (platform in ('android', 'ios')),
  product_id text not null check (length(product_id) <= 100),
  original_id text not null check (length(original_id) <= 300),
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table public.subscriptions enable row level security;

drop policy if exists subscriptions_own_select on public.subscriptions;
create policy subscriptions_own_select on public.subscriptions
  for select to authenticated using (user_id = (select auth.uid()));
