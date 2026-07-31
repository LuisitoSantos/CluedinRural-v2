-- Ejecutar este parche si ya ejecutaste add_persistent_player_accounts.sql.
create or replace function public.authenticate_game_player(p_display_name text, p_pin text)
returns table(auth_user_id uuid, display_name text)
language plpgsql security definer set search_path = public, extensions as $$
declare account public.game_player_accounts%rowtype;
begin
  if auth.uid() is null
     or char_length(trim(p_display_name)) not between 1 and 40
     or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'Nombre o PIN no valido';
  end if;

  select * into account
  from public.game_player_accounts as player_account
  where lower(player_account.display_name) = lower(trim(p_display_name));

  if not found then
    insert into public.game_player_accounts(display_name, pin_hash, auth_user_id)
    values (trim(p_display_name), extensions.crypt(p_pin, extensions.gen_salt('bf')), auth.uid())
    returning * into account;
  elsif extensions.crypt(p_pin, account.pin_hash) <> account.pin_hash then
    raise exception 'El PIN no es correcto';
  elsif account.auth_user_id <> auth.uid() then
    update public.game_room_players set user_id = auth.uid() where user_id = account.auth_user_id;
    update public.game_rooms set admin_user_id = auth.uid() where admin_user_id = account.auth_user_id;
    update public.game_player_accounts set auth_user_id = auth.uid()
    where id = account.id returning * into account;
  end if;

  return query select account.auth_user_id, account.display_name;
end;
$$;

grant execute on function public.authenticate_game_player(text, text) to authenticated;
