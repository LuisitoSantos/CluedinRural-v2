import 'dart:convert';
import 'dart:js_interop';

@JS('cluedinNotifications')
external _CluedinNotifications get _api;

extension type _CluedinNotifications._(JSObject _) implements JSObject {
  external JSPromise<JSString> subscribe();
  external JSPromise<JSBoolean> install();
}

class PushSubscriptionData {
  const PushSubscriptionData({this.endpoint, this.p256dh, this.auth, required this.supported, required this.installed});

  final String? endpoint;
  final String? p256dh;
  final String? auth;
  final bool supported;
  final bool installed;
}

class PushNotifications {
  static Future<PushSubscriptionData> subscribe() async {
    final raw = (await _api.subscribe().toDart).toDart;
    final value = jsonDecode(raw) as Map<String, dynamic>;
    return PushSubscriptionData(
      endpoint: value['endpoint'] as String?,
      p256dh: value['p256dh'] as String?,
      auth: value['auth'] as String?,
      supported: value['supported'] as bool? ?? false,
      installed: value['installed'] as bool? ?? false,
    );
  }

  static Future<bool> install() async => (await _api.install().toDart).toDart;
}
