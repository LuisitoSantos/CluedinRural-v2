(function () {
  let deferredInstallPrompt;
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredInstallPrompt = event;
  });

  function installed() {
    return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  }

  function base64ToUint8Array(value) {
    const padding = '='.repeat((4 - value.length % 4) % 4);
    const base64 = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    return Uint8Array.from(raw, char => char.charCodeAt(0));
  }

  window.cluedinNotifications = {
    async install() {
      if (!deferredInstallPrompt) return false;
      deferredInstallPrompt.prompt();
      const result = await deferredInstallPrompt.userChoice;
      deferredInstallPrompt = null;
      return result.outcome === 'accepted';
    },
    async subscribe() {
      if (!('serviceWorker' in navigator) || !('PushManager' in window) || !window.CLUE_VAPID_PUBLIC_KEY || window.CLUE_VAPID_PUBLIC_KEY.startsWith('REEMPLAZAR')) {
        return JSON.stringify({ supported: false, installed: installed() });
      }
      if (/iPhone|iPad|iPod/i.test(navigator.userAgent) && !installed()) {
        return JSON.stringify({ supported: false, installed: false });
      }
      const registration = await navigator.serviceWorker.ready;
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') return JSON.stringify({ supported: false, installed: installed() });
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: base64ToUint8Array(window.CLUE_VAPID_PUBLIC_KEY),
      });
      const json = subscription.toJSON();
      return JSON.stringify({ supported: true, installed: installed(), endpoint: json.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth });
    },
  };

  if ('serviceWorker' in navigator) navigator.serviceWorker.register('push_service_worker.js');
}());
