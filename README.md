# Rempart Messenger

End-to-end encrypted messaging built on Matrix, with self-hosted,
GDPR-compliant infrastructure in France. This repository holds the Flutter
application (Android, iOS, web).

**Released version: 1.0.0+72** · [rempart-messenger.fr](https://rempart-messenger.fr/en/)

> **Status:** the service is not open to the public yet. The server runs and
> the application works, but new accounts are closed until email verification
> is in place.

## What it does

Encrypted one-to-one and group conversations, voice messages with waveforms,
photo and video albums, replies, reactions, read-once messages, push
notifications over FCM or UnifiedPush, device management with QR-code pairing,
a browser version, light and dark themes.

Its distinctive feature is **user-owned bots**: anyone can create a bot from
the app, receive a token, and drive it with a Telegram-style API (long-poll or
webhook) or over MCP. See
[the agent documentation](https://rempart-messenger.fr/api-bots.md).

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

The build distributed through the Play Store differs on two points, both
required by Google (Device and Network Abuse policy): out-of-store updates are
disabled (`UPDATE_MANIFEST_URL` left empty) and the
`REQUEST_INSTALL_PACKAGES` permission is removed from the manifest. Nothing
else changes.

## Building

```bash
cp .env.example .env    # then fill in your own server addresses
flutter pub get
flutter run
```

Encryption goes through a native Rust library (vodozemac) compiled at build
time, so Rust and the relevant targets are required. The WebAssembly module in
`web/pkg/` is built from
[vodozemac](https://github.com/matrix-org/vodozemac) and
[flutter_vodozemac](https://github.com/famedly/dart-vodozemac).

---

# Rempart Messenger (francais)

Messagerie chiffree de bout en bout (protocole Matrix), hebergement souverain
en France. Ce depot porte le code de l'application Flutter (Android, iOS, web).

**Version publiee : 1.0.0+72** · [rempart-messenger.fr](https://rempart-messenger.fr)

> **Etat** : le service n'est pas encore ouvert au public. Le serveur tourne et
> l'application fonctionne, mais la creation de comptes attend la verification
> des adresses electroniques.

## Licence

AGPL-3.0-or-later, voir [LICENSE](LICENSE) et [COPYRIGHT](COPYRIGHT).

Le nom « Rempart » et le logo ne sont pas couverts par cette licence : voir
[TRADEMARK](TRADEMARK.md). Forkez, modifiez, exploitez ; donnez seulement un
autre nom a votre version.

La distribution sur iOS est **en suspens** : les restrictions de l'App Store se
concilient mal avec l'article 10 de l'AGPLv3, et une permission additionnelle
au titre de l'article 7 est demandee aux titulaires des droits, plutot qu'un
contournement du copyleft. Android et la version navigateur ne sont pas
concernes.

## Ce depot est un miroir

Le developpement se fait dans un monorepo prive qui porte aussi
l'infrastructure serveur. Ce miroir recoit un instantane a chaque version
distribuee : un commit, une etiquette, le code exact de l'APK correspondant.
Les tickets et les demandes de fusion ne sont donc pas suivis ici.
