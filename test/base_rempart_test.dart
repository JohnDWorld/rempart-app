import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/base_rempart.dart';

/// Le SDK garde le fichier d'un envoi sous `cache://file/<transaction>`, et
/// annule l'envoi (en vidant son contenu) s'il ne l'y retrouve pas. Sans
/// dossier de fichiers, sa base ne gardait rien : la base de Rempart tient ce
/// cache en mémoire.
void main() {
  test('le cache d’envoi se garde, se relit et s’efface', () async {
    final base = BaseRempart('essai');
    final cle = Uri(scheme: 'cache', host: 'file', path: 'tx1');
    final octets = Uint8List.fromList([1, 2, 3]);

    await base.storeFile(cle, octets, 0);
    expect(await base.getFile(cle), octets);

    expect(await base.deleteFile(cle), isTrue);
    expect(await base.getFile(cle), isNull);
  });

  test('un média reçu ne se garde toujours pas sur le téléphone', () async {
    final base = BaseRempart('essai');
    final mxc = Uri.parse('mxc://serveur/abc');

    await base.storeFile(mxc, Uint8List.fromList([1]), 0);

    expect(await base.getFile(mxc), isNull);
  });
}
