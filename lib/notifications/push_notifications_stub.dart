class PushSubscriptionData {
  const PushSubscriptionData({this.endpoint, this.p256dh, this.auth, required this.supported, required this.installed});

  final String? endpoint;
  final String? p256dh;
  final String? auth;
  final bool supported;
  final bool installed;
}

class PushNotifications {
  static Future<PushSubscriptionData> subscribe() async =>
      const PushSubscriptionData(supported: false, installed: false);

  static Future<bool> install() async => false;
}
