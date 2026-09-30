import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/partage_entrant.dart';

void main() {
  test('des photos', () {
    expect(resumePartage(['image/jpeg'], null), '1 photo');
    expect(resumePartage(['image/jpeg', 'image/png'], null), '2 photos');
  });

  test('des vidéos, puis un mélange des deux', () {
    expect(resumePartage(['video/mp4'], null), '1 vidéo');
    expect(
        resumePartage(['image/jpeg', 'video/mp4'], null), '2 photos et vidéos');
  });

  test('tout le reste est un fichier, type inconnu compris', () {
    expect(resumePartage(['application/pdf'], null), '1 fichier');
    expect(resumePartage(['image/jpeg', null], null), '2 fichiers');
  });

  test('sans fichier, le texte partagé tient lieu de résumé', () {
    expect(resumePartage([], ' https://exemple.fr '), 'https://exemple.fr');
  });
}
