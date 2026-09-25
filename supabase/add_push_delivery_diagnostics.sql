-- Registro de intentos de Web Push y recuento de dispositivos suscritos.
-- Ejecutar después de add_scheduled_events.sql.

create table if not exists public.game_push_delivery_log (
  id bigint generated always as identity primary key,
  event_id uuid references public.game_scheduled_events(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  delivered_at timestamptz not null default now(),
  success boolean not null,
  details text
);
create index if not exists game_push_delivery_log_event_id on public.game_push_delivery_log(event_id, delivered_at desc);
alter table public.game_push_delivery_log enable row level security;

create or replace function public.my_room_push_subscription_count(p_room_id uuid)
returns integer language sql security definer set search_path = public stable as $$
  select count(distinct subscriptions.user_id)::integer
  from public.game_push_subscriptions subscriptions
  join public.game_room_players members on members.user_id = subscriptions.user_id
  where members.room_id = p_room_id
    and public.is_game_room_admin(p_room_id);
$$;

grant execute on function public.my_room_push_subscription_count(uuid) to authenticated;
