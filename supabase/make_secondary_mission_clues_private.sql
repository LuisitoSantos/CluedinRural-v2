-- Las pistas obtenidas por misiones secundarias son personales: solo las ve
-- quien completó la misión. Las pistas iniciales y del Compás siguen siendo
-- compartidas por equipo, y las pistas perdidas se mantienen en el saco del
-- equipo como hasta ahora.
-- Ejecutar después de add_secondary_missions.sql.

drop policy if exists "Teams can read secondary clues" on public.game_team_secondary_clues;
drop policy if exists "Players can read their secondary clues" on public.game_team_secondary_clues;
create policy "Players can read their secondary clues"
on public.game_team_secondary_clues for select to authenticated
using (
  public.is_game_room_admin(room_id)
  or exists (
    select 1
    from public.game_assignments own_assignment
    where own_assignment.room_id = game_team_secondary_clues.room_id
      and own_assignment.user_id = (select auth.uid())
      and own_assignment.participant_id = game_team_secondary_clues.participant_id
  )
);

create or replace function public.complete_secondary_mission(p_room_id uuid, p_mission_id text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_mission public.game_secondary_missions%rowtype;
  v_sabotage_id bigint;
begin
  select * into v_mission from public.game_secondary_missions
  where room_id = p_room_id and user_id = (select auth.uid()) and completed_at is null
  order by mission_number limit 1;
  if not found then raise exception 'No tienes más misiones secundarias pendientes'; end if;
  if v_mission.mission_id <> trim(p_mission_id) then raise exception 'Ese ID no corresponde a tu misión actual'; end if;
  update public.game_secondary_missions set completed_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  select id into v_sabotage_id from public.game_compass_sabotages
  where room_id = p_room_id and target_participant_id = v_mission.participant_id and consumed_at is null
  order by caused_at limit 1 for update skip locked;
  if found then
    update public.game_compass_sabotages set consumed_at = now() where id = v_sabotage_id;
    update public.game_secondary_missions set reward_withheld = true
    where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
    insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
    values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number,
      'Pista perdida por daños. Puede recuperarse del saco del equipo por 15 monedas.');
    return 'Misión completada. Los daños han retenido tu pista: el equipo puede recuperarla del saco por 15 monedas.';
  end if;
  if v_mission.reward_withheld then
    insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
    values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number,
      'Pista perdida. Ha pasado al saco de pistas del equipo y puede recuperarse por 15 monedas.');
    return 'Misión completada. Esta vez tu pista ha pasado al saco de pistas del equipo.';
  end if;
  insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
  values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number,
    format('Pista recibida por misión %s: %s', v_mission.mission_number, v_mission.clue));
  update public.game_secondary_missions set clue_revealed_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  return 'Misión completada. Has recibido una pista.';
end;
$$;

create or replace function public.purchase_team_lost_clue(p_room_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_team text; v_family text; v_mission public.game_secondary_missions%rowtype;
begin
  select team, role_name into v_team, v_family from public.game_assignments
  where room_id = p_room_id and user_id = (select auth.uid());
  if not found then raise exception 'Debes tener una casilla asignada para comprar'; end if;
  if not coalesce((select clue_enabled from public.game_room_purchase_settings where room_id = p_room_id), false) then
    raise exception 'Esta compra no está activada por el admin';
  end if;
  update public.game_family_balances set coins = coins - 15
  where room_id = p_room_id and team = v_team and family_name = v_family and coins >= 15;
  if not found then raise exception 'Tu equipo no tiene suficientes monedas'; end if;
  select * into v_mission from public.game_secondary_missions
  where room_id = p_room_id and team = v_team and reward_withheld
    and completed_at is not null and clue_purchased_at is null
  order by random() limit 1;
  if not found then return 'No quedaban pistas perdidas en el saco de tu equipo. Se han gastado las monedas.'; end if;
  update public.game_secondary_missions set clue_purchased_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
  values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number,
    format('Pista recuperada de misión %s: %s', v_mission.mission_number, v_mission.clue))
  on conflict (room_id, participant_id, mission_number) do update set clue = excluded.clue;
  return 'El jugador que completó esa misión ha recuperado su pista del saco por 15 monedas.';
end;
$$;

grant execute on function public.complete_secondary_mission(uuid, text) to authenticated;
grant execute on function public.purchase_team_lost_clue(uuid) to authenticated;
