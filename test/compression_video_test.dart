import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/compression_video.dart';

/// Ce qu'on fait d'une vidéo avant l'envoi. Une vidéo de 100 Mo était
/// refusée par le serveur (50 Mo) ; WhatsApp l'envoyait en une douzaine
/// (relevé le 2026-10-23).
void main() {
  const mo = 1024 * 1024;
  const limite = 50 * mo;
  const minute = 60000;

  test('une vidéo 1080p de 100 Mo passe en 720p, au débit visé', () {
    final plan = planCompression(
      taille: 100 * mo,
      dureeMs: minute,
      largeur: 1920,
      hauteur: 1080,
      limite: limite,
    );
    expect(plan, isA<ReencoderVideo>());
    plan as ReencoderVideo;
    expect(plan.debit, debitVise);
    expect(plan.coteCourt, 720);
  });

  test('filmée en portrait, c’est aussi le petit côté qui passe à 720', () {
    final plan = planCompression(
      taille: 100 * mo,
      dureeMs: minute,
      largeur: 1080,
      hauteur: 1920,
      limite: limite,
    ) as ReencoderVideo;
    expect(plan.coteCourt, 720);
  });

  test('déjà en 720p et légère, elle part telle quelle', () {
    expect(
      planCompression(
        taille: 8 * mo,
        dureeMs: minute,
        largeur: 1280,
        hauteur: 720,
        limite: limite,
      ),
      isA<GarderVideo>(),
    );
  });

  test('en 720p mais trop lourde, le débit baisse sans changer la taille', () {
    final plan = planCompression(
      taille: 60 * mo,
      dureeMs: minute,
      largeur: 1280,
      hauteur: 720,
      limite: limite,
    ) as ReencoderVideo;
    expect(plan.coteCourt, 0);
    expect(plan.debit, debitVise);
  });

  test('longue, le débit baisse pour tenir sous la limite', () {
    final plan = planCompression(
      taille: 800 * mo,
      dureeMs: 8 * minute,
      largeur: 1920,
      hauteur: 1080,
      limite: limite,
    ) as ReencoderVideo;
    expect(plan.debit, lessThan(debitVise));
    final octetsAttendus = (plan.debit + debitSon) * 8 * minute / 8000;
    expect(octetsAttendus, lessThan(limite));
  });

  test('trop longue même au débit minimum : on le dit avant d’envoyer', () {
    expect(
      () => planCompression(
        taille: 1500 * mo,
        dureeMs: 15 * minute,
        largeur: 1920,
        hauteur: 1080,
        limite: limite,
      ),
      throwsA(isA<VideoTropLongue>()),
    );
  });

  test('longue mais déjà sous la limite : elle part telle quelle', () {
    expect(
      planCompression(
        taille: 40 * mo,
        dureeMs: 15 * minute,
        largeur: 640,
        hauteur: 360,
        limite: limite,
      ),
      isA<GarderVideo>(),
    );
  });
}
