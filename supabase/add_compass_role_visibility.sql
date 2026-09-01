-- Ejecutar despues de add_compass_mystery.sql.
-- Revela solo al jugador autenticado si es ladron o complice, sin exponer la identidad de los demas.
create or replace function public.my_compass_role(p_room_id uuid)
returns text language sql security definer set search_path = public stable as $$
  select case
    when mystery.thief_participant_id = (select auth.uid()) then 'thief'
    when (select auth.uid()) = any(mystery.accomplice_participant_ids) then 'accomplice'
    else null
  end
  from public.game_room_mysteries mystery
  where mystery.room_id = p_room_id;
$$;

grant execute on function public.my_compass_role(uuid) to authenticated;
