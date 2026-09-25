-- Interruptor independiente para permitir completar misiones secundarias.
-- Ejecutar después de add_secondary_missions.sql.

alter table public.game_room_purchase_settings
  add column if not exists mission_completion_enabled boolean not null default false;

create or replace function public.set_game_mission_completion_enabled(p_room_id uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_game_room_admin(p_room_id) then
    raise exception 'Solo el admin puede activar el envío de misiones';
  end if;
  insert into public.game_room_purchase_settings(room_id, mission_completion_enabled)
  values (p_room_id, p_enabled)
  on conflict (room_id) do update set mission_completion_enabled = excluded.mission_completion_enabled;
end;
$$;

create or replace function public.guard_secondary_mission_completion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.completed_at is not null and old.completed_at is null
     and not coalesce((select mission_completion_enabled from public.game_room_purchase_settings where room_id = new.room_id), false) then
    raise exception 'El admin no ha activado el envío de misiones secundarias';
  end if;
  return new;
end;
$$;

drop trigger if exists game_secondary_missions_require_enabled on public.game_secondary_missions;
create trigger game_secondary_missions_require_enabled
before update of completed_at on public.game_secondary_missions
for each row execute function public.guard_secondary_mission_completion();

-- Al iniciar o reiniciar un sorteo se crea un misterio nuevo. Cerramos el
-- envío de misiones para que el admin tenga que abrir cada ronda de forma
-- consciente, incluso si la sala ya tenía una partida anterior.
create or replace function public.reset_mission_completion_on_new_game()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.game_room_purchase_settings
  set mission_completion_enabled = false
  where room_id = new.room_id;
  return new;
end;
$$;

drop trigger if exists game_mystery_resets_mission_completion on public.game_room_mysteries;
create trigger game_mystery_resets_mission_completion
before insert on public.game_room_mysteries
for each row execute function public.reset_mission_completion_on_new_game();

grant execute on function public.set_game_mission_completion_enabled(uuid, boolean) to authenticated;
