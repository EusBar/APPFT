-- Eliminar a conta tem de poder apagar também os movimentos (em cascata).
-- Só delete_my_account() liga esta exceção, e só durante a transação.
create or replace function public.movements_append_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.kind = 'movement'
     and coalesce(current_setting('fintrack.deleting_account', true), '') <> 'on' then
    raise exception 'Livro-razão imutável: os movimentos não se alteram nem se apagam';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Sem sessão';
  end if;
  perform set_config('fintrack.deleting_account', 'on', true);
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
