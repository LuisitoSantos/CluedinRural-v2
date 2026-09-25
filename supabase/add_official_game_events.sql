-- Eventos definitivos con hora y estancia aleatorias.
-- Ejecutar después de add_scheduled_events.sql.

alter table public.game_scheduled_events drop constraint if exists game_scheduled_events_event_kind_check;
alter table public.game_scheduled_events add constraint game_scheduled_events_event_kind_check
  check (event_kind in ('room', 'achupe', 'police_raid', 'family_reunion'));
alter table public.game_scheduled_events drop constraint if exists game_scheduled_events_status_check;
alter table public.game_scheduled_events add constraint game_scheduled_events_status_check
  check (status in ('scheduled', 'triggered', 'resolved', 'failed'));

create table if not exists public.game_scheduled_event_results (
  event_id uuid not null references public.game_scheduled_events(id) on delete cascade,
  team text not null check (team in ('red', 'blue', 'green', 'yellow')),
  coins_change integer not null,
  resolved_by uuid not null references auth.users(id),
  resolved_at timestamptz not null default now(),
  primary key (event_id, team)
);
alter table public.game_scheduled_event_results enable row level security;

create or replace function public.schedule_official_game_event(
  p_room_id uuid,
  p_event_kind text,
  p_event_day date
)
returns table(id uuid, event_kind text, title text, message text, scheduled_for timestamptz, status text)
language plpgsql security definer set search_path = public as $$
declare v_place text; v_title text; v_message text; v_local_time time; v_scheduled_for timestamptz;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede programar eventos'; end if;
  if p_event_day < (now() at time zone 'Europe/Madrid')::date then raise exception 'Elige un día actual o futuro'; end if;

  if p_event_kind = 'police_raid' then
    v_place := (array['Sala de BlackJack', 'Salon de Ruletas', 'Sala de Apuestas', 'Salon Privado', 'Sala de Fumadores',
      'Restaurante del Casino', 'Bar del Casino', 'Cocina', 'Salon Principal', 'Sala Vip', 'Pasillo'])
      [1 + floor(random() * 11)::integer];
    v_local_time := time '15:30' + floor(random() * 91)::integer * interval '1 minute';
    v_title := 'Evento: Redada policial';
    v_message := format('Redada policial. ¡Escondeos en %s! El último o últimos equipos en llegar perderán 15 monedas.', v_place);
  elsif p_event_kind = 'family_reunion' then
    v_place := (array['Porche del Sur', 'Porche de Entrada', 'Camino del Bosque', 'Bosque del Casino', 'Pasillo Exterior',
      'Terraza del Poker', 'Patio de Eventos'])[1 + floor(random() * 7)::integer];
    v_local_time := time '19:00' + floor(random() * 91)::integer * interval '1 minute';
    v_title := 'Evento: Reunión familiar';
    v_message := format('Reunión familiar. Reuníos en %s. El primer equipo en agruparse ganará 15 monedas.', v_place);
  else
    raise exception 'Evento no válido';
  end if;

  v_scheduled_for := (p_event_day + v_local_time) at time zone 'Europe/Madrid';
  if v_scheduled_for <= now() then raise exception 'La hora aleatoria ya ha pasado. Elige otro día'; end if;

  return query
  insert into public.game_scheduled_events(room_id, event_kind, title, message, scheduled_for, created_by)
  values (p_room_id, p_event_kind, v_title, v_message, v_scheduled_for, (select auth.uid()))
  returning game_scheduled_events.id, game_scheduled_events.event_kind, game_scheduled_events.title,
    game_scheduled_events.message, game_scheduled_events.scheduled_for, game_scheduled_events.status;
end;
$$;

create or replace function public.resolve_official_game_event(p_event_id uuid, p_teams text[])
returns text language plpgsql security definer set search_path = public as $$
declare v_event public.game_scheduled_events%rowtype; v_change integer;
begin
  select * into v_event from public.game_scheduled_events where id = p_event_id for update;
  if not found then raise exception 'No existe el evento'; end if;
  if not public.is_game_room_admin(v_event.room_id) then raise exception 'Solo el admin puede resolver eventos'; end if;
  if v_event.status <> 'triggered' then raise exception 'El evento debe haberse activado antes de resolverlo'; end if;
  if p_teams is null or cardinality(p_teams) = 0 then raise exception 'Elige al menos un equipo'; end if;
  if exists (select 1 from unnest(p_teams) team where team not in ('red', 'blue', 'green', 'yellow')) then raise exception 'Equipo no válido'; end if;

  if v_event.event_kind = 'police_raid' then
    v_change := -15;
  elsif v_event.event_kind = 'family_reunion' then
    if cardinality(p_teams) <> 1 then raise exception 'En una reunión familiar solo puede ganar un equipo'; end if;
    v_change := 15;
  else
    raise exception 'Este evento es solo de prueba y no tiene premio';
  end if;

  if exists (select 1 from public.game_scheduled_event_results where event_id = p_event_id) then
    raise exception 'Este evento ya se ha resuelto';
  end if;
  insert into public.game_scheduled_event_results(event_id, team, coins_change, resolved_by)
  select p_event_id, team, v_change, (select auth.uid()) from unnest(p_teams) team;
  update public.game_family_balances
  set coins = greatest(coins + v_change, 0)
  where room_id = v_event.room_id and team = any(p_teams);
  update public.game_scheduled_events set status = 'resolved' where id = p_event_id;
  return case when v_change < 0
    then format('Redada resuelta: se han restado hasta 15 monedas a %s equipo(s).', cardinality(p_teams))
    else 'Reunión resuelta: se han sumado 15 monedas al equipo ganador.' end;
end;
$$;

grant execute on function public.schedule_official_game_event(uuid, text, date) to authenticated;
grant execute on function public.resolve_official_game_event(uuid, text[]) to authenticated;
