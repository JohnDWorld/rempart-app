# Rempart Messenger - application

Messagerie chiffree de bout en bout (protocole Matrix), hebergement souverain
en France. Ce depot porte le code de l'application Flutter (Android, iOS, web).

**Version publiee : 1.0.0+64**

## Licence

AGPL-3.0-or-later, voir [LICENSE](LICENSE) et [COPYRIGHT](COPYRIGHT).

Le nom « Rempart » et le logo, eux, ne sont pas couverts par cette licence :
voir [TRADEMARK](TRADEMARK.md). Forkez, modifiez, exploitez ; donnez seulement
un autre nom a votre version.

L'application se lie au SDK Matrix et a vodozemac, tous deux sous AGPL : la
licence se propage, et c'est tres bien ainsi pour une messagerie a qui l'on
confie ses conversations.

## Ce depot est un miroir

Le developpement se fait dans un monorepo prive qui porte aussi
l'infrastructure serveur. Ce miroir recoit un instantane a chaque version
distribuee : un commit, une etiquette, le code exact de l'APK correspondant.
Les tickets et les demandes de fusion ne sont donc pas suivis ici.

Ne sont pas publies : les fichiers chiffres du monorepo (configuration, cle de
signature Android), qui sont de la configuration et des secrets, pas du code.
Voir `.env.example` pour les variables attendues.

La version distribuee par le Play Store differe de celle-ci sur deux points,
tous deux exiges par Google (regle Device and Network Abuse) : la mise a jour
hors magasin y est desactivee (`UPDATE_MANIFEST_URL` vide) et la permission
`REQUEST_INSTALL_PACKAGES` est retiree du manifeste. Rien d'autre ne change.

## Construire

```bash
cp .env.example .env    # puis renseigner les adresses de vos serveurs
flutter pub get
flutter run
```

Le chiffrement passe par une bibliotheque Rust native (vodozemac) compilee au
build : il faut donc Rust et les cibles voulues. Le module WebAssembly de
`web/pkg/` est construit a partir de
[vodozemac](https://github.com/matrix-org/vodozemac) et de
[flutter_vodozemac](https://github.com/famedly/dart-vodozemac).
