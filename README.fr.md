<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail" width="880"></p>

[English](README.md) · [Español](README.es.md) · **Français** · [日本語](README.ja.md) · [한국어](README.ko.md) · [简体中文](README.zh-Hans.md)

# Monkeytail

**Un client d’API natif pour iPhone, iPad, Mac et Apple Vision Pro. Apportez vos collections Postman et Insomnia, gardez vos scripts et oubliez la connexion.**

Monkeytail ouvre les collections que vous avez déjà et les exécute de la même façon. Pas de compte Monkeytail, pas d’écran de connexion obligatoire, pas d’espace de travail dans le cloud, pas de télémétrie. Les requêtes partent directement vers vos serveurs, et vos données restent sur vos appareils ou dans votre propre iCloud Drive.

<p><img src="docs/screenshots/iphone-request.png" alt="Éditeur de requêtes sur iPhone" width="285"> <img src="docs/screenshots/iphone-response.png" alt="Réponse JSON sur iPhone" width="285"></p>

## Télécharger

**[Télécharger dans l’App Store](https://apps.apple.com/app/id6814706725)** : gratuit et sans achats intégrés, pour iPhone, iPad, Mac et Apple Vision Pro. Site web : [monk.ieb.app](https://monk.ieb.app)

## Passer de Postman ou Insomnia

- **Importez tout.** Collections Postman (v1, v2, v2.1), environnements, variables globales et exports complets ; exports Insomnia v4 et v5 ; ainsi que Bruno, Hoppscotch, Thunder Client, HAR, fichiers `.http`, OpenAPI/Swagger et cURL. Choisissez plusieurs fichiers ou un dossier entier d’un coup.
- **Ou récupérez-les directement depuis le cloud.** Connectez-vous une fois à Postman, Insomnia ou Hoppscotch pour récupérer vos espaces de travail synchronisés, ou indiquez un dépôt GitHub. La session ne sert qu’à cette importation et n’est jamais enregistrée.
- **Vos scripts fonctionnent toujours.** Les scripts de pré-requête et de test s’exécutent avec une API `pm` compatible Postman, dont `pm.test`, `pm.expect`, `pm.sendRequest`, CryptoJS, lodash et moment. Les scripts d’Insomnia, de Bruno et d’autres clients passent par des objets de compatibilité.
- **La même logique.** Espaces de travail, collections et dossiers imbriqués qui héritent de l’authentification, des en-têtes, des variables et des scripts ; environnements, variables globales et `{{variables}}`, y compris dynamiques comme `{{$guid}}`.
- **Exportez quand vous voulez.** Postman v2.1, Insomnia v4 ou un fichier JSON Monkeytail complet.

## Et aussi

- HTTP, GraphQL avec introspection, WebSocket et événements envoyés par le serveur
- OAuth 2.0 avec PKCE, OAuth 1.0, JWT, AWS Signature V4, Digest, clés d’API, Basic et Bearer
- Un exécuteur de collections avec itérations et fichiers de données CSV/JSON, et export de rapports JSON ou JUnit
- Assertions visuelles, exemples enregistrés, simulations hors ligne et serveur de simulation local
- Un visualiseur de réponses avec JSON formaté, arborescence, recherche, comparaison, images, audio, vidéo et hexadécimal
- Génération de code dans 13 langages, et import et export cURL
- Détail des durées, informations TLS, proxys HTTP/HTTPS/SOCKS5, certificats clients et profils TLS de navigateur facultatifs
- Thèmes, couleurs et polices personnalisés, en anglais, espagnol, français, japonais, coréen et chinois simplifié
- Synchronisation via votre propre iCloud Drive, et une app compagnon Apple Watch pour vos requêtes favorites

En savoir plus : [Outils d’API](docs/APITools.md) · [Scripts](docs/Scripting.md) · [Profils de navigateur](docs/BrowserProfiles.md) · [Espaces de travail d’exemple](docs/examples)

## Compiler

Ouvrez `Monkeytail.xcodeproj` dans Xcode et lancez le schéma **Monkeytail** (iPhone et iPad), **MonkeytailMac** ou **MonkeytailVision**. Nécessite iOS 17, macOS 14 ou visionOS 1. Après avoir modifié `project.yml`, exécutez `xcodegen generate`.

## Tests

```sh
swift test
```

## Licence

[BSD 3-Clause](LICENSE)
