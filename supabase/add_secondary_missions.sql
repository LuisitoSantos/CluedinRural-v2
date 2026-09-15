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
  target_participant_id uuid,
  clue_type text check (clue_type in ('room', 'column', 'row', 'location')),
  reward_withheld boolean not null default false,
  completed_at timestamptz,
  clue_revealed_at timestamptz,
  clue_purchased_at timestamptz,
  primary key (room_id, participant_id, mission_number)
);

-- Compatibilidad con instalaciones que ya crearon la tabla antes de que las
-- pistas guardasen explícitamente su personaje y su tipo.
alter table public.game_secondary_missions
  add column if not exists target_participant_id uuid,
  add column if not exists clue_type text;
create unique index if not exists game_secondary_missions_unique_target
  on public.game_secondary_missions(room_id, target_participant_id)
  where target_participant_id is not null;

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
drop policy if exists "Teams can read secondary clues" on public.game_team_secondary_clues;
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
declare
  v_team text;
  v_team_size integer;
  v_lost_count integer;
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

  -- Las pistas se reciben exclusivamente al terminar una misión secundaria.
  -- Las pistas iniciales de ubicación de los compañeros se conservan.
  delete from public.game_team_secondary_clues where room_id = p_room_id;
  delete from public.game_compass_sabotages where room_id = p_room_id;
  delete from public.game_compass_bribes where room_id = p_room_id;
  update public.game_room_purchase_settings set sabotage_round = 0 where room_id = p_room_id;
  delete from public.game_secondary_missions where room_id = p_room_id;
  insert into public.game_secondary_missions(room_id, participant_id, user_id, team, mission_number, mission_id, mission_level, mission_action, clue, target_participant_id, clue_type)
  select p_room_id, a.participant_id, a.user_id, a.team,
    (m->>'mission_number')::integer, m->>'mission_id', (m->>'mission_level')::integer,
    m->>'mission_action', m->>'clue', (m->>'target_participant_id')::uuid, m->>'clue_type'
  from jsonb_array_elements(p_missions) m
  join public.game_assignments a on a.room_id = p_room_id and a.participant_id = (m->>'participant_id')::uuid
  join public.game_assignments target on target.room_id = p_room_id and target.participant_id = (m->>'target_participant_id')::uuid
  where target.team <> a.team;

  if exists (
    select 1 from public.game_assignments a where a.room_id = p_room_id
    group by a.participant_id having count(*) <> 1
  ) or exists (
    select 1 from public.game_secondary_missions m where m.room_id = p_room_id
    group by m.participant_id having count(*) <> 5
  ) then raise exception 'Cada jugador debe recibir exactamente cinco misiones'; end if;
  if exists (
    select 1 from public.game_secondary_missions
    where room_id = p_room_id and (target_participant_id is null or clue_type is null)
  ) then raise exception 'Cada misión debe tener una pista válida'; end if;

  -- La pérdida aleatoria original se conserva y puede acumularse con un daño.
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
declare
  v_mission public.game_secondary_missions%rowtype;
  v_sabotage_id bigint;
begin
  select * into v_mission from public.game_secondary_missions
  where room_id = p_room_id and user_id = (select auth.uid()) and completed_at is null
  order by mission_number limit 1;
  if not found then raise exception 'No tienes más misiones secundarias pendientes'; end if;
  if v_mission.mission_id <> trim(p_mission_id) then raise exception 'Ese ID no corresponde a tu misión actual'; end if;
  update public.game_secondary_missions set completed_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  select id into v_sabotage_id from public.game_compass_sabotages
  where room_id = p_room_id and target_participant_id = v_mission.participant_id and consumed_at is null
  order by caused_at limit 1 for update skip locked;
  if found then
    update public.game_compass_sabotages set consumed_at = now() where id = v_sabotage_id;
    update public.game_secondary_missions set reward_withheld = true
    where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
    insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
    values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number,
      'Pista perdida por daños. Puede recuperarse del saco del equipo por 30 monedas.');
    return 'Misión completada. Los daños han retenido la pista: tu equipo puede recuperarla del saco por 30 monedas.';
  end if;
  if v_mission.reward_withheld then
    insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
    values (v_mission.room_id, v_mission.team, v_mission.participant_id, v_mission.mission_number,
      'Pista perdida. Ha pasado al saco de pistas del equipo y puede recuperarse por 30 monedas.');
    return 'Misión completada. Esta vez la pista ha pasado al saco de pistas del equipo.';
  end if;
  insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
  values (
    v_mission.room_id,
    v_mission.team,
    v_mission.participant_id,
    v_mission.mission_number,
    format('Pista recibida por misión %s: %s', v_mission.mission_number, v_mission.clue)
  );
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
  update public.game_family_balances set coins = coins - 30
  where room_id = p_room_id and team = v_team and family_name = v_family and coins >= 30;
  if not found then raise exception 'Tu equipo no tiene suficientes monedas'; end if;
  select * into v_mission from public.game_secondary_missions
  where room_id = p_room_id and team = v_team and reward_withheld
    and completed_at is not null and clue_purchased_at is null
  order by random() limit 1;
  if not found then return 'No quedaban pistas perdidas en el saco de tu equipo. Se han gastado las monedas.'; end if;
  update public.game_secondary_missions set clue_purchased_at = now()
  where room_id = v_mission.room_id and participant_id = v_mission.participant_id and mission_number = v_mission.mission_number;
  insert into public.game_team_secondary_clues(room_id, team, participant_id, mission_number, clue)
  values (
    v_mission.room_id,
    v_mission.team,
    v_mission.participant_id,
    v_mission.mission_number,
    format('Pista recuperada de misión %s: %s', v_mission.mission_number, v_mission.clue)
  )
  on conflict (room_id, participant_id, mission_number) do update set clue = excluded.clue;
  return 'Tu equipo ha recuperado una pista del saco por 30 monedas.';
end;
$$;

-- Cada activación de la compra de pistas abre una ronda: ladrón y cómplices
-- tienen un sabotaje cada uno. Los daños se consumen al completar misiones.
alter table public.game_room_purchase_settings add column if not exists sabotage_round integer not null default 0;

create table if not exists public.game_compass_sabotages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  sabotage_round integer not null,
  attacker_user_id uuid not null references auth.users(id),
  target_participant_id uuid not null,
  caused_at timestamptz not null default now(),
  consumed_at timestamptz,
  unique(room_id, sabotage_round, attacker_user_id)
);
alter table public.game_compass_sabotages enable row level security;

create table if not exists public.game_compass_bribes (
  room_id uuid primary key references public.game_rooms(id) on delete cascade,
  paid_by uuid not null references auth.users(id),
  paid_at timestamptz not null default now()
);
alter table public.game_compass_bribes enable row level security;

create or replace function public.set_game_purchase_enabled(p_room_id uuid, p_item text, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede activar compras'; end if;
  insert into public.game_room_purchase_settings(room_id) values (p_room_id) on conflict (room_id) do nothing;
  if p_item = 'clue' then
    update public.game_room_purchase_settings
    set sabotage_round = sabotage_round + case when p_enabled and not clue_enabled then 1 else 0 end,
        clue_enabled = p_enabled
    where room_id = p_room_id;
  elsif p_item = 'quadrant' then
    update public.game_room_purchase_settings set quadrant_enabled = p_enabled where room_id = p_room_id;
  elsif p_item = 'quadrant_locations' then
    update public.game_room_purchase_settings set quadrant_locations_enabled = p_enabled where room_id = p_room_id;
  else raise exception 'Compra no válida'; end if;
end;
$$;

create or replace function public.cause_compass_damage(p_room_id uuid, p_target_participant_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_round integer; v_is_secret boolean;
begin
  select clue_enabled, sabotage_round into v_is_secret, v_round
  from public.game_room_purchase_settings where room_id = p_room_id;
  if not coalesce(v_is_secret, false) then raise exception 'El admin debe activar las compras de pistas'; end if;
  select exists(select 1 from public.game_room_mysteries m where m.room_id = p_room_id and
    (m.thief_participant_id = (select auth.uid()) or (select auth.uid()) = any(m.accomplice_participant_ids))) into v_is_secret;
  if not v_is_secret then raise exception 'Solo el ladrón y sus cómplices pueden causar daños'; end if;
  if not exists(select 1 from public.game_assignments where room_id = p_room_id and participant_id = p_target_participant_id and participant_type = 'real') then
    raise exception 'Elige un jugador real de esta partida'; end if;
  insert into public.game_compass_sabotages(room_id, sabotage_round, attacker_user_id, target_participant_id)
  values (p_room_id, v_round, (select auth.uid()), p_target_participant_id);
  return 'Daños causados. Ese jugador perderá la pista de su próxima misión.';
exception when unique_violation then raise exception 'Ya has usado tus daños en esta activación';
end;
$$;

create or replace function public.my_sabotage_targets(p_room_id uuid)
returns table(participant_id uuid, character_name text, pending_damage_count integer)
language sql security definer set search_path = public stable as $$
  select a.participant_id, a.character_name,
    count(s.id) filter (where s.consumed_at is null)::integer
  from public.game_assignments a
  left join public.game_compass_sabotages s on s.room_id = a.room_id and s.target_participant_id = a.participant_id
  where a.room_id = p_room_id and a.participant_type = 'real'
    and exists(select 1 from public.game_room_mysteries m where m.room_id = p_room_id and
      (m.thief_participant_id = (select auth.uid()) or (select auth.uid()) = any(m.accomplice_participant_ids)))
  group by a.participant_id, a.character_name order by a.character_name;
$$;

create or replace function public.pay_compass_bribes(p_room_id uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.game_room_mysteries m
    where m.room_id = p_room_id and m.thief_participant_id = (select auth.uid())
  ) then raise exception 'Solo el ladrón puede pagar sobornos'; end if;
  insert into public.game_compass_bribes(room_id, paid_by) values (p_room_id, (select auth.uid()));
  update public.game_family_balances
  set coins = greatest(coins - 30, 0)
  where room_id = p_room_id;
  return 'Sobornos pagados: se han restado hasta 30 monedas a cada equipo.';
exception when unique_violation then raise exception 'Los sobornos ya se han pagado en esta partida';
end;
$$;

drop function if exists public.my_compass_secret(uuid);
create function public.my_compass_secret(p_room_id uuid)
returns table(role text, secret_word text, can_cause_damage boolean, pending_damage_count integer, can_pay_bribes boolean)
language sql security definer set search_path = public stable as $$
  select role, secret_word,
    role is not null and settings.clue_enabled and not exists (
      select 1 from public.game_compass_sabotages s
      where s.room_id = p_room_id and s.sabotage_round = settings.sabotage_round and s.attacker_user_id = (select auth.uid())
    ),
    (select count(*)::integer from public.game_compass_sabotages s
      join public.game_assignments a on a.room_id = s.room_id and a.participant_id = s.target_participant_id
      where s.room_id = p_room_id and a.user_id = (select auth.uid()) and s.consumed_at is null),
    role = 'thief' and not exists (select 1 from public.game_compass_bribes b where b.room_id = p_room_id)
  from (
    select case when m.thief_participant_id = (select auth.uid()) then 'thief'
      when (select auth.uid()) = any(m.accomplice_participant_ids) then 'accomplice' else null end as role,
      case when m.thief_participant_id = (select auth.uid()) or (select auth.uid()) = any(m.accomplice_participant_ids) then m.secret_word else null end as secret_word
    from public.game_room_mysteries m where m.room_id = p_room_id
  ) mystery
  join public.game_room_purchase_settings settings on settings.room_id = p_room_id;
$$;

grant execute on function public.save_secondary_missions(uuid, jsonb) to authenticated;
grant execute on function public.my_current_secondary_mission(uuid) to authenticated;
grant execute on function public.complete_secondary_mission(uuid, text) to authenticated;
grant execute on function public.purchase_team_lost_clue(uuid) to authenticated;
grant execute on function public.cause_compass_damage(uuid, uuid) to authenticated;
grant execute on function public.my_sabotage_targets(uuid) to authenticated;
grant execute on function public.my_compass_secret(uuid) to authenticated;
grant execute on function public.pay_compass_bribes(uuid) to authenticated;
