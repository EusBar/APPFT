-- Limites contra abuso (ninguém consegue encher o servidor com dados enormes).
-- O conteúdo continua cifrado; só o tamanho é verificado.
alter table public.records
  add constraint records_payload_size check (length(payload) <= 1048576),
  add constraint records_id_size check (length(id) <= 100);
alter table public.devices
  add constraint devices_name_size check (length(name) <= 60),
  add constraint devices_id_size check (length(id) <= 100),
  add constraint devices_platform check (platform in ('android', 'ios', 'other'));
alter table public.vaults
  add constraint vaults_wrap_size check (length(password_wrap) <= 4096 and length(recovery_wrap) <= 4096);

-- Apagar a conta: só utilizadores com sessão (nunca anónimos).
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
