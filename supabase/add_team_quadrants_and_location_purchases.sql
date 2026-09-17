-- Ejecutar después de add_player_purchases_and_reset_balances.sql.
-- Los cuadrantes pertenecen al equipo de color; las monedas siguen siendo
-- de cada familia, como en el resto de las compras.

create table if not exists public.game_team_quadrants (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  quadrant text not null check (quadrant in (
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'
  )),
  source text not null check (source in ('initial', 'secret', 'purchase')),
  primary key (room_id, team, quadrant)
);

alter table public.game_team_quadrants enable row level security;

drop policy if exists "Admins and teams can read their available quadrants" on public.game_team_quadrants;
create policy "Admins and teams can read their available quadrants"
on public.game_team_quadrants for select to authenticated
using (
  public.is_game_room_admin(room_id)
  or (
    source <> 'secret'
    and exists (
      select 1 from public.game_assignments own_assignment
      where own_assignment.room_id = game_team_quadrants.room_id
        and own_assignment.user_id = (select auth.uid())
        and own_assignment.team = game_team_quadrants.team
    )
  )
);

create table if not exists public.game_team_quadrant_location_purchases (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  quadrant text not null,
  bought_by uuid not null references auth.users(id),
  bought_at timestamptz not null default now(),
  primary key (room_id, team, quadrant)
);

create table if not exists public.game_team_quadrant_locations (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  quadrant text not null,
  position_name text not null,
  primary key (room_id, team, quadrant, position_name)
);

-- El tablero actual es una cuadrícula de 3 × 3: A–I. Se limpian posibles
-- cuadrantes de la versión anterior (A–R) antes de estrechar la restricción.
delete from public.game_team_quadrant_locations where quadrant not in ('A','B','C','D','E','F','G','H','I');
delete from public.game_team_quadrant_location_purchases where quadrant not in ('A','B','C','D','E','F','G','H','I');
delete from public.game_team_quadrants where quadrant not in ('A','B','C','D','E','F','G','H','I');
alter table public.game_team_quadrants drop constraint if exists game_team_quadrants_quadrant_check;
alter table public.game_team_quadrants add constraint game_team_quadrants_quadrant_check
  check (quadrant in ('A','B','C','D','E','F','G','H','I'));

alter table public.game_team_quadrant_locations enable row level security;

drop policy if exists "Admins and teams can read discovered locations" on public.game_team_quadrant_locations;
create policy "Admins and teams can read discovered locations"
on public.game_team_quadrant_locations for select to authenticated
using (
  public.is_game_room_admin(room_id)
  or exists (
    select 1 from public.game_assignments own_assignment
    where own_assignment.room_id = game_team_quadrant_locations.room_id
      and own_assignment.user_id = (select auth.uid())
      and own_assignment.team = game_team_quadrant_locations.team
  )
);

-- Se redefine para que un cuadrante comprado se entregue de inmediato, sin
-- repetir ninguno (incluido el cuadrante secreto que el equipo desconoce).
-- La versión anterior tenía dos parámetros y provocaría ambigüedad al llamar
-- a la función sin cuadrante.
drop function if exists public.purchase_game_item(uuid, text);
create or replace function public.purchase_game_item(
  p_room_id uuid,
  p_item text,
  p_quadrant text default null
)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_team text;
  v_family_name text;
  v_cost integer;
  v_enabled boolean;
  v_quadrant text;
  v_location_count integer;
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

  if p_item = 'quadrant' then
    select quadrant into v_quadrant
    from (
      select unnest(array['A','B','C','D','E','F','G','H','I']) as quadrant
    ) candidates
    where not exists (
      select 1 from public.game_team_quadrants owned
      where owned.room_id = p_room_id and owned.team = v_team and owned.quadrant = candidates.quadrant
    )
    order by random()
    limit 1;
    if v_quadrant is null then raise exception 'Tu equipo ya tiene todos los cuadrantes disponibles'; end if;
  elsif p_item = 'quadrant_locations' then
    v_quadrant := upper(trim(coalesce(p_quadrant, '')));
    if v_quadrant = '' then raise exception 'Elige un cuadrante para ver sus ubicaciones'; end if;
    if not exists (
      select 1 from public.game_team_quadrants owned
      where owned.room_id = p_room_id and owned.team = v_team
        and owned.quadrant = v_quadrant and owned.source <> 'secret'
    ) then raise exception 'Solo puedes comprar ubicaciones de un cuadrante que ya tenga tu equipo'; end if;
    if exists (
      select 1 from public.game_team_quadrant_location_purchases already_bought
      where already_bought.room_id = p_room_id and already_bought.team = v_team and already_bought.quadrant = v_quadrant
    ) then raise exception 'Tu equipo ya ha comprado las ubicaciones de ese cuadrante'; end if;
  end if;

  update public.game_family_balances
  set coins = coins - v_cost
  where room_id = p_room_id and team = v_team and family_name = v_family_name and coins >= v_cost;
  if not found then raise exception 'Tu equipo/familia no tiene suficientes monedas'; end if;

  insert into public.game_family_purchase_log(room_id, team, family_name, item, cost, bought_by)
  values (p_room_id, v_team, v_family_name, p_item, v_cost, (select auth.uid()));

  if p_item = 'quadrant' then
    insert into public.game_team_quadrants(room_id, team, quadrant, source)
    values (p_room_id, v_team, v_quadrant, 'purchase');
    return format('Tu equipo ha recibido el cuadrante %s.', v_quadrant);
  elsif p_item = 'quadrant_locations' then
    insert into public.game_team_quadrant_location_purchases(room_id, team, quadrant, bought_by)
    values (p_room_id, v_team, v_quadrant, (select auth.uid()));
    insert into public.game_team_quadrant_locations(room_id, team, quadrant, position_name)
    select p_room_id, v_team, v_quadrant, assignment.position_name
    from public.game_assignments assignment
    join public.game_team_quadrants owned
      on owned.room_id = p_room_id and owned.team = v_team and owned.quadrant = v_quadrant
    where assignment.room_id = p_room_id
      and (
        (v_quadrant in ('A', 'D', 'G') and substring(assignment.position_name from 1 for 1) between 'A' and 'G')
        or (v_quadrant in ('B', 'E', 'H') and substring(assignment.position_name from 1 for 1) between 'H' and 'N')
        or (v_quadrant in ('C', 'F', 'I') and substring(assignment.position_name from 1 for 1) between 'O' and 'U')
      )
      and (
        (v_quadrant in ('A', 'B', 'C') and substring(assignment.position_name from 2)::integer between 1 and 11)
        or (v_quadrant in ('D', 'E', 'F') and substring(assignment.position_name from 2)::integer between 12 and 22)
        or (v_quadrant in ('G', 'H', 'I') and substring(assignment.position_name from 2)::integer between 23 and 33)
      );
    get diagnostics v_location_count = row_count;
    if v_location_count = 0 then
      return format('No había ningún jugador en el cuadrante %s. Mala suerte.', v_quadrant);
    end if;
    return format('Se han descubierto %s ubicaciones del cuadrante %s.', v_location_count, v_quadrant);
  end if;

  return 'Compra registrada. La pista se entregará cuando se configure el saco de pistas.';
end;
$$;

-- Al iniciar o reiniciar se vuelven a sortear exactamente dos cuadrantes
-- visibles y uno secreto por cada equipo que participe en la partida.
alter table public.game_room_mysteries add column if not exists secret_word text;

create or replace function public.save_game_assignments(
  p_room_id uuid,
  p_assignments jsonb,
  p_mystery jsonb
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_thief_id uuid; v_accomplice_ids uuid[]; v_compass_holder_id uuid; v_suspect_room_names text[]; v_secret_word text; v_team text;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede iniciar la partida'; end if;
  if jsonb_typeof(p_assignments) <> 'array' or jsonb_array_length(p_assignments) < 3 then
    raise exception 'Se necesitan al menos tres jugadores para iniciar la partida';
  end if;
  v_thief_id := (p_mystery->>'thief_participant_id')::uuid;
  v_accomplice_ids := array(select jsonb_array_elements_text(p_mystery->'accomplice_participant_ids')::uuid);
  v_compass_holder_id := (p_mystery->>'compass_holder_participant_id')::uuid;
  v_suspect_room_names := array(select jsonb_array_elements_text(p_mystery->'suspect_room_names'));
  v_secret_word := nullif(trim(p_mystery->>'secret_word'), '');
  if cardinality(v_accomplice_ids) <> 2 or v_thief_id = any(v_accomplice_ids)
     or v_compass_holder_id <> v_thief_id or cardinality(v_suspect_room_names) <> 3 or v_secret_word is null then
    raise exception 'La solución del Compás Dorado no es válida';
  end if;

  delete from public.game_team_quadrant_locations where room_id = p_room_id;
  delete from public.game_team_quadrant_location_purchases where room_id = p_room_id;
  delete from public.game_team_quadrants where room_id = p_room_id;
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
  insert into public.game_room_mysteries(room_id, thief_participant_id, accomplice_participant_ids, suspect_room_names, compass_holder_participant_id, secret_word)
  values (p_room_id, v_thief_id, v_accomplice_ids, v_suspect_room_names, v_compass_holder_id, v_secret_word);
  insert into public.game_room_purchase_settings(room_id, clue_enabled, quadrant_enabled, quadrant_locations_enabled)
  values (p_room_id, false, false, false)
  on conflict (room_id) do update set clue_enabled = false, quadrant_enabled = false, quadrant_locations_enabled = false;

  for v_team in select distinct item->>'team' from jsonb_array_elements(p_assignments) as item loop
    insert into public.game_team_quadrants(room_id, team, quadrant, source)
    select p_room_id, v_team, quadrant,
      case when row_number() over (order by random()) <= 2 then 'initial' else 'secret' end
    from (
      select quadrant from unnest(array['A','B','C','D','E','F','G','H','I']) quadrant
      order by random() limit 3
    ) drawn;
  end loop;
end;
$$;

grant execute on function public.purchase_game_item(uuid, text, text) to authenticated;
grant execute on function public.save_game_assignments(uuid, jsonb, jsonb) to authenticated;
