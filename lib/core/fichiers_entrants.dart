// Les fichiers collés (Ctrl+V) ou déposés dans la page, sur le web seulement :
// `package:web` ne se compile pas pour Android ni iOS.

export 'fichiers_entrants_io.dart'
    if (dart.library.js_interop) 'fichiers_entrants_web.dart';
