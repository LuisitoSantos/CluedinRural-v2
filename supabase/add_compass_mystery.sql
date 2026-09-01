-- Ejecutar despues de add_game_assignments_and_fake_players.sql y add_team_clues.sql.
-- Guarda la solucion secreta de cada partida. Solo el administrador puede leerla.
create table if not exists public.game_room_mysteries (
  room_id uuid primary key references public.game_rooms(id) on delete cascade,
  thief_participant_id uuid not null,
  accomplice_participant_ids uuid[] not null,
  compass_holder_participant_id uuid not null,
  created_at timestamptz not null default now(),
  check (cardinality(accomplice_participant_ids) = 2),
  check (thief_participant_id <> all(accomplice_participant_ids)),
  check (compass_holder_participant_id = thief_participant_id)
);

alter table public.game_room_mysteries enable row level security;

create policy "Only the admin can read the mystery"
on public.game_room_mysteries for select to authenticated
using (public.is_game_room_admin(room_id));

create or replace function public.save_game_assignments(
  p_room_id uuid,
  p_assignments jsonb,
  p_mystery jsonb
)
returns void language plpgsql security definer set search_path = public as $$
declare v_thief_id uuid; v_accomplice_ids uuid[]; v_compass_holder_id uuid;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede iniciar la partida'; end if;
  if jsonb_typeof(p_assignments) <> 'array' or jsonb_array_length(p_assignments) < 3 then
    raise exception 'Se necesitan al menos tres jugadores para iniciar la partida';
  end if;
  v_thief_id := (p_mystery->>'thief_participant_id')::uuid;
  v_accomplice_ids := array(select jsonb_array_elements_text(p_mystery->'accomplice_participant_ids')::uuid);
  v_compass_holder_id := (p_mystery->>'compass_holder_participant_id')::uuid;
  if cardinality(v_accomplice_ids) <> 2
     or v_thief_id = any(v_accomplice_ids)
     or v_compass_holder_id <> v_thief_id then
    raise exception 'La solucion del Compas Dorado no es valida';
  end if;

  delete from public.game_team_clues where room_id = p_room_id;
  delete from public.game_assignments where room_id = p_room_id;
  delete from public.game_room_mysteries where room_id = p_room_id;
  insert into public.game_assignments(room_id, participant_id, participant_type, user_id, character_name, team, role_name, position_name)
  select p_room_id, (item->>'participant_id')::uuid, item->>'participant_type',
    case when item->>'participant_type' = 'real' then (item->>'participant_id')::uuid else null end,
    item->>'character_name', item->>'team', item->>'role_name', item->>'position_name'
  from jsonb_array_elements(p_assignments) as item;
  insert into public.game_team_clues(room_id, target_participant_id, team, clue)
  select p_room_id, (item->>'participant_id')::uuid, item->>'team', item->>'clue'
  from jsonb_array_elements(p_assignments) as item;
  insert into public.game_room_mysteries(room_id, thief_participant_id, accomplice_participant_ids, compass_holder_participant_id)
  values (p_room_id, v_thief_id, v_accomplice_ids, v_compass_holder_id);
end;
$$;

grant execute on function public.save_game_assignments(uuid, jsonb, jsonb) to authenticated;
