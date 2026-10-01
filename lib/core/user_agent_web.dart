import 'package:web/web.dart' as web;

/// La signature du navigateur, d'où se lisent son nom et le système.
String? get userAgentNavigateur => web.window.navigator.userAgent;
