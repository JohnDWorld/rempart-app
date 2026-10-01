// La signature du navigateur, sur le web seulement : `package:web` ne se
// compile pas pour Android ni iOS.
export 'user_agent_io.dart' if (dart.library.js_interop) 'user_agent_web.dart';
