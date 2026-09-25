self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(self.registration.showNotification(data.title || 'Cluedin Rural', {
    body: data.body || 'Hay un nuevo evento de partida.',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    // Cada evento debe generar un aviso visible y audible independiente. iOS
    // puede ignorar parte de estas preferencias según los ajustes del sistema.
    tag: `cluedin-${Date.now()}-${Math.random()}`,
    renotify: true,
    silent: false,
    requireInteraction: true,
    timestamp: Date.now(),
    data: { url: data.url || './' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data.url));
});
