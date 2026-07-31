-- Ejecutar una vez en Supabase SQL Editor.
create table if not exists public.game_room_fake_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.game_assignments (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  participant_id uuid not null,
  participant_type text not null check (participant_type in ('real', 'fake')),
  user_id uuid references auth.users(id),
  character_name text not null,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  role_name text not null,
  position_name text not null,
  assigned_at timestamptz not null default now(),
  unique (room_id, participant_type, participant_id)
);

alter table public.game_room_fake_players enable row level security;
alter table public.game_assignments enable row level security;

create or replace function public.is_game_room_admin(p_room_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.game_rooms
    where id = p_room_id and admin_user_id = (select auth.uid())
  );
$$;

create policy "Members can read fake players" on public.game_room_fake_players for select to authenticated
using (public.is_game_room_member(room_id));
create policy "Admin or owner can read assignments" on public.game_assignments for select to authenticated
using (public.is_game_room_admin(room_id) or user_id = (select auth.uid()));

create or replace function public.add_game_fake_players(p_room_id uuid, p_count integer)
returns void language plpgsql security definer set search_path = public as $$
declare starting_number integer; total_players integer;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede añadir jugadores ficticios'; end if;
  if p_count not between 1 and 50 then raise exception 'La cantidad debe estar entre 1 y 50'; end if;
  select count(*) into starting_number from public.game_room_fake_players where room_id = p_room_id;
  select count(*) + starting_number into total_players from public.game_room_players where room_id = p_room_id;
  if total_players + p_count > 33 then raise exception 'El limite de la partida es de 33 jugadores'; end if;
  insert into public.game_room_fake_players(room_id, display_name)
  select p_room_id, 'Jugador ficticio ' || (starting_number + series_number)
  from generate_series(1, p_count) as series_number;
end;
$$;

create or replace function public.save_game_assignments(p_room_id uuid, p_assignments jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede iniciar la partida'; end if;
  if jsonb_typeof(p_assignments) <> 'array' or jsonb_array_length(p_assignments) = 0 then
    raise exception 'No hay jugadores para asignar';
  end if;
  delete from public.game_assignments where room_id = p_room_id;
  insert into public.game_assignments(
    room_id, participant_id, participant_type, user_id, character_name, team, role_name, position_name
  )
  select
    p_room_id,
    (item->>'participant_id')::uuid,
    item->>'participant_type',
    case when item->>'participant_type' = 'real' then (item->>'participant_id')::uuid else null end,
    item->>'character_name',
    item->>'team',
    item->>'role_name',
    item->>'position_name'
  from jsonb_array_elements(p_assignments) as item;
end;
$$;

grant execute on function public.is_game_room_admin(uuid) to authenticated;
grant execute on function public.add_game_fake_players(uuid, integer) to authenticated;
grant execute on function public.save_game_assignments(uuid, jsonb) to authenticated;
