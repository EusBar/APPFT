-- FINTRACK Copilot: contagem diária de perguntas por utilizador (limite de
-- custo). Só a função bump_ai_usage escreve; ninguém lê diretamente.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  count int not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;

-- Soma uma pergunta ao dia de hoje do próprio utilizador e devolve o total.
create or replace function public.bump_ai_usage()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  if auth.uid() is null then
    raise exception 'sem sessão' using errcode = '28000';
  end if;
  insert into ai_usage (user_id, day, count)
  values (auth.uid(), current_date, 1)
  on conflict (user_id, day) do update set count = ai_usage.count + 1
  returning count into n;
  return n;
end;
$$;

revoke all on function public.bump_ai_usage() from public, anon;
grant execute on function public.bump_ai_usage() to authenticated;
