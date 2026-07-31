-- Ejecutar este parche si ya ejecutaste schema.sql antes de esta correccion.
create or replace function public.create_game_room(p_display_name text)
returns table(room_id uuid, room_code text)
language plpgsql security definer set search_path = public as $$
declare v_room_id uuid; v_code text;
begin
  if auth.uid() is null or char_length(trim(p_display_name)) not between 1 and 40 then
    raise exception 'Nombre de jugador no valido';
  end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));
    exit when not exists (select 1 from public.game_rooms where code = v_code);
  end loop;
  insert into public.game_rooms(code, admin_user_id) values (v_code, auth.uid()) returning id into v_room_id;
  insert into public.game_room_players(room_id, user_id, display_name)
  values (v_room_id, auth.uid(), trim(p_display_name));
  return query select v_room_id, v_code;
end;
$$;

grant execute on function public.create_game_room(text) to authenticated;
