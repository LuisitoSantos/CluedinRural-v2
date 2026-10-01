-- Permite el reparto alternativo de misiones en partidas pequeñas con
-- equipos de tamaños distintos. Ejecutar después de add_secondary_missions.sql.
-- Cuando no puede igualarse el total por equipo sin dejar jugadores fuera,
-- cada jugador recibe una misión única sobre otro equipo.

create or replace function public.save_secondary_missions(p_room_id uuid, p_missions jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_team text; v_lost_count integer; v_min_team_missions integer; v_max_team_missions integer;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede iniciar la partida'; end if;
  if jsonb_typeof(p_missions) <> 'array' then raise exception 'Las misiones no son válidas'; end if;
  if exists (
    select 1 from public.game_assignments a where a.room_id = p_room_id and a.participant_type = 'real'
    and not exists (select 1 from jsonb_array_elements(p_missions) m where (m->>'participant_id')::uuid = a.participant_id)
  ) then raise exception 'Faltan misiones para algún jugador'; end if;

  delete from public.game_team_secondary_clues where room_id = p_room_id;
  delete from public.game_team_compass_clues where room_id = p_room_id;
  delete from public.game_compass_sabotages where room_id = p_room_id;
  delete from public.game_compass_bribes where room_id = p_room_id;
  update public.game_room_purchase_settings set sabotage_round = 0 where room_id = p_room_id;
  delete from public.game_secondary_missions where room_id = p_room_id;
  insert into public.game_secondary_missions(room_id, participant_id, user_id, team, mission_number, mission_id, mission_level, mission_action, clue, target_participant_id, clue_type)
  select p_room_id, a.participant_id, a.user_id, a.team,
    (m->>'mission_number')::integer, m->>'mission_id', (m->>'mission_level')::integer,
    m->>'mission_action', m->>'clue', (m->>'target_participant_id')::uuid, m->>'clue_type'
  from jsonb_array_elements(p_missions) m
  join public.game_assignments a on a.room_id = p_room_id and a.participant_id = (m->>'participant_id')::uuid
  join public.game_assignments target on target.room_id = p_room_id and target.participant_id = (m->>'target_participant_id')::uuid
  where target.team <> a.team;

  if exists (
    select 1 from public.game_assignments a where a.room_id = p_room_id and a.participant_type = 'real'
    and not exists (select 1 from public.game_secondary_missions m where m.room_id = p_room_id and m.participant_id = a.participant_id)
  ) then raise exception 'Faltan misiones secundarias para algún jugador'; end if;
  select min(mission_count), max(mission_count) into v_min_team_missions, v_max_team_missions
  from (select team, count(*)::integer as mission_count from public.game_secondary_missions where room_id = p_room_id group by team) team_missions;
  if v_min_team_missions <> v_max_team_missions and exists (
    select 1 from public.game_secondary_missions m where m.room_id = p_room_id
    group by m.participant_id having count(*) <> 1
  ) then raise exception 'Todos los equipos deben tener la misma cantidad total de misiones'; end if;
  if exists (select 1 from public.game_secondary_missions where room_id = p_room_id and (target_participant_id is null or clue_type is null)) then
    raise exception 'Cada misión debe tener una pista válida';
  end if;

  for v_team in select distinct team from public.game_assignments where room_id = p_room_id and participant_type = 'real' loop
    v_lost_count := floor(random() * (ceil(v_max_team_missions / 5.0)::integer + 1));
    with selected as (
      select ctid from public.game_secondary_missions where room_id = p_room_id and team = v_team order by random() limit v_lost_count
    ) update public.game_secondary_missions set reward_withheld = true where ctid in (select ctid from selected);
  end loop;
end;
$$;

grant execute on function public.save_secondary_missions(uuid, jsonb) to authenticated;
