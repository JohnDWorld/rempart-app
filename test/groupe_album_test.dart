import 'package:flutter_test/flutter_test.dart';

/// Le regroupement des médias d'un même envoi.
///
/// La règle décide de ce qu'on voit côte à côte : trop large, elle
/// rassemblerait des photos qui n'ont pas été envoyées ensemble et fausserait
/// l'ordre du fil ; trop étroite, elle ne grouperait rien.
void main() {
  /// Reproduit `grouperParAlbum`, sur des couples (album, expéditeur).
  List<List<String>> grouper(List<(String?, String)> evenements) {
    final groupes = <List<(String?, String)>>[];
    for (final e in evenements) {
      final precedent = groupes.isEmpty ? null : groupes.last;
      final memeAlbum = e.$1 != null &&
          precedent != null &&
          precedent.first.$1 == e.$1 &&
          precedent.first.$2 == e.$2;
      if (memeAlbum) {
        precedent.add(e);
      } else {
        groupes.add([e]);
      }
    }
    return [
      for (final g in groupes) [for (final e in g) e.$1 ?? 'seul'],
    ];
  }

  test('des messages ordinaires restent séparés', () {
    expect(
      grouper([(null, 'john'), (null, 'john'), (null, 'bé')]),
      [['seul'], ['seul'], ['seul']],
    );
  });

  test('trois photos du même envoi tiennent en un groupe', () {
    expect(
      grouper([('a1', 'john'), ('a1', 'john'), ('a1', 'john')]),
      [['a1', 'a1', 'a1']],
    );
  });

  test('un message glissé au milieu coupe le groupe', () {
    // Sinon la grille rassemblerait des photos qu'on n'a pas vues côte à
    // côte, et l'ordre du fil deviendrait faux.
    expect(
      grouper([('a1', 'john'), (null, 'john'), ('a1', 'john')]),
      [['a1'], ['seul'], ['a1']],
    );
  });

  test('deux expéditeurs ne partagent pas un album', () {
    expect(
      grouper([('a1', 'john'), ('a1', 'bé')]),
      [['a1'], ['a1']],
    );
  });

  test('deux envois distincts restent distincts', () {
    expect(
      grouper([('a1', 'john'), ('a2', 'john')]),
      [['a1'], ['a2']],
    );
  });
}
