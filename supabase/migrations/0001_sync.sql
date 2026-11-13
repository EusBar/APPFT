-- FINTRACK — sincronização cifrada ponta-a-ponta.
-- O servidor guarda apenas texto cifrado; a chave nunca sai do telemóvel
-- sem estar ela própria cifrada (pela palavra-passe ou pelo código de
-- recuperação). Cada utilizador só acede às suas linhas (Row Level Security).

-- Chave de dados do utilizador, embrulhada (nunca em claro).
create table if not exists public.vaults (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  password_wrap text not null check (length(password_wrap) < 4000),
  recovery_wrap text not null check (length(recovery_wrap) < 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Um registo cifrado por entidade (conta, movimento, compromisso, ...).
create table if not exists public.records (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in (
    'profile', 'account', 'category', 'movement', 'commitment', 'budget',
    'goal', 'goal_contribution', 'kixikila', 'kixikila_record'
  )),
  id text not null check (length(id) between 1 and 100),
  payload text not null check (length(payload) < 600000),
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, id)
);
create index if not exists records_user_updated on public.records (user_id, updated_at);

-- A hora de alteração é sempre a do servidor.
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists records_touch on public.records;
create trigger records_touch before insert or update on public.records
  for each row execute function public.touch_updated_at();
drop trigger if exists vaults_touch on public.vaults;
create trigger vaults_touch before update on public.vaults
  for each row execute function public.touch_updated_at();

-- Livro-razão imutável também na nuvem: movimentos só se acrescentam.
create or replace function public.movements_append_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.kind = 'movement' then
    raise exception 'Livro-razão imutável: os movimentos não se alteram nem se apagam';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists records_movements_append_only on public.records;
create trigger records_movements_append_only before update or delete on public.records
  for each row execute function public.movements_append_only();

-- Row Level Security: só o próprio utilizador.
alter table public.vaults enable row level security;
alter table public.records enable row level security;

drop policy if exists vaults_own_select on public.vaults;
drop policy if exists vaults_own_insert on public.vaults;
drop policy if exists vaults_own_update on public.vaults;
create policy vaults_own_select on public.vaults for select to authenticated using (user_id = (select auth.uid()));
create policy vaults_own_insert on public.vaults for insert to authenticated with check (user_id = (select auth.uid()));
create policy vaults_own_update on public.vaults for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists records_own_select on public.records;
drop policy if exists records_own_insert on public.records;
drop policy if exists records_own_update on public.records;
drop policy if exists records_own_delete on public.records;
create policy records_own_select on public.records for select to authenticated using (user_id = (select auth.uid()));
create policy records_own_insert on public.records for insert to authenticated with check (user_id = (select auth.uid()));
create policy records_own_update on public.records for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy records_own_delete on public.records for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.vaults, public.records from anon;
grant select, insert, update, delete on public.records to authenticated;
grant select, insert, update on public.vaults to authenticated;

-- Eliminar a conta dentro do app: apaga o utilizador e, em cascata, tudo.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Sem sessão';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
