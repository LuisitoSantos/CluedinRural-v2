-- Ejecutar después de add_compass_locations_and_family_coins.sql.
-- Añade compras de jugadores, habilitadas por el administrador, y garantiza
-- que cada inicio/reinicio restablezca los saldos a 100.

drop policy if exists "Only the admin can read family balances" on public.game_family_balances;
create policy "Admin or family members can read family balances"
on public.game_family_balances for select to authenticated
using (
  public.is_game_room_admin(room_id)
  or exists (
    select 1 from public.game_assignments own_assignment
    where own_assignment.room_id = game_family_balances.room_id
      and own_assignment.user_id = (select auth.uid())
      and own_assignment.team = game_family_balances.team
      and own_assignment.role_name = game_family_balances.family_name
  )
);

create table if not exists public.game_room_purchase_settings (
  room_id uuid primary key references public.game_rooms(id) on delete cascade,
  clue_enabled boolean not null default false,
  quadrant_enabled boolean not null default false,
  quadrant_locations_enabled boolean not null default false
);

alter table public.game_room_purchase_settings enable row level security;

create policy "Room members can read purchase settings"
on public.game_room_purchase_settings for select to authenticated
using (
  public.is_game_room_admin(room_id)
  or exists (
    select 1 from public.game_room_players member
    where member.room_id = game_room_purchase_settings.room_id
      and member.user_id = (select auth.uid())
  )
);

create table if not exists public.game_family_purchase_log (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  family_name text not null,
  item text not null check (item in ('clue', 'quadrant', 'quadrant_locations')),
  cost integer not null check (cost > 0),
  bought_by uuid not null references auth.users(id),
  bought_at timestamptz not null default now()
);

alter table public.game_family_purchase_log enable row level security;

create or replace function public.set_game_purchase_enabled(
  p_room_id uuid,
  p_item text,
  p_enabled boolean
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_game_room_admin(p_room_id) then
    raise exception 'Solo el admin puede activar compras';
  end if;
  insert into public.game_room_purchase_settings(room_id)
  values (p_room_id)
  on conflict (room_id) do nothing;

  case p_item
    when 'clue' then update public.game_room_purchase_settings set clue_enabled = p_enabled where room_id = p_room_id;
    when 'quadrant' then update public.game_room_purchase_settings set quadrant_enabled = p_enabled where room_id = p_room_id;
    when 'quadrant_locations' then update public.game_room_purchase_settings set quadrant_locations_enabled = p_enabled where room_id = p_room_id;
    else raise exception 'Compra no válida';
  end case;
end;
$$;

create or replace function public.purchase_game_item(p_room_id uuid, p_item text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_team text;
  v_family_name text;
  v_cost integer;
  v_enabled boolean;
begin
  select team, role_name into v_team, v_family_name
  from public.game_assignments
  where room_id = p_room_id and user_id = (select auth.uid());
  if not found then raise exception 'Debes tener una casilla asignada para comprar'; end if;

  select case p_item
    when 'clue' then 15
    when 'quadrant' then 10
    when 'quadrant_locations' then 25
    else null
  end into v_cost;
  if v_cost is null then raise exception 'Compra no válida'; end if;

  select case p_item
    when 'clue' then clue_enabled
    when 'quadrant' then quadrant_enabled
    when 'quadrant_locations' then quadrant_locations_enabled
  end into v_enabled
  from public.game_room_purchase_settings where room_id = p_room_id;
  if coalesce(v_enabled, false) is not true then
    raise exception 'Esta compra no está activada por el admin';
  end if;

  update public.game_family_balances
  set coins = coins - v_cost
  where room_id = p_room_id and team = v_team and family_name = v_family_name and coins >= v_cost;
  if not found then raise exception 'Tu equipo/familia no tiene suficientes monedas'; end if;

  insert into public.game_family_purchase_log(room_id, team, family_name, item, cost, bought_by)
  values (p_room_id, v_team, v_family_name, p_item, v_cost, (select auth.uid()));

  return case p_item
    when 'clue' then 'Compra registrada. La pista se entregará cuando se configure el saco de pistas.'
    when 'quadrant' then 'Compra de cuadrante registrada.'
    else 'Compra de ubicaciones de cuadrante registrada.'
  end;
end;
$$;

-- Reemplaza la función previa: se borran todos los saldos y compras para que
-- las familias de la nueva partida empiecen siempre con 100 monedas.
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

  delete from public.game_family_purchase_log where room_id = p_room_id;
  delete from public.game_family_balances where room_id = p_room_id;
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
  from jsonb_array_elements(p_assignments) as item;
  insert into public.game_room_mysteries(room_id, thief_participant_id, accomplice_participant_ids, suspect_room_names, compass_holder_participant_id)
  values (p_room_id, v_thief_id, v_accomplice_ids, v_suspect_room_names, v_compass_holder_id);
  insert into public.game_room_purchase_settings(room_id, clue_enabled, quadrant_enabled, quadrant_locations_enabled)
  values (p_room_id, false, false, false)
  on conflict (room_id) do update set clue_enabled = false, quadrant_enabled = false, quadrant_locations_enabled = false;
end;
$$;

grant execute on function public.set_game_purchase_enabled(uuid, text, boolean) to authenticated;
grant execute on function public.purchase_game_item(uuid, text) to authenticated;
grant execute on function public.save_game_assignments(uuid, jsonb, jsonb) to authenticated;
