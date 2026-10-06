// Le téléchargement par le navigateur, sur le web seulement : `package:web` ne
// se compile pas pour Android ni iOS.
export 'telechargement_io.dart'
    if (dart.library.js_interop) 'telechargement_web.dart';
