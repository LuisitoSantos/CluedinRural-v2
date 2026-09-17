import 'dart:convert';
import 'dart:js_util' as js_util;

class PushSubscriptionData {
  const PushSubscriptionData({this.endpoint, this.p256dh, this.auth, required this.supported, required this.installed});

  final String? endpoint;
  final String? p256dh;
  final String? auth;
  final bool supported;
  final bool installed;
}

class PushNotifications {
  static Object get _api => js_util.getProperty<Object>(js_util.globalThis, 'cluedinNotifications');

  static Future<PushSubscriptionData> subscribe() async {
    final raw = await js_util.promiseToFuture<String>(js_util.callMethod<Object>(_api, 'subscribe', const []));
    final value = jsonDecode(raw) as Map<String, dynamic>;
    return PushSubscriptionData(
      endpoint: value['endpoint'] as String?,
      p256dh: value['p256dh'] as String?,
      auth: value['auth'] as String?,
      supported: value['supported'] as bool? ?? false,
      installed: value['installed'] as bool? ?? false,
    );
  }

  static Future<bool> install() => js_util.promiseToFuture<bool>(js_util.callMethod<Object>(_api, 'install', const []));
}
