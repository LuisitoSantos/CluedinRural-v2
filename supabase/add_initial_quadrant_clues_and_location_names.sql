-- Pistas iniciales condicionadas por cuadrante y nombres en ubicaciones.
-- Ejecutar después de add_team_quadrants_and_location_purchases.sql.

create or replace function public.refresh_initial_team_quadrant_clues(p_room_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_game_room_admin(p_room_id) then
    raise exception 'Solo el admin puede preparar las pistas iniciales';
  end if;

  -- Si un compañero está dentro de un cuadrante inicial del equipo, la pista
  -- inicial pasa a señalar su casilla en lugar de describir el entorno.
  update public.game_team_clues clue
  set clue = format('Hay un jugador de tu equipo en la casilla %s.', target.position_name)
  from public.game_assignments target
  where clue.room_id = p_room_id
    and target.room_id = clue.room_id
    and target.participant_id = clue.target_participant_id
    and target.team = clue.team
    and exists (
      select 1
      from public.game_team_quadrants quadrant
      where quadrant.room_id = p_room_id
        and quadrant.team = clue.team
        and quadrant.source = 'initial'
        and quadrant.quadrant = case
          when substring(target.position_name from 1 for 1) between 'A' and 'G'
            and substring(target.position_name from 2)::integer between 1 and 11 then 'A'
          when substring(target.position_name from 1 for 1) between 'H' and 'N'
            and substring(target.position_name from 2)::integer between 1 and 11 then 'B'
          when substring(target.position_name from 1 for 1) between 'O' and 'U'
            and substring(target.position_name from 2)::integer between 1 and 11 then 'C'
          when substring(target.position_name from 1 for 1) between 'A' and 'G'
            and substring(target.position_name from 2)::integer between 12 and 22 then 'D'
          when substring(target.position_name from 1 for 1) between 'H' and 'N'
            and substring(target.position_name from 2)::integer between 12 and 22 then 'E'
          when substring(target.position_name from 1 for 1) between 'O' and 'U'
            and substring(target.position_name from 2)::integer between 12 and 22 then 'F'
          when substring(target.position_name from 1 for 1) between 'A' and 'G'
            and substring(target.position_name from 2)::integer between 23 and 33 then 'G'
          when substring(target.position_name from 1 for 1) between 'H' and 'N'
            and substring(target.position_name from 2)::integer between 23 and 33 then 'H'
          when substring(target.position_name from 1 for 1) between 'O' and 'U'
            and substring(target.position_name from 2)::integer between 23 and 33 then 'I'
        end
    );
end;
$$;

create or replace function public.my_team_quadrant_locations(p_room_id uuid)
returns table(quadrant text, position_name text, character_name text)
language sql security definer set search_path = public stable as $$
  select locations.quadrant, locations.position_name, assignments.character_name
  from public.game_team_quadrant_locations locations
  join public.game_assignments assignments
    on assignments.room_id = locations.room_id
   and assignments.position_name = locations.position_name
  where locations.room_id = p_room_id
    and locations.team = (
      select own_assignment.team
      from public.game_assignments own_assignment
      where own_assignment.room_id = p_room_id
        and own_assignment.user_id = (select auth.uid())
      limit 1
    )
  order by locations.quadrant, locations.position_name;
$$;

grant execute on function public.refresh_initial_team_quadrant_clues(uuid) to authenticated;
grant execute on function public.my_team_quadrant_locations(uuid) to authenticated;
