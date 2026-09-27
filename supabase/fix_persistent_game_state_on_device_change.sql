-- Conserva una partida ya iniciada cuando un jugador entra desde otro
-- dispositivo con su mismo nombre y PIN. Ejecutar después de los scripts
-- de cuentas persistentes y de los scripts del juego.

create or replace function public.transfer_game_player_identity(p_previous_user_id uuid, p_current_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_previous_user_id = p_current_user_id then return; end if;
  update public.game_room_players set user_id = p_current_user_id where user_id = p_previous_user_id;
  update public.game_rooms set admin_user_id = p_current_user_id where admin_user_id = p_previous_user_id;
  update public.game_assignments set participant_id = p_current_user_id, user_id = p_current_user_id
  where participant_type = 'real' and (participant_id = p_previous_user_id or user_id = p_previous_user_id);
  update public.game_team_clues set target_participant_id = p_current_user_id where target_participant_id = p_previous_user_id;
  update public.game_secondary_missions
  set participant_id = case when participant_id = p_previous_user_id then p_current_user_id else participant_id end,
      user_id = case when user_id = p_previous_user_id then p_current_user_id else user_id end,
      target_participant_id = case when target_participant_id = p_previous_user_id then p_current_user_id else target_participant_id end
  where participant_id = p_previous_user_id or user_id = p_previous_user_id or target_participant_id = p_previous_user_id;
  update public.game_team_secondary_clues set participant_id = p_current_user_id where participant_id = p_previous_user_id;
  update public.game_room_mysteries
  set thief_participant_id = case when thief_participant_id = p_previous_user_id then p_current_user_id else thief_participant_id end,
      compass_holder_participant_id = case when compass_holder_participant_id = p_previous_user_id then p_current_user_id else compass_holder_participant_id end,
      accomplice_participant_ids = array(
        select case when member_id = p_previous_user_id then p_current_user_id else member_id end
        from unnest(accomplice_participant_ids) as member_id
      )
  where thief_participant_id = p_previous_user_id
     or compass_holder_participant_id = p_previous_user_id
     or p_previous_user_id = any(accomplice_participant_ids);
  update public.game_compass_sabotages
  set attacker_user_id = case when attacker_user_id = p_previous_user_id then p_current_user_id else attacker_user_id end,
      target_participant_id = case when target_participant_id = p_previous_user_id then p_current_user_id else target_participant_id end
  where attacker_user_id = p_previous_user_id or target_participant_id = p_previous_user_id;
  update public.game_compass_bribes set paid_by = p_current_user_id where paid_by = p_previous_user_id;
  update public.game_family_purchase_log set bought_by = p_current_user_id where bought_by = p_previous_user_id;
  update public.game_player_notices set user_id = p_current_user_id where user_id = p_previous_user_id;
  update public.game_push_subscriptions set user_id = p_current_user_id where user_id = p_previous_user_id;
  update public.game_scheduled_events set created_by = p_current_user_id where created_by = p_previous_user_id;
end;
$$;

create or replace function public.authenticate_game_player(p_display_name text, p_pin text)
returns table(auth_user_id uuid, display_name text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  account public.game_player_accounts%rowtype;
  v_previous_user_id uuid;
  v_current_user_id uuid := auth.uid();
  v_room_id uuid;
  v_orphan_participant_id uuid;
begin
  if v_current_user_id is null or char_length(trim(p_display_name)) not between 1 and 40 or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'Nombre o PIN no válido';
  end if;
  select * into account from public.game_player_accounts as player_account
  where lower(player_account.display_name) = lower(trim(p_display_name));
  if not found then
    insert into public.game_player_accounts(display_name, pin_hash, auth_user_id)
    values (trim(p_display_name), extensions.crypt(p_pin, extensions.gen_salt('bf')), v_current_user_id)
    returning * into account;
  elsif extensions.crypt(p_pin, account.pin_hash) <> account.pin_hash then
    raise exception 'El PIN no es correcto';
  elsif account.auth_user_id <> v_current_user_id then
    v_previous_user_id := account.auth_user_id;
    perform public.transfer_game_player_identity(v_previous_user_id, v_current_user_id);
    update public.game_player_accounts set auth_user_id = v_current_user_id where id = account.id returning * into account;
  end if;

  -- Recupera el único estado huérfano que pudo dejar la versión anterior
  -- del login. No toca nada si hay más de una asignación huérfana.
  for v_room_id in select room_id from public.game_room_players where user_id = v_current_user_id loop
    if exists (select 1 from public.game_assignments where room_id = v_room_id and user_id = v_current_user_id) then continue; end if;
    select assignment.participant_id into v_orphan_participant_id
    from public.game_assignments assignment
    where assignment.room_id = v_room_id and assignment.participant_type = 'real'
      and not exists (select 1 from public.game_room_players member where member.room_id = assignment.room_id and member.user_id = assignment.user_id)
    group by assignment.participant_id
    having count(*) = 1 and (select count(*) from public.game_assignments orphan_assignment
      where orphan_assignment.room_id = v_room_id and orphan_assignment.participant_type = 'real'
        and not exists (select 1 from public.game_room_players orphan_member
          where orphan_member.room_id = orphan_assignment.room_id and orphan_member.user_id = orphan_assignment.user_id)) = 1;
    if v_orphan_participant_id is not null then
      perform public.transfer_game_player_identity(v_orphan_participant_id, v_current_user_id);
    end if;
  end loop;
  return query select account.auth_user_id, account.display_name;
end;
$$;

revoke all on function public.transfer_game_player_identity(uuid, uuid) from public;
grant execute on function public.authenticate_game_player(text, text) to authenticated;
