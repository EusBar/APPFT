-- Dispositivos com sessão na conta (lista, último acesso, aviso de novo
-- início de sessão). Só metadados: nenhum dado financeiro.
create table if not exists public.devices (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null check (length(id) between 8 and 64),
  name text not null check (length(name) between 1 and 60),
  platform text not null check (platform in ('android', 'ios', 'other')),
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (user_id, id)
);

create or replace function public.touch_last_seen() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.last_seen := now();
  return new;
end;
$$;
drop trigger if exists devices_touch on public.devices;
create trigger devices_touch before insert or update on public.devices
  for each row execute function public.touch_last_seen();

alter table public.devices enable row level security;
drop policy if exists devices_own_select on public.devices;
drop policy if exists devices_own_insert on public.devices;
drop policy if exists devices_own_update on public.devices;
drop policy if exists devices_own_delete on public.devices;
create policy devices_own_select on public.devices for select to authenticated using (user_id = (select auth.uid()));
create policy devices_own_insert on public.devices for insert to authenticated with check (user_id = (select auth.uid()));
create policy devices_own_update on public.devices for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy devices_own_delete on public.devices for delete to authenticated using (user_id = (select auth.uid()));
revoke all on public.devices from anon;
grant select, insert, update, delete on public.devices to authenticated;
