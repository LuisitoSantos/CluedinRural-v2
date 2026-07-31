-- Ejecutar si ya aplicaste add_game_assignments_and_fake_players.sql.
create or replace function public.add_game_fake_players(p_room_id uuid, p_count integer)
returns void language plpgsql security definer set search_path = public as $$
declare starting_number integer; total_players integer;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede añadir jugadores ficticios'; end if;
  if p_count not between 1 and 50 then raise exception 'La cantidad debe estar entre 1 y 50'; end if;
  select count(*) into starting_number from public.game_room_fake_players where room_id = p_room_id;
  select count(*) + starting_number into total_players from public.game_room_players where room_id = p_room_id;
  if total_players + p_count > 33 then raise exception 'El limite de la partida es de 33 jugadores'; end if;
  insert into public.game_room_fake_players(room_id, display_name)
  select p_room_id, 'Jugador ficticio ' || (starting_number + series_number)
  from generate_series(1, p_count) as series_number;
end;
$$;

grant execute on function public.add_game_fake_players(uuid, integer) to authenticated;
