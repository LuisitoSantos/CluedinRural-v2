-- Eventos de partida y suscripciones Web Push. Ejecutar después de los demás scripts.

create table if not exists public.game_push_subscriptions (
  endpoint text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.game_push_subscriptions enable row level security;

create table if not exists public.game_scheduled_events (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  event_kind text not null check (event_kind in ('room', 'achupe')),
  title text not null,
  message text not null,
  scheduled_for timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled', 'triggered', 'failed')),
  triggered_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists game_scheduled_events_due on public.game_scheduled_events(status, scheduled_for);
alter table public.game_scheduled_events enable row level security;

create or replace function public.save_game_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if nullif(trim(p_endpoint), '') is null or nullif(trim(p_p256dh), '') is null or nullif(trim(p_auth), '') is null then
    raise exception 'La suscripción de notificaciones no es válida';
  end if;
  insert into public.game_push_subscriptions(endpoint, user_id, p256dh, auth)
  values (p_endpoint, (select auth.uid()), p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth, updated_at = now();
end;
$$;

create or replace function public.schedule_random_game_event(p_room_id uuid, p_scheduled_for timestamptz)
returns table(id uuid, event_kind text, title text, message text, scheduled_for timestamptz, status text)
language plpgsql security definer set search_path = public as $$
declare v_kind text; v_room text; v_title text; v_message text;
begin
  if not public.is_game_room_admin(p_room_id) then raise exception 'Solo el admin puede programar eventos'; end if;
  if p_scheduled_for <= now() then raise exception 'La hora del evento debe ser futura'; end if;
  v_kind := case when random() < 0.5 then 'room' else 'achupe' end;
  if v_kind = 'room' then
    v_room := (array['Sala de BlackJack', 'Salon de Ruletas', 'Sala de Apuestas', 'Salon Privado', 'Sala de Fumadores', 'Restaurante del Casino', 'Bar del Casino', 'Cocina', 'Salon Principal', 'Sala Vip'])[1 + floor(random() * 10)::integer];
    v_title := 'Evento: reunión urgente';
    v_message := format('Acudid a %s.', v_room);
  else
    v_title := 'Evento: Achupé';
    v_message := '¡Achupé! Todos los jugadores deben sentarse cuanto antes.';
  end if;
  return query
  insert into public.game_scheduled_events(room_id, event_kind, title, message, scheduled_for, created_by)
  values (p_room_id, v_kind, v_title, v_message, p_scheduled_for, (select auth.uid()))
  returning game_scheduled_events.id, game_scheduled_events.event_kind, game_scheduled_events.title,
    game_scheduled_events.message, game_scheduled_events.scheduled_for, game_scheduled_events.status;
end;
$$;

create or replace function public.my_room_scheduled_events(p_room_id uuid)
returns table(id uuid, event_kind text, title text, message text, scheduled_for timestamptz, status text)
language sql security definer set search_path = public stable as $$
  select e.id, e.event_kind, e.title, e.message, e.scheduled_for, e.status
  from public.game_scheduled_events e
  where e.room_id = p_room_id and (
    public.is_game_room_admin(p_room_id) or exists (
      select 1 from public.game_room_players p where p.room_id = p_room_id and p.user_id = (select auth.uid())
    )
  )
  order by e.scheduled_for desc;
$$;

grant execute on function public.save_game_push_subscription(text, text, text) to authenticated;
grant execute on function public.schedule_random_game_event(uuid, timestamptz) to authenticated;
grant execute on function public.my_room_scheduled_events(uuid) to authenticated;
