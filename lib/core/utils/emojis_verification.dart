/// Noms français des symboles de vérification.
///
/// Le SDK ne les donne qu'en anglais (« Thumbs Up », « Light Bulb »), alors
/// que les deux personnes qui comparent lisent le même écran dans leur langue.
/// Un nom incompris oblige à se fier au seul dessin, et c'est précisément ce
/// qu'il ne faut pas : « Chat » et « Lion » se distinguent mieux par le mot
/// que par une vignette de trente pixels.
///
/// Les 64 symboles sont fixés par la spécification Matrix : la table est donc
/// close, et un nom inconnu ne peut venir que d'une évolution du SDK. Dans ce
/// cas on rend l'anglais plutôt que rien.
const _traductions = <String, String>{
  'Dog': 'Chien',
  'Cat': 'Chat',
  'Lion': 'Lion',
  'Horse': 'Cheval',
  'Unicorn': 'Licorne',
  'Pig': 'Cochon',
  'Elephant': 'Éléphant',
  'Rabbit': 'Lapin',
  'Panda': 'Panda',
  'Rooster': 'Coq',
  'Penguin': 'Manchot',
  'Turtle': 'Tortue',
  'Fish': 'Poisson',
  'Octopus': 'Pieuvre',
  'Butterfly': 'Papillon',
  'Flower': 'Fleur',
  'Tree': 'Arbre',
  'Cactus': 'Cactus',
  'Mushroom': 'Champignon',
  'Globe': 'Globe',
  'Moon': 'Lune',
  'Cloud': 'Nuage',
  'Fire': 'Feu',
  'Banana': 'Banane',
  'Apple': 'Pomme',
  'Strawberry': 'Fraise',
  'Corn': 'Maïs',
  'Pizza': 'Pizza',
  'Cake': 'Gâteau',
  'Heart': 'Cœur',
  'Smiley': 'Sourire',
  'Robot': 'Robot',
  'Hat': 'Chapeau',
  'Glasses': 'Lunettes',
  'Spanner': 'Clé plate',
  'Santa': 'Père Noël',
  'Thumbs Up': 'Pouce levé',
  'Umbrella': 'Parapluie',
  'Hourglass': 'Sablier',
  'Clock': 'Horloge',
  'Gift': 'Cadeau',
  'Light Bulb': 'Ampoule',
  'Book': 'Livre',
  'Pencil': 'Crayon',
  'Paperclip': 'Trombone',
  'Scissors': 'Ciseaux',
  'Lock': 'Cadenas',
  'Key': 'Clé',
  'Hammer': 'Marteau',
  'Telephone': 'Téléphone',
  'Flag': 'Drapeau',
  'Train': 'Train',
  'Bicycle': 'Vélo',
  'Aeroplane': 'Avion',
  'Rocket': 'Fusée',
  'Trophy': 'Trophée',
  'Ball': 'Ballon',
  'Guitar': 'Guitare',
  'Trumpet': 'Trompette',
  'Bell': 'Cloche',
  'Anchor': 'Ancre',
  'Headphones': 'Casque',
  'Folder': 'Dossier',
  'Pin': 'Punaise',
};

/// Nom français d'un symbole, ou le nom d'origine si on ne le connaît pas.
String nomEmojiVerification(String nomAnglais) =>
    _traductions[nomAnglais] ?? nomAnglais;

/// Noms anglais couverts par la table.
///
/// Exposé pour que le test constate la couverture des 64 symboles : plusieurs
/// se traduisent par eux-mêmes (Lion, Robot, Pizza), comparer les chaînes ne
/// dirait donc rien.
Set<String> get nomsEmojiCouverts => _traductions.keys.toSet();
