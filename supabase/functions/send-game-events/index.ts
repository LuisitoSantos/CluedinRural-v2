import webpush from 'npm:web-push@3.6.7'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
)

webpush.setVapidDetails(
  Deno.env.get('VAPID_SUBJECT') ?? 'mailto:admin@example.com',
  Deno.env.get('VAPID_PUBLIC_KEY') ?? '',
  Deno.env.get('VAPID_PRIVATE_KEY') ?? '',
)

Deno.serve(async () => {
  const now = new Date().toISOString()
  const { data: events, error } = await supabase
    .from('game_scheduled_events')
    .select('id, room_id, title, message')
    .eq('status', 'scheduled')
    .lte('scheduled_for', now)

  if (error) return Response.json({ error: error.message }, { status: 500 })

  for (const event of events ?? []) {
    // Se marca antes de enviar para que dos invocaciones no dupliquen el evento.
    const { data: claimed } = await supabase
      .from('game_scheduled_events')
      .update({ status: 'triggered', triggered_at: now })
      .eq('id', event.id)
      .eq('status', 'scheduled')
      .select('id')
    if (!claimed?.length) continue

    const { data: members } = await supabase.from('game_room_players').select('user_id').eq('room_id', event.room_id)
    const userIds = (members ?? []).map((member) => member.user_id)
    if (!userIds.length) continue
    const { data: subscriptions } = await supabase
      .from('game_push_subscriptions')
      .select('endpoint, p256dh, auth')
      .in('user_id', userIds)

    await Promise.all((subscriptions ?? []).map(async (subscription) => {
      try {
        await webpush.sendNotification(
          { endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } },
          JSON.stringify({ title: event.title, body: event.message, url: './' }),
        )
      } catch (pushError) {
        // Las suscripciones expiradas (404/410) se eliminan para no reintentarlas.
        const statusCode = (pushError as { statusCode?: number }).statusCode
        if (statusCode === 404 || statusCode === 410) {
          await supabase.from('game_push_subscriptions').delete().eq('endpoint', subscription.endpoint)
        } else {
          console.error('No se pudo enviar una notificación', pushError)
        }
      }
    }))
  }

  const { data: notices, error: noticesError } = await supabase
    .from('game_player_notices')
    .select('id, user_id, title, message')
    .is('push_delivered_at', null)
    .limit(100)
  if (noticesError) return Response.json({ error: noticesError.message }, { status: 500 })

  for (const notice of notices ?? []) {
    // Se reclama el aviso antes de enviarlo para evitar duplicados si llega
    // a la vez la llamada del trigger y la revisión periódica del cron.
    const { data: claimed } = await supabase
      .from('game_player_notices')
      .update({ push_delivered_at: now })
      .eq('id', notice.id)
      .is('push_delivered_at', null)
      .select('id')
    if (!claimed?.length) continue

    const { data: subscriptions } = await supabase
      .from('game_push_subscriptions')
      .select('endpoint, p256dh, auth')
      .eq('user_id', notice.user_id)
    await Promise.all((subscriptions ?? []).map(async (subscription) => {
      try {
        await webpush.sendNotification(
          { endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } },
          JSON.stringify({ title: notice.title, body: notice.message, url: './' }),
        )
      } catch (pushError) {
        const statusCode = (pushError as { statusCode?: number }).statusCode
        if (statusCode === 404 || statusCode === 410) {
          await supabase.from('game_push_subscriptions').delete().eq('endpoint', subscription.endpoint)
        } else {
          console.error('No se pudo enviar una notificación', pushError)
        }
      }
    }))
  }

  return Response.json({ processedEvents: events?.length ?? 0, processedNotices: notices?.length ?? 0 })
})
