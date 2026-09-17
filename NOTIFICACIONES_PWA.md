# PWA y eventos programados

La aplicación sigue desplegándose en GitHub Pages. Antes de probar los avisos:

1. Ejecuta `supabase/add_scheduled_events.sql` en el SQL Editor de Supabase.
2. Genera claves VAPID, por ejemplo con `npx web-push generate-vapid-keys`.
3. Copia la clave pública a `web/push_config.js`.
4. Configura en Supabase los secretos `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` y `VAPID_SUBJECT` (por ejemplo, `mailto:tu-correo@example.com`).
5. Despliega la función: `supabase functions deploy send-game-events --no-verify-jwt`.
6. En Supabase, guarda la URL y la publishable key en Vault y programa una invocación por minuto:

```sql
select vault.create_secret('https://PROJECT_REF.supabase.co', 'project_url');
select vault.create_secret('TU_SUPABASE_PUBLISHABLE_KEY', 'publishable_key');

select cron.schedule(
  'send-game-events-every-minute',
  '* * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-game-events',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'publishable_key')
      ),
      body := '{}'::jsonb
    );
  $$
);
```

El cron solo revisa eventos vencidos; no crea notificaciones repetidas.

En iPhone/iPad hay que abrir la web, pulsar **Instalar app** (o Compartir → Añadir a pantalla de inicio) y después **Activar avisos**. En Android basta normalmente con instalar o añadir al inicio y activar los avisos.
