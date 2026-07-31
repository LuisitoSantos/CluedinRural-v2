-- Ejecutar una vez en Supabase: SQL Editor.
create table if not exists public.game_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{5}$'),
  admin_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.game_room_players (
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  display_name text not null check (char_length(display_name) between 1 and 40),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id),
  unique (room_id, display_name)
);

alter table public.game_rooms enable row level security;
alter table public.game_room_players enable row level security;

create or replace function public.is_game_room_member(p_room_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.game_room_players
    where room_id = p_room_id and user_id = (select auth.uid())
  );
$$;

create policy "Members can read their rooms" on public.game_rooms for select to authenticated
using (public.is_game_room_member(id));
create policy "Members can read room players" on public.game_room_players for select to authenticated
using (public.is_game_room_member(room_id));

create or replace function public.create_game_room(p_display_name text)
returns table(room_id uuid, room_code text)
language plpgsql security definer set search_path = public as $$
declare v_room_id uuid; v_code text;
begin
  if auth.uid() is null or char_length(trim(p_display_name)) not between 1 and 40 then
    raise exception 'Nombre de jugador no valido';
  end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));
    exit when not exists (select 1 from public.game_rooms where code = v_code);
  end loop;
  insert into public.game_rooms(code, admin_user_id) values (v_code, auth.uid()) returning id into v_room_id;
  insert into public.game_room_players(room_id, user_id, display_name)
  values (v_room_id, auth.uid(), trim(p_display_name));
  return query select v_room_id, v_code;
end;
$$;

create or replace function public.join_game_room(p_code text, p_display_name text)
returns table(room_id uuid, room_code text)
language plpgsql security definer set search_path = public as $$
declare v_room_id uuid; v_code text;
begin
  if auth.uid() is null or char_length(trim(p_display_name)) not between 1 and 40 then
    raise exception 'Nombre de jugador no valido';
  end if;
  select id, code into v_room_id, v_code from public.game_rooms where code = upper(trim(p_code));
  if v_room_id is null then raise exception 'No existe ninguna sala con ese codigo'; end if;
  insert into public.game_room_players(room_id, user_id, display_name)
  values (v_room_id, auth.uid(), trim(p_display_name));
  return query select v_room_id, v_code;
exception when unique_violation then
  raise exception 'Ya estas en la sala o ese nombre ya esta en uso';
end;
$$;

grant execute on function public.create_game_room(text) to authenticated;
grant execute on function public.join_game_room(text, text) to authenticated;
grant execute on function public.is_game_room_member(uuid) to authenticated;
