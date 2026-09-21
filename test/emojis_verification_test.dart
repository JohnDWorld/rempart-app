import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/emojis_verification.dart';

void main() {
  group('nomEmojiVerification', () {
    test('traduit les noms du SDK', () {
      expect(nomEmojiVerification('Thumbs Up'), 'Pouce levé');
      expect(nomEmojiVerification('Light Bulb'), 'Ampoule');
      expect(nomEmojiVerification('Mushroom'), 'Champignon');
    });

    test("rend le nom d'origine si inconnu", () {
      // Une evolution du SDK ne doit pas faire disparaitre le libelle : sans
      // nom, il ne resterait que la vignette a comparer.
      expect(nomEmojiVerification('Spaceship'), 'Spaceship');
    });

    test('couvre les 64 symboles de la spécification', () {
      const duSdk = [
        'Dog', 'Cat', 'Lion', 'Horse', 'Unicorn', 'Pig', 'Elephant', 'Rabbit',
        'Panda', 'Rooster', 'Penguin', 'Turtle', 'Fish', 'Octopus',
        'Butterfly', 'Flower', 'Tree', 'Cactus', 'Mushroom', 'Globe', 'Moon',
        'Cloud', 'Fire', 'Banana', 'Apple', 'Strawberry', 'Corn', 'Pizza',
        'Cake', 'Heart', 'Smiley', 'Robot', 'Hat', 'Glasses', 'Spanner',
        'Santa', 'Thumbs Up', 'Umbrella', 'Hourglass', 'Clock', 'Gift',
        'Light Bulb', 'Book', 'Pencil', 'Paperclip', 'Scissors', 'Lock',
        'Key', 'Hammer', 'Telephone', 'Flag', 'Train', 'Bicycle', 'Aeroplane',
        'Rocket', 'Trophy', 'Ball', 'Guitar', 'Trumpet', 'Bell', 'Anchor',
        'Headphones', 'Folder', 'Pin',
      ];
      expect(duSdk.length, 64);
      // Plusieurs symboles se traduisent par eux-memes (Lion, Robot, Pizza) :
      // comparer les chaines ne prouverait rien. On verifie la couverture.
      expect(nomsEmojiCouverts, containsAll(duSdk));
      expect(nomsEmojiCouverts.length, 64);
    });
  });
}
