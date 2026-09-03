-- Ejecutar después de add_team_quadrants_and_location_purchases.sql.

create table if not exists public.game_secondary_missions (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  participant_id uuid not null,
  user_id uuid references auth.users(id),
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  mission_number integer not null check (mission_number between 1 and 5),
  mission_id text not null,
  mission_level integer not null,
  mission_action text not null,
  clue text not null,
  reward_withheld boolean not null default false,
  completed_at timestamptz,
  clue_revealed_at timestamptz,
  clue_purchased_at timestamptz,
  primary key (room_id, participant_id, mission_number)
);

alter table public.game_secondary_missions enable row level security;

create table if not exists public.game_team_secondary_clues (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  participant_id uuid not null,
  mission_number integer not null,
  clue text not null,
  primary key (room_id, participant_id, mission_number)
);

alter table public.game_team_secondary_clues enable row level security;
create policy "Teams can read secondary clues" on public.game_team_secondary_clues for select to authenticated
using (
  public.is_game_room_admin(room_id) or exists (
    select 1 from public.game_assignments own_assignment
    where own_assignment.room_id = game_team_secondary_clues.room_id
      and own_assignment.user_id = (select auth.uid())
      and own_assignment.team = game_team_secondary_clues.team
  )
);

create or replace function public.save_secondary_missions(p_room_id uuid, p_missions jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_team text; v_team_size integer; v_lost_count integer;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede iniciar la partida'; end if;
  if jsonb_typeof(p_missions) <> 'array' then raise exception 'Las misiones no son válidas'; end if;
  if exists (
    select 1 from public.game_assignments a
    where a.room_id = p_room_id and a.participant_type = 'real' and not exists (
      select 1 from jsonb_array_elements(p_missions) m
      where (m->>'participant_id')::uuid = a.participant_id
    )
  ) then raise exception 'Faltan misiones para algún jugador'; end if;

  delete from public.game_team_secondary_clues where room_id = p_room_id;
  delete from public.game_secondary_missions where room_id = p_room_id;
  insert into public.game_secondary_missions(room_id, participant_id, user_id, team, mission_number, mission_id, mission_level, mission_action, clue)
  select p_room_id, a.participant_id, a.user_id, a.team,
    (m->>'mission_number')::integer, m->>'mission_id', (m->>'mission_level')::integer,
    m->>'mission_action', m->>'clue'
  from jsonb_array_elements(p_missions) m
  join public.game_assignments a on a.room_id = p_room_id and a.participant_id = (m->>'participant_id')::uuid;

  if exists (
    select 1 from public.game_assignments a where a.room_id = p_room_id
    group by a.participant_id having count(*) <> 1
  ) or exists (
    select 1 from public.game_secondary_missions m where m.room_id = p_room_id
    group by m.participant_id having count(*) <> 5
  ) then raise exception 'Cada jugador debe recibir exactamente cinco misiones'; end if;

  for v_team in select distinct team from public.game_assignments where room_id = p_room_id and participant_type = 'real' loop
    select count(*) into v_team_size from public.game_assignments
    where room_id = p_room_id and team = v_team and participant_type = 'real';
    v_lost_count := floor(random() * (v_team_size + 1));
    with selected as (
      select ctid from public.game_secondary_missions
      where room_id = p_room_id and team = v_team
      order by random() limit v_lost_count
    ) update public.game_secondary_missions set reward_withheld = true
      where ctid in (select ctid from selected);
  end loop;
end;
$$;

create or replace function public.my_current_secondary_mission(p_room_id uuid)
returns table(mission_id text, mission_level integer, mission_action text, mission_number integer)
language sql security definer set search_path = public stable as $$
  select m.mission_id, m.mission_level, m.mission_action, m.mission_number
  from public.game_secondary_missions m
  where m.room_id = p_room_id and m.user_id = (select auth.uid()) and m.completed_at is null
  order by m.mission_number limit 1;
$$;

create or replace function public.complete_secondary_mission(p_room_id uuid, p_mission_id text)
returns text language plpgsql security definer set search_path = public as $$
declare v_mission public.game_secondary_missions%rowtype;
begin
  select * into v_mission from public.game_secondary_missions
  where room_id = p_room_id and user_id = (select auth.uid()) and completed_at is null
  order by mission_number limit 1;
  if not found then raise exception 'No tienes más misiones secundarias pendientes'; end if;
  if v_mission.mission_id <> trim(p_mission_id) then raise exception 'Ese ID no corresponde a tu misión actual'; end if;
  update public.game_secondary_missions set completed_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  if v_mission.reward_withheld then
    return 'Misión completada. Esta vez la pista ha pasado al saco de pistas del equipo.';
  end if;
  insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
  values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number, v_mission.clue);
  update public.game_secondary_missions set clue_revealed_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  return 'Misión completada. Tu equipo ha recibido una pista.';
end;
$$;

create or replace function public.purchase_team_lost_clue(p_room_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_team text; v_family text; v_mission public.game_secondary_missions%rowtype;
begin
  select team, role_name into v_team, v_family from public.game_assignments
  where room_id = p_room_id and user_id = (select auth.uid());
  if not found then raise exception 'Debes tener una casilla asignada para comprar'; end if;
  if not coalesce((select clue_enabled from public.game_room_purchase_settings where room_id = p_room_id), false) then
    raise exception 'Esta compra no está activada por el admin';
  end if;
  update public.game_family_balances set coins = coins - 15
  where room_id = p_room_id and team = v_team and family_name = v_family and coins >= 15;
  if not found then raise exception 'Tu equipo no tiene suficientes monedas'; end if;
  select * into v_mission from public.game_secondary_missions
  where room_id = p_room_id and team = v_team and reward_withheld
    and completed_at is not null and clue_purchased_at is null
  order by random() limit 1;
  if not found then return 'No quedaban pistas perdidas en el saco de tu equipo. Se han gastado las monedas.'; end if;
  update public.game_secondary_missions set clue_purchased_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
  values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number, v_mission.clue)
  on conflict do nothing;
  return 'Tu equipo ha recuperado una pista del saco.';
end;
$$;

grant execute on function public.save_secondary_missions(uuid, jsonb) to authenticated;
grant execute on function public.my_current_secondary_mission(uuid) to authenticated;
grant execute on function public.complete_secondary_mission(uuid, text) to authenticated;
grant execute on function public.purchase_team_lost_clue(uuid) to authenticated;
