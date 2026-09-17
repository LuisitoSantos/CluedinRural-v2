-- Desbloqueo manual del cuadrante secreto de un equipo.
-- Ejecutar este archivo después de add_team_quadrants_and_location_purchases.sql.

alter table public.game_team_quadrants
  drop constraint if exists game_team_quadrants_source_check;
alter table public.game_team_quadrants
  add constraint game_team_quadrants_source_check
  check (source in ('initial', 'secret', 'purchase', 'unlocked'));

create or replace function public.unlock_secret_team_quadrant(
  p_room_id uuid,
  p_team text
)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_quadrant text;
begin
  if not public.is_game_room_admin(p_room_id) then
    raise exception 'Solo el admin puede habilitar cuadrantes secretos';
  end if;

  update public.game_team_quadrants
  set source = 'unlocked'
  where room_id = p_room_id
    and team = lower(trim(p_team))
    and source = 'secret'
  returning quadrant into v_quadrant;

  if v_quadrant is null then
    raise exception 'Ese equipo no tiene ningún cuadrante secreto pendiente';
  end if;

  return format('Cuadrante secreto %s habilitado para el equipo %s.', v_quadrant, initcap(lower(trim(p_team))));
end;
$$;

grant execute on function public.unlock_secret_team_quadrant(uuid, text) to authenticated;
