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

create table if not exists public.game_player_notices (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null,
  created_at timestamptz not null default now(),
  push_delivered_at timestamptz
);
create index if not exists game_player_notices_pending_push on public.game_player_notices(push_delivered_at) where push_delivered_at is null;
alter table public.game_player_notices enable row level security;

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

create or replace function public.my_game_notices(p_room_id uuid)
returns table(message text, created_at timestamptz)
language sql security definer set search_path = public stable as $$
  select n.message, n.created_at
  from public.game_player_notices n
  where n.room_id = p_room_id and n.user_id = (select auth.uid())
  order by n.created_at desc;
$$;

-- Estas funciones reemplazan las previas para dejar un aviso persistente y
-- solicitar un push inmediato cuando hay soborno o daño.
create or replace function public.cause_compass_damage(p_room_id uuid, p_target_participant_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_round integer; v_is_secret boolean; v_target_user_id uuid; v_target_name text;
begin
  select clue_enabled, sabotage_round into v_is_secret, v_round from public.game_room_purchase_settings where room_id = p_room_id;
  if not coalesce(v_is_secret, false) then raise exception 'El admin debe activar las compras de pistas'; end if;
  select exists(select 1 from public.game_room_mysteries m where m.room_id = p_room_id and
    (m.thief_participant_id = (select auth.uid()) or (select auth.uid()) = any(m.accomplice_participant_ids))) into v_is_secret;
  if not v_is_secret then raise exception 'Solo el ladrón y sus cómplices pueden causar daños'; end if;
  select user_id, character_name into v_target_user_id, v_target_name from public.game_assignments
  where room_id = p_room_id and participant_id = p_target_participant_id and participant_type = 'real';
  if not found then raise exception 'Elige un jugador real de esta partida'; end if;
  insert into public.game_compass_sabotages(room_id, sabotage_round, attacker_user_id, target_participant_id)
  values (p_room_id, v_round, (select auth.uid()), p_target_participant_id);
  insert into public.game_player_notices(room_id, user_id, title, message)
  values (p_room_id, v_target_user_id, 'Has sufrido daños', 'Han causado daños a ' || v_target_name || '. Perderás una pista al completar tu próxima misión secundaria.');
  return 'Daños causados. Ese jugador perderá la pista de su próxima misión.';
exception when unique_violation then raise exception 'Ya has usado tus daños en esta activación';
end;
$$;

create or replace function public.pay_compass_bribes(p_room_id uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.game_room_mysteries m where m.room_id = p_room_id and m.thief_participant_id = (select auth.uid())) then
    raise exception 'Solo el ladrón puede pagar sobornos';
  end if;
  insert into public.game_compass_bribes(room_id, paid_by) values (p_room_id, (select auth.uid()));
  update public.game_family_balances set coins = greatest(coins - 30, 0) where room_id = p_room_id;
  insert into public.game_player_notices(room_id, user_id, title, message)
  select p_room_id, a.user_id, 'Pago de sobornos', 'Se han restado hasta 30 monedas a todos los equipos.'
  from public.game_assignments a where a.room_id = p_room_id and a.participant_type = 'real';
  return 'Sobornos pagados: se han restado hasta 30 monedas a cada equipo.';
exception when unique_violation then raise exception 'Los sobornos ya se han pagado en esta partida';
end;
$$;

create or replace function public.dispatch_game_notice_push()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-game-events',
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey',
      (select decrypted_secret from vault.decrypted_secrets where name = 'publishable_key')),
    body := '{}'::jsonb
  );
  return new;
end;
$$;
drop trigger if exists game_player_notices_send_push on public.game_player_notices;
create trigger game_player_notices_send_push after insert on public.game_player_notices
for each statement execute function public.dispatch_game_notice_push();

grant execute on function public.save_game_push_subscription(text, text, text) to authenticated;
grant execute on function public.schedule_random_game_event(uuid, timestamptz) to authenticated;
grant execute on function public.my_room_scheduled_events(uuid) to authenticated;
grant execute on function public.my_game_notices(uuid) to authenticated;
