-- Ejecutar una vez en Supabase SQL Editor.
-- Las funciones pgcrypto se califican con su esquema para evitar el error previo.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.game_player_accounts (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (char_length(display_name) between 1 and 40),
  pin_hash text not null,
  auth_user_id uuid not null unique references auth.users(id),
  created_at timestamptz not null default now()
);

create unique index if not exists game_player_accounts_display_name_lower_idx
on public.game_player_accounts (lower(display_name));

alter table public.game_player_accounts enable row level security;

create policy "Players can read their own account"
on public.game_player_accounts for select to authenticated
using (auth_user_id = (select auth.uid()));

-- Crea una identidad o recupera la existente en otro movil/reinstalacion.
create or replace function public.authenticate_game_player(p_display_name text, p_pin text)
returns table(auth_user_id uuid, display_name text)
language plpgsql security definer set search_path = public, extensions as $$
declare account public.game_player_accounts%rowtype;
begin
  if auth.uid() is null
     or char_length(trim(p_display_name)) not between 1 and 40
     or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'Nombre o PIN no valido';
  end if;

  select * into account
  from public.game_player_accounts as player_account
  where lower(player_account.display_name) = lower(trim(p_display_name));

  if not found then
    insert into public.game_player_accounts(display_name, pin_hash, auth_user_id)
    values (
      trim(p_display_name),
      extensions.crypt(p_pin, extensions.gen_salt('bf')),
      auth.uid()
    )
    returning * into account;
  elsif extensions.crypt(p_pin, account.pin_hash) <> account.pin_hash then
    raise exception 'El PIN no es correcto';
  elsif account.auth_user_id <> auth.uid() then
    -- El PIN prueba la identidad: se transfiere al nuevo usuario anonimo.
    update public.game_room_players
    set user_id = auth.uid()
    where user_id = account.auth_user_id;
    update public.game_rooms
    set admin_user_id = auth.uid()
    where admin_user_id = account.auth_user_id;
    update public.game_player_accounts
    set auth_user_id = auth.uid()
    where id = account.id
    returning * into account;
  end if;

  return query select account.auth_user_id, account.display_name;
end;
$$;

grant execute on function public.authenticate_game_player(text, text) to authenticated;
