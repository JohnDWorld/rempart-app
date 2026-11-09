# Rempart Messenger

End-to-end encrypted messaging built on Matrix, with self-hosted,
GDPR-compliant infrastructure in France. This repository holds the Flutter
application (Android, iOS, web).

**Released version: 1.0.0+128** · [rempart-messenger.fr](https://rempart-messenger.fr/en/)

> **Status:** accounts are open, with email address verification. The browser
> version runs at [app.rempart-messenger.fr](https://app.rempart-messenger.fr);
> the Play Store release is in preparation.

## What it does

Encrypted one-to-one and group conversations, voice messages with waveforms,
photo and video albums, replies, reactions, file previews, push notifications
over FCM or UnifiedPush with replies straight from the notification, device
management with QR-code pairing, a browser version, light and dark themes.

Private by default:

- a stranger's first message waits in "Message requests" until you accept it;
- people are found by their exact username, a QR code or a contact link, never
  through a searchable directory;
- photos leave the device without their location, camera model or timestamp,
  full-quality ones included;
- one-time codes and passwords are masked until tapped;
- the account password never leaves the device: two unrelated values are
  derived from it, one to sign in, the other to unlock the key backup.

Its distinctive feature is **user-owned bots**: anyone can create a bot from
the app, receive a token, and drive it with a Telegram-style API (long-poll or
webhook) or over MCP. See
[the agent documentation](https://rempart-messenger.fr/api-bots.md). Bot
conversations are **not** end-to-end encrypted, and the app says so in each of
them; an agent running its own Matrix device gets the same end-to-end
encryption as any contact.

## Licence

AGPL-3.0-or-later. See [LICENSE](LICENSE) and [COPYRIGHT](COPYRIGHT).

The application links against the Matrix Dart SDK (`matrix`) and against
vodozemac (`vodozemac`, `flutter_vodozemac`), all three AGPL-3.0-or-later.
It is therefore a combined work and the licence propagates. That is not a
constraint we merely tolerate: a messenger that claims sovereignty is worth
more when the code can be read by the people who trust it with their
conversations.

The name "Rempart" and the logo are **not** covered by that licence, see
[TRADEMARK](TRADEMARK.md). Fork it, change it, run it commercially; just give
your version another name.

**iOS distribution is pending.** The App Store's contractual and technical
restrictions are difficult to reconcile with AGPLv3 section 10, and we are
seeking an additional permission under section 7 from the copyright holders of
the AGPL dependencies rather than working around the copyleft. Android and the
web version are unaffected.

## This repository is a mirror

Development happens in a private monorepo that also carries the server
infrastructure. This mirror receives a snapshot for every released version:
one commit, one tag, the exact source of the corresponding APK. Issues and
pull requests are therefore not tracked here.

Not published: the monorepo's encrypted files (configuration, Android signing
key), which are secrets and configuration rather than code. See
`.env.example` for the expected variables.

The build distributed through the Play Store differs on three points. Two
are required by Google (Device and Network Abuse policy): out-of-store updates
are disabled (`UPDATE_MANIFEST_URL` left empty) and the
`REQUEST_INSTALL_PACKAGES` permission is removed from the manifest. The
third is hardening: cleartext HTTP is refused (`usesCleartextTraffic="false"`),
which only the development build needs, to reach a private network. Nothing
else changes.

## Building

```bash
cp .env.example .env    # then fill in your own server addresses
flutter pub get
flutter run
```

The `.env` file is mandatory: it is bundled as an asset and loaded before
the app starts. Flutter stable is required.

Encryption goes through a native Rust library (vodozemac) compiled at build
time, so Rust, installed with rustup, and the relevant targets are required.
The WebAssembly module in `web/pkg/` is built from
[vodozemac](https://github.com/matrix-org/vodozemac) and
[flutter_vodozemac](https://github.com/famedly/dart-vodozemac).

---

# Rempart Messenger (français)

Messagerie chiffrée de bout en bout (protocole Matrix), hébergement souverain
en France. Ce dépôt porte le code de l'application Flutter (Android, iOS, web).

**Version publiée : 1.0.0+128** · [rempart-messenger.fr](https://rempart-messenger.fr)

> **État** : les inscriptions sont ouvertes, avec vérification de l'adresse
> électronique. La version navigateur tourne sur
> [app.rempart-messenger.fr](https://app.rempart-messenger.fr) ; la sortie sur
> le Play Store se prépare.

## Ce qu'elle fait

Conversations et groupes chiffrés, messages vocaux avec silhouette du son,
albums de photos et de vidéos, réponses, réactions, aperçu des fichiers,
notifications par FCM ou UnifiedPush avec réponse depuis la notification,
gestion des appareils et connexion par QR code, version navigateur, thèmes
clair et sombre.

Discrète par défaut :

- le premier message d'un inconnu attend dans « Demandes de message » que vous
  l'acceptiez ;
- on trouve quelqu'un par son nom d'utilisateur exact, un code QR ou un lien
  de contact, jamais en parcourant un annuaire ;
- une photo part sans sa position, son appareil ni son heure, en qualité
  d'origine comprise ;
- un code ou un mot de passe reçu reste masqué jusqu'à ce qu'on le touche ;
- le mot de passe du compte ne quitte jamais l'appareil : il en tire deux
  valeurs sans lien, l'une pour se connecter, l'autre pour ouvrir la
  sauvegarde des clés.

Sa particularité : **chacun crée ses propres bots** depuis l'application,
reçoit un jeton, et les pilote par une API façon Telegram (long-poll ou
webhook) ou par MCP. Voir
[la documentation des agents](https://rempart-messenger.fr/api-bots.md). Une
conversation avec un bot n'est **pas** chiffrée de bout en bout, et
l'application le dit dans chacune ; un agent qui tient son propre appareil
Matrix est chiffré comme n'importe quel contact.

## Licence

AGPL-3.0-or-later, voir [LICENSE](LICENSE) et [COPYRIGHT](COPYRIGHT).

L'application se lie au SDK Matrix pour Dart (`matrix`) et à vodozemac
(`vodozemac`, `flutter_vodozemac`), tous trois sous AGPL-3.0-or-later :
c'est une œuvre combinée, et la licence se propage. Ce n'est pas une
contrainte subie : une messagerie qui se réclame de la souveraineté vaut
davantage quand ceux qui lui confient leurs conversations peuvent en lire le
code.

Le nom « Rempart » et le logo ne sont pas couverts par cette licence : voir
[TRADEMARK](TRADEMARK.md). Forkez, modifiez, exploitez ; donnez seulement un
autre nom à votre version.

La distribution sur iOS est **en suspens** : les restrictions de l'App Store se
concilient mal avec l'article 10 de l'AGPLv3, et une permission additionnelle
au titre de l'article 7 est demandée aux titulaires des droits, plutôt qu'un
contournement du copyleft. Android et la version navigateur ne sont pas
concernés.

## Ce dépôt est un miroir

Le développement se fait dans un monorepo privé qui porte aussi
l'infrastructure serveur. Ce miroir reçoit un instantané à chaque version
distribuée : un commit, une étiquette, le code exact de l'APK correspondant.
Les tickets et les demandes de fusion ne sont donc pas suivis ici.

Non publiés : les fichiers chiffrés du monorepo (configuration, clé de
signature Android), qui sont des secrets et de la configuration, pas du code.
Voir `.env.example` pour les variables attendues.

Le paquet du Play Store diffère sur trois points. Deux sont exigés par Google
(règles sur l'abus d'appareils et de réseaux) : la mise à jour hors magasin est
coupée (`UPDATE_MANIFEST_URL` vide) et la permission
`REQUEST_INSTALL_PACKAGES` disparaît du manifeste. Le troisième est un
durcissement : le HTTP en clair est refusé (`usesCleartextTraffic="false"`),
dont seule la version de développement a besoin, pour joindre un réseau privé.
Rien d'autre ne change.

## Construire

```bash
cp .env.example .env    # puis y mettre les adresses de vos serveurs
flutter pub get
flutter run
```

Le `.env` est obligatoire : déclaré comme asset, il est lu avant le
démarrage de l'application. Il faut Flutter en version stable.

Le chiffrement passe par une bibliothèque Rust native (vodozemac), compilée à
la construction : il faut donc Rust, installé par rustup, avec les cibles
voulues. Le module WebAssembly de `web/pkg/` est construit depuis
[vodozemac](https://github.com/matrix-org/vodozemac) et
[flutter_vodozemac](https://github.com/famedly/dart-vodozemac).
