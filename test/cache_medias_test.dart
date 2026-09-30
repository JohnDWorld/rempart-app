import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/cache_medias.dart';

MediaCharge _media(int taille) => MediaCharge(Uint8List(taille), 1);

void main() {
  test('un média déjà chargé est rendu sans recharger', () async {
    final cache = CacheMedias();
    var chargements = 0;
    Future<MediaCharge> charger() async {
      chargements++;
      return _media(10);
    }

    await cache.obtenir('a', charger);
    await cache.obtenir('a', charger);
    expect(chargements, 1);
    expect(cache.deja('a'), isNotNull);
  });

  test('deux demandes simultanées ne chargent qu une fois', () async {
    final cache = CacheMedias();
    var chargements = 0;
    Future<MediaCharge> charger() async {
      chargements++;
      await Future<void>.delayed(Duration.zero);
      return _media(10);
    }

    await Future.wait(
        [cache.obtenir('a', charger), cache.obtenir('a', charger)]);
    expect(chargements, 1);
  });

  test('au-delà du plafond, le moins récemment vu part', () async {
    final cache = CacheMedias(plafond: 25);
    await cache.obtenir('a', () async => _media(10));
    await cache.obtenir('b', () async => _media(10));
    // « a » redevient récent : c'est « b » qui doit partir.
    cache.deja('a');
    await cache.obtenir('c', () async => _media(10));
    expect(cache.deja('a'), isNotNull);
    expect(cache.deja('b'), isNull);
    expect(cache.deja('c'), isNotNull);
  });

  test('un échec ne reste pas en mémoire', () async {
    final cache = CacheMedias();
    await expectLater(
      cache.obtenir('a', () async => throw Exception('réseau')),
      throwsException,
    );
    expect(cache.deja('a'), isNull);
    final media = await cache.obtenir('a', () async => _media(5));
    expect(media.octets.length, 5);
  });
}
