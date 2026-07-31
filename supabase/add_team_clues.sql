-- Ejecutar una vez en Supabase SQL Editor.
create table if not exists public.game_team_clues (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  target_participant_id uuid not null,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  clue text not null,
  primary key (room_id, target_participant_id)
);

alter table public.game_team_clues enable row level security;

create policy "Admin or teammates can read clues" on public.game_team_clues for select to authenticated
using (
  public.is_game_room_admin(room_id)
  or exists (
    select 1 from public.game_assignments own_assignment
    where own_assignment.room_id = game_team_clues.room_id
      and own_assignment.user_id = (select auth.uid())
      and own_assignment.team = game_team_clues.team
  )
);

-- Sustituye la funcion previa para guardar las pistas al iniciar o repartir de nuevo.
create or replace function public.save_game_assignments(p_room_id uuid, p_assignments jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede iniciar la partida'; end if;
  if jsonb_typeof(p_assignments) <> 'array' or jsonb_array_length(p_assignments) = 0 then
    raise exception 'No hay jugadores para asignar';
  end if;
  delete from public.game_team_clues where room_id = p_room_id;
  delete from public.game_assignments where room_id = p_room_id;
  insert into public.game_assignments(
    room_id, participant_id, participant_type, user_id, character_name, team, role_name, position_name
  )
  select p_room_id, (item->>'participant_id')::uuid, item->>'participant_type',
    case when item->>'participant_type' = 'real' then (item->>'participant_id')::uuid else null end,
    item->>'character_name', item->>'team', item->>'role_name', item->>'position_name'
  from jsonb_array_elements(p_assignments) as item;
  insert into public.game_team_clues(room_id, target_participant_id, team, clue)
  select p_room_id, (item->>'participant_id')::uuid, item->>'team', item->>'clue'
  from jsonb_array_elements(p_assignments) as item;
end;
$$;

grant execute on function public.save_game_assignments(uuid, jsonb) to authenticated;
