-- Información completa para ladrón y cómplices, daños ocultos y gestión
-- manual de cuadrantes. Ejecutar después de los demás scripts de juego.

delete from public.game_player_notices where title = 'Has sufrido daños';

drop function if exists public.my_compass_secret(uuid);
create function public.my_compass_secret(p_room_id uuid)
returns table(role text, secret_word text, can_cause_damage boolean, can_pay_bribes boolean, members jsonb)
language sql security definer set search_path = public stable as $$
  with mystery as (
    select m.thief_participant_id, m.accomplice_participant_ids, m.secret_word,
      case
        when m.thief_participant_id = (select auth.uid()) then 'thief'
        when (select auth.uid()) = any(m.accomplice_participant_ids) then 'accomplice'
      end as role
    from public.game_room_mysteries m
    where m.room_id = p_room_id
  )
  select mystery.role,
    case when mystery.role is not null then mystery.secret_word end,
    mystery.role is not null and settings.clue_enabled and not exists (
      select 1 from public.game_compass_sabotages sabotage
      where sabotage.room_id = p_room_id
        and sabotage.sabotage_round = settings.sabotage_round
        and sabotage.attacker_user_id = (select auth.uid())
    ),
    mystery.role = 'thief' and not exists (
      select 1 from public.game_compass_bribes bribe where bribe.room_id = p_room_id
    ),
    case when mystery.role is not null then (
      select jsonb_agg(jsonb_build_object(
        'team', assignment.team,
        'position_name', assignment.position_name,
        'is_self', assignment.user_id = (select auth.uid())
      ) order by assignment.user_id = (select auth.uid()) desc)
      from public.game_assignments assignment
      where assignment.room_id = p_room_id
        and assignment.participant_id in (mystery.thief_participant_id, mystery.accomplice_participant_ids[1], mystery.accomplice_participant_ids[2])
    ) end
  from mystery
  join public.game_room_purchase_settings settings on settings.room_id = p_room_id;
$$;

-- No se crea aviso ni push al dañar a alguien: solo se descubre al completar
-- la misión secundaria afectada.
create or replace function public.cause_compass_damage(p_room_id uuid, p_target_participant_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_round integer; v_is_villain boolean;
begin
  select sabotage_round into v_round
  from public.game_room_purchase_settings
  where room_id = p_room_id and clue_enabled;
  if v_round is null then raise exception 'El admin debe activar las compras de pistas'; end if;
  select exists(
    select 1 from public.game_room_mysteries mystery
    where mystery.room_id = p_room_id
      and (mystery.thief_participant_id = (select auth.uid()) or (select auth.uid()) = any(mystery.accomplice_participant_ids))
  ) into v_is_villain;
  if not v_is_villain then raise exception 'Solo el ladrón y sus cómplices pueden causar daños'; end if;
  if not exists(
    select 1 from public.game_assignments
    where room_id = p_room_id and participant_id = p_target_participant_id and participant_type = 'real'
  ) then raise exception 'Elige un jugador real de esta partida'; end if;
  insert into public.game_compass_sabotages(room_id, sabotage_round, attacker_user_id, target_participant_id)
  values (p_room_id, v_round, (select auth.uid()), p_target_participant_id);
  return 'Daños causados.';
exception when unique_violation then raise exception 'Ya has usado tus daños en esta activación';
end;
$$;

alter table public.game_team_quadrants drop constraint if exists game_team_quadrants_source_check;
alter table public.game_team_quadrants add constraint game_team_quadrants_source_check
  check (source in ('initial', 'secret', 'purchase', 'unlocked', 'admin'));

create or replace function public.admin_change_team_quadrant(
  p_room_id uuid,
  p_team text,
  p_quadrant text,
  p_add boolean
)
returns text language plpgsql security definer set search_path = public as $$
declare v_team text := lower(trim(p_team)); v_quadrant text := upper(trim(p_quadrant));
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede modificar cuadrantes'; end if;
  if v_team not in ('red', 'blue', 'green', 'yellow') then raise exception 'Equipo no válido'; end if;
  if v_quadrant not in ('A','B','C','D','E','F','G','H','I') then raise exception 'Cuadrante no válido'; end if;

  if p_add then
    insert into public.game_team_quadrants(room_id, team, quadrant, source)
    values (p_room_id, v_team, v_quadrant, 'admin')
    on conflict (room_id, team, quadrant) do update set source = 'admin';
    return format('Cuadrante %s disponible para el equipo %s.', v_quadrant, initcap(v_team));
  end if;

  delete from public.game_team_quadrant_locations
  where room_id = p_room_id and team = v_team and quadrant = v_quadrant;
  delete from public.game_team_quadrant_location_purchases
  where room_id = p_room_id and team = v_team and quadrant = v_quadrant;
  delete from public.game_team_quadrants
  where room_id = p_room_id and team = v_team and quadrant = v_quadrant;
  if not found then raise exception 'Ese equipo no tenía el cuadrante %s', v_quadrant; end if;
  return format('Cuadrante %s retirado del equipo %s.', v_quadrant, initcap(v_team));
end;
$$;

grant execute on function public.my_compass_secret(uuid) to authenticated;
grant execute on function public.cause_compass_damage(uuid, uuid) to authenticated;
grant execute on function public.admin_change_team_quadrant(uuid, text, text, boolean) to authenticated;
