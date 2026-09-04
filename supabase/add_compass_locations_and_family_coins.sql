-- Ejecutar después de add_compass_mystery.sql.
-- Añade las tres estancias del misterio y los saldos por equipo/familia.

alter table public.game_room_mysteries
  add column if not exists suspect_room_names text[] not null default '{}';

create table if not exists public.game_family_balances (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  family_name text not null,
  coins integer not null default 100 check (coins >= 0),
  primary key (room_id, team, family_name)
);

alter table public.game_family_balances enable row level security;

create policy "Only the admin can read family balances"
on public.game_family_balances for select to authenticated
using (public.is_game_room_admin(room_id));

create or replace function public.change_game_family_coins(
  p_room_id uuid,
  p_team text,
  p_family_name text,
  p_amount integer
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_game_room_admin(p_room_id) then
    raise exception 'Solo el admin puede modificar monedas';
  end if;
  if p_amount = 0 then return; end if;
  update public.game_family_balances
  set coins = coins + p_amount
  where room_id = p_room_id and team = p_team and family_name = p_family_name
    and coins + p_amount >= 0;
  if not found then
    raise exception 'No existe ese equipo/familia o no tiene suficientes monedas';
  end if;
end;
$$;

-- Sustituye la función para guardar las estancias y crear únicamente los saldos nuevos.
create or replace function public.save_game_assignments(
  p_room_id uuid,
  p_assignments jsonb,
  p_mystery jsonb
)
returns void language plpgsql security definer set search_path = public as $$
declare v_thief_id uuid; v_accomplice_ids uuid[]; v_compass_holder_id uuid; v_suspect_room_names text[];
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede iniciar la partida'; end if;
  if jsonb_typeof(p_assignments) <> 'array' or jsonb_array_length(p_assignments) < 3 then
    raise exception 'Se necesitan al menos tres jugadores para iniciar la partida';
  end if;
  v_thief_id := (p_mystery->>'thief_participant_id')::uuid;
  v_accomplice_ids := array(select jsonb_array_elements_text(p_mystery->'accomplice_participant_ids')::uuid);
  v_compass_holder_id := (p_mystery->>'compass_holder_participant_id')::uuid;
  v_suspect_room_names := array(select jsonb_array_elements_text(p_mystery->'suspect_room_names'));
  if cardinality(v_accomplice_ids) <> 2 or v_thief_id = any(v_accomplice_ids)
     or v_compass_holder_id <> v_thief_id or cardinality(v_suspect_room_names) <> 3 then
    raise exception 'La solución del Compás Dorado no es válida';
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
  insert into public.game_family_balances(room_id, team, family_name, coins)
  select distinct p_room_id, item->>'team', coalesce(nullif(item->>'role_name', ''), 'Sin familia'), 100
  from jsonb_array_elements(p_assignments) as item
  on conflict (room_id, team, family_name) do nothing;
  insert into public.game_room_mysteries(room_id, thief_participant_id, accomplice_participant_ids, suspect_room_names, compass_holder_participant_id)
  values (p_room_id, v_thief_id, v_accomplice_ids, v_suspect_room_names, v_compass_holder_id);
end;
$$;

grant execute on function public.change_game_family_coins(uuid, text, text, integer) to authenticated;
grant execute on function public.save_game_assignments(uuid, jsonb, jsonb) to authenticated;
