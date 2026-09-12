-- Ejecutar despues de add_compass_mystery.sql.
-- Revela solo al jugador autenticado su rol y, si procede, la palabra común.
alter table public.game_room_mysteries add column if not exists secret_word text;

create or replace function public.my_compass_secret(p_room_id uuid)
returns table(role text, secret_word text) language sql security definer set search_path = public stable as $$
  select
    case
      when mystery.thief_participant_id = (select auth.uid()) then 'thief'
      when (select auth.uid()) = any(mystery.accomplice_participant_ids) then 'accomplice'
      else null
    end,
    case when mystery.thief_participant_id = (select auth.uid())
           or (select auth.uid()) = any(mystery.accomplice_participant_ids)
         then mystery.secret_word else null end
  from public.game_room_mysteries mystery
  where mystery.room_id = p_room_id;
$$;

grant execute on function public.my_compass_secret(uuid) to authenticated;
