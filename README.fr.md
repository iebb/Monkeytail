<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail — HTTP et cURL pour iPhone, iPad et Mac, par Kitta Co" width="880"></p>

# Monkeytail

[English](README.md) · [Español](README.es.md) · **Français** · [日本語](README.ja.md) · [한국어](README.ko.md) · [简体中文](README.zh-Hans.md)

**Un débogueur de requêtes natif pour iPhone, iPad, Mac et visionOS, avec une app compagnon compacte pour Apple Watch.** Importez une commande, modifiez votre requête et inspectez la réponse. Développé en SwiftUI, avec un éditeur compact sur iPhone et un espace de travail adaptatif sur ordinateur.

Gratuit. Aucun achat intégré. Aucun compte. Aucune donnée collectée par Kitta Co.

[Produit](https://docs.kitta.co/monkeytail/) · [Confidentialité](https://docs.kitta.co/monkeytail/privacy/) · [Assistance](https://docs.kitta.co/monkeytail/support/) · [Outils API](docs/APITools.md) · [Scripts](docs/Scripting.md) · [Profils de navigateur](docs/BrowserProfiles.md) · [Configuration de publication](docs/Release.md)

<p><img src="docs/screenshots/iphone-request.png" alt="Éditeur de requêtes Monkeytail sur iPhone, avec les en-têtes en ligne" width="285"> <img src="docs/screenshots/iphone-response.png" alt="Visionneuse de réponses JSON de Monkeytail sur iPhone" width="285"></p>

Consultez les [résultats de vérification et captures d’écran sur appareil](docs/Verification.md). Des [espaces de travail d’exemple](docs/examples) importables sont fournis pour Monkeytail, Postman et Insomnia.

## Exécution

Ouvrez **`Monkeytail.xcodeproj`**. Sélectionnez **Monkeytail** pour iPhone/iPad, **MonkeytailMac** pour Mac, **MonkeytailVision** pour visionOS ou **MonkeytailWatch** pour l’app compagnon Watch. Nécessite iOS 17, macOS 14, visionOS 1 ou watchOS 10 ; l’importation de certificats client sur Mac nécessite macOS 15. Les compilations et la vérification utilisent Xcode 27. Choisissez votre équipe de signature pour les appareils physiques et les compilations Mac avec iCloud. Les compilations Debug sur Mac utilisent des entitlements de sandbox distincts pour les tests locaux ad hoc ; la configuration Release active le conteneur iCloud partagé.

Le projet Xcode généré est versionné. Si vous modifiez les réglages des cibles dans `project.yml`, régénérez-le avec [XcodeGen](https://github.com/yonaskolb/XcodeGen) :

```sh
xcodegen generate
```

La collection de départ utilise httpbin.org. Les requêtes ne sont envoyées que lorsque vous touchez **Envoyer** ou utilisez le raccourci clavier d’envoi. Remplacez `base_url` dans l’environnement Playground pour utiliser votre propre serveur.

## Fonctionnalités

- Éditeur de requêtes natif : méthodes, URL, variables de chemin `:name`, en-têtes et paramètres de requête activables ou désactivables avec édition groupée à la Postman, corps JSON, texte, URL-encoded et multipart, envoi de fichiers binaires, authentification héritée, bearer/basic/Digest, clés d’API, signature OAuth 1.0, JWT Bearer (HS/RS/PS/ES 256–512, signé localement à chaque envoi, dans un en-tête ou un paramètre de requête), OAuth 2.0 avec PKCE et actualisation, AWS SigV4, délai d’expiration, redirections.
- Importation et exportation cURL, y compris l’échappement shell, les commandes sur plusieurs lignes, les données, le JSON, les cookies, l’authentification basic et `--digest`, et le choix du proxy. L’importateur analyse le texte ; il n’invoque jamais de shell.
- Collections et dossiers imbriqués avec en-têtes, authentification, variables et scripts hérités ; ajout, renommage, duplication, suppression, recherche et enregistrement local automatique. La synchronisation iCloud Drive est activée par défaut et utilise la session déjà ouverte sur l’appareil ; aucun compte Monkeytail.
- Environnements nommés, variables globales de l’espace de travail et substitution `{{variable}}` dans toutes les requêtes ; variables imbriquées avec détection des variables manquantes et des cycles, ainsi que les variables dynamiques de Postman comme `{{$guid}}`, `{{$timestamp}}` et `{{$randomEmail}}`. Les valeurs résolues s’affichent sous l’URL, et la saisie de `{{` propose des variables.
- Exécuteur de collections et de dossiers : itérations, délai, fichiers de données CSV/JSON, `pm.execution.setNextRequest`/`skipRequest`, résultats de réussite/échec en direct et export de rapport JSON ou JUnit. L’exécution est locale ; aucun compte ni exécuteur dans le cloud.
- Transport HTTP réel, annulation, partage des réponses et diagnostics par saut (DNS, connexion, TLS, envoi, serveur, téléchargement) avec les en-têtes rapportés par le transport et des corps envoyés de taille limitée.
- [Profils de navigateur TLS et HTTP/2](docs/BrowserProfiles.md) facultatifs pour Chrome, Firefox et Safari, y compris des préréglages iOS et Android, sur iOS et Mac. visionOS utilise le TLS système ; la bibliothèque de navigateur épinglée ne propose pas de version pour visionOS. L’exécution est locale avec une version épinglée de curl-impersonate ; la vérification des certificats reste activée.
- Mise en forme JSON, minification dans la bibliothèque principale, coloration syntaxique, arborescence dépliable, recherche par ligne, copie et mise en forme du corps de requête.
- Aperçus d’images selon le type MIME avec zoom par pincement, lecture audio et vidéo native, et visionneuses hexadécimale (décalage/ASCII) et binaire. Les médias non pris en charge peuvent être inspectés octet par octet ou enregistrés.
- Hooks JavaScript locaux avant la requête et après la réponse, avec un sous-ensemble de `pm` compatible Postman : `pm.expect` de style Chai, `pm.response.to.*`, `pm.sendRequest`, variables d’environnement, de collection et globales, cookies, CryptoJS intégré, sous-ensembles de lodash et moment, et journaux de console. Les scripts s’exécutent à chaque envoi, y compris les scripts importés.
- Réseau système ou proxys personnalisés HTTP CONNECT, HTTPS CONNECT encapsulé dans TLS et SOCKS5, avec identifiants facultatifs et sans repli vers une connexion directe en cas d’échec d’un proxy personnalisé.
- Importation OpenAPI/Swagger en JSON et YAML avec indications de paramètres, exemples et validation JSON Schema portable.
- Édition des requêtes, variables et opérations GraphQL, introspection et suggestions de champs de schéma avec recherche.
- Chronologies WebSocket et SSE avec inspection texte, JSON et binaire, filtres, ping, annulation et reconnexion.
- Bocaux à cookies locaux à l’appareil pour chaque environnement, identités client PKCS#12 liées à un hôte exact, et confiance par hôte pour les certificats autosignés (épinglés par empreinte SHA-256 au lieu de désactiver la vérification). Les diagnostics du transport système affichent la chaîne de certificats, la validité, les identifiants TLS et de suite de chiffrement négociés, et le protocole.
- Assertions visuelles sur le statut, le temps, les en-têtes, JSONPath et le schéma, résultats de réussite/échec et vérifications JavaScript modifiables.
- Extraits de code pour cURL, JavaScript fetch, Node.js axios, Python requests, Go, Java HttpClient, C# HttpClient, PHP cURL, Ruby Net::HTTP, Swift URLSession, Kotlin OkHttp, HTTPie et PowerShell, avec masquage facultatif des identifiants.
- Exemples de réponses enregistrés par requête (exemples `response` de Postman), simulations de réponses hors ligne à partir d’exemples, de réponses actuelles ou d’instantanés, avec délais, statuts et erreurs, et un serveur de simulation en boucle locale actif au premier plan.
- Onglets de requêtes sur Mac et iPad, restaurés au relancement, documentation Markdown pour les requêtes, dossiers et collections, et aperçu HTML des réponses en sandbox.
- Importation depuis Postman (collections v1, v2/v2.1, environnements, variables globales et exports de données complets), Insomnia (v4 JSON/YAML et v5 YAML), Bruno (dossiers `.bru` et exports JSON), Hoppscotch, Thunder Client, HAR, fichiers `.http` de VS Code REST Client/JetBrains, OpenAPI et cURL. Sélectionnez plusieurs fichiers ou un dossier entier à la fois.
- Importation directe depuis une autre app : connectez-vous à Postman, Insomnia ou Hoppscotch comme le font leurs propres apps et récupérez vos collections synchronisées, ou connectez un dépôt GitHub. Toutes les collections, tous les environnements et toutes les variables globales sont repris. Les sessions et jetons servent uniquement à cette importation et ne sont jamais enregistrés ; Monkeytail n’a toujours pas de compte.
- Exportation de collections Postman v2.1 et exportation Insomnia v4 JSON. Les versions actuelles d’Insomnia peuvent importer ce format historique.
- Importation et exportation JSON fidèles des espaces de travail Monkeytail, intégration à Fichiers et feuille de partage du système.
- Instantanés de réponses enregistrés avec recherche, comparaison JSON, de statut et d’en-têtes, et extraction JSONPath (`$`, clés, indices, jokers). Les instantanés restent locaux et sont limités à 50 entrées dans 60 Mo.
- Les 50 dernières définitions de requêtes dans l’historique, avec statut et durée ; restauration sans renvoi automatique.
- Apparences claire et sombre, Dynamic Type, libellés VoiceOver, raccourci d’envoi au clavier matériel (⌘↵) et dispositions adaptatives en portrait et en paysage.

## Dispositions selon l’appareil

La barre latérale fonctionne comme celle de Postman : un sélecteur d’espace de travail en haut, puis toutes les collections de cet espace de travail sous forme d’arborescence de dossiers et de requêtes imbriqués. Chaque espace de travail possède ses propres collections, environnements et variables globales, et les données existantes se trouvent dans **Mon espace de travail**. Déplacez les requêtes et les dossiers avec **Déplacer vers** ou en les faisant glisser, et ajoutez un dossier depuis **+** ou depuis le menu d’une collection, d’un dossier ou d’une requête. L’interface est disponible en anglais, espagnol, français, japonais, coréen et chinois simplifié, et suit la langue de l’appareil.

Les couleurs suivent par défaut le système de design. **Réglages → Thème et polices** propose six préréglages (Monkeytail, Navy, Ocean, Ember, Grape, Graphite), une apparence Système/Clair/Sombre, ainsi que des couleurs claires et sombres par rôle pour l’accent, le fond, les surfaces, l’avertissement, le danger, l’information, les autres méthodes et les erreurs. Vous pouvez aussi choisir des polices distinctes pour l’interface et pour le code parmi celles installées sur l’appareil. Les thèmes sont enregistrés sur l’appareil et s’appliquent immédiatement à toutes les fenêtres.

Sur iPhone, la méthode et l’URL restent visibles au-dessus d’un éditeur compact. **Envoyer/Annuler** et **Requête/Réponse** restent en bas, à portée du pouce, et remontent au-dessus du clavier pendant la saisie. Les noms et valeurs des en-têtes et des paramètres partagent une même ligne avec des commandes de 44 points. Sur téléphone, les onglets de réponse se replient pendant la saisie d’une recherche afin que les lignes correspondantes restent visibles au-dessus du clavier. L’aide facultative est repliée, et le nom des requêtes peut être modifié directement dans la barre de navigation. Le partage cURL se trouve dans le menu des actions.

La disposition dépend de la **taille de fenêtre disponible** :

| Espace disponible | Disposition |
| --- | --- |
| Téléphone étroit / fenêtre pliée | Sélecteur Requête/Réponse en bas ; collections via le bouton retour/barre latérale |
| Zone de détail iPad d’au moins 640 × 440 points | Requête et réponse côte à côte |
| Fenêtre de téléphone basse en paysage | Panneau unique pour que l’éditeur reste utilisable |
| Fenêtre d’au moins 1 100 points | Barre latérale des collections plus panneaux de requête et de réponse |
| Appareil pliable entrouvert, pli horizontal (mode table) | Réponse au-dessus de la charnière ; URL, Envoyer et éditeur de requête en dessous. Rien ne chevauche le pli |
| Tailles de texte d’accessibilité | Éditeur à panneau unique pour garder un texte lisible |

La sélection et l’état de l’éditeur sont conservés lors des changements de largeur, des rotations, du redimensionnement des fenêtres sur iPad et des changements de taille des appareils pliables. Sur iOS 27.1 et versions ultérieures, la disposition en mode table suit `UIHingeInteraction` (partiellement ouvert) et la zone réservée `.division` du système, de sorte que la séparation se place exactement sur le pli signalé, avec 7 points de marge de chaque côté. Si la charnière est à plat ou fermée, ou si le pli n’est pas horizontal, les dispositions habituelles s’appliquent.

## App compagnon Apple Watch

Ajoutez une requête aux favoris depuis le menu des actions sur iPhone. Ouvrez **Apple Watch**, touchez un favori pour le copier, puis touchez **Synchroniser** lorsque l’app associée est installée. La Watch affiche jusqu’à dix copies : ouvrez-en une et touchez **Envoyer** ou **Annuler**, puis inspectez le statut, le temps, les en-têtes, ou le texte Formaté/Brut/Hex. La Watch ne propose ni éditeur de requêtes ni interrogation automatique.

L’environnement sélectionné et les en-têtes et l’authentification hérités sont résolus au moment de la copie. **Inclure les identifiants et le corps** est une option enregistrée, activée sauf si vous l’avez désactivée. Les copies utilisent par défaut des fichiers locaux, éventuellement le trousseau, et le dernier contexte d’application de WatchConnectivity. Après modification d’une requête ou changement d’environnement, il faut la copier de nouveau ; Synchroniser supprime les copies qui ne sont plus en favoris. La Watch effectue sa propre requête HTTP : le serveur doit donc être joignable depuis la Watch. Les réponses restent en mémoire. Le transfert entre appareils physiques jumelés doit encore être vérifié sur du matériel réel.

La Watch prend en charge HTTP/GraphQL système, HTTPS vérifié et les en-têtes basic/bearer/clé d’API saisis manuellement. Les proxys, les préréglages TLS de navigateur, les identités client, les cookies, OAuth/JWT/AWS, les scripts, les simulations, WebSocket et SSE restent réservés à l’app complète. Les configurations non prises en charge produisent une erreur avant la copie. Le délai d’expiration est d’au plus 30 secondes, un corps copié d’au plus 32 Ko, le transfert d’au plus 60 Ko, une réponse d’au plus 256 Ko et un corps affiché d’au plus 16 Ko.

La fenêtre visionOS partage avec iPhone et Mac l’éditeur complet de l’espace de travail, les visionneuses de réponses, les outils API et le conteneur iCloud. Sélectionnez le TLS système sur visionOS ; les préréglages TLS de navigateur n’y sont pas disponibles. Les paquets Swift système uniquement et Watch lient les sources de référence par des liens symboliques versionnés, ce qui évite le binaire curl iOS/Mac sur les plateformes non prises en charge.

La version 1.4 est disponible pour iPhone/iPad avec l’app compagnon Watch, pour Mac et pour visionOS. La version 1.5 est en attente de validation par l’App Review sur les trois plateformes. Consultez le [registre des publications](docs/app-store/README.md) pour les builds et la validation. Le transfert vers une Watch physique jumelée et le transfert iCloud en conditions réelles restent non vérifiés.

Sur Mac, la requête et la réponse sont empilées par défaut dans une vue partagée redimensionnable. Choisissez **Actions de l’espace de travail → Disposition de l’espace de travail** pour les placer côte à côte ; la position de séparation est mémorisée pour chaque disposition. La barre latérale reste ouverte pendant le redimensionnement jusqu’à ce que vous la masquiez. Les réglages s’ouvrent dans la fenêtre Réglages native. Utilisez ⌘F pour rechercher une requête, ⇧⌘I pour importer/exporter, ⇧⌘E pour exporter en cURL, ⌘N pour une nouvelle requête et ⌘Retour pour envoyer ou annuler.

## Portée de l’interopérabilité

Le JSON d’espace de travail Monkeytail conserve tous les champs du modèle, les environnements et les réglages de proxy. Les importations ajoutent les collections et les environnements et génèrent de nouveaux identifiants ; les importations natives appliquent aussi leurs réglages de proxy enregistrés. Les scripts importés s’exécutent à l’envoi, comme dans Postman ; vérifiez-les dans chaque onglet Scripts, ou désactivez **Exécuter les scripts** pour les ignorer.

L’exportation Postman conserve les dossiers imbriqués et exporte l’**environnement actif** sous forme de variables de collection. Les importations Postman conservent la hiérarchie des dossiers ainsi que les en-têtes, l’authentification, les variables et les scripts hérités. Les corps bruts, URL-encoded, multipart, fichier et JSON GraphQL sont pris en charge. Les scripts sont conservés ; l’exécution prend en charge les API documentées dans [Scripts](docs/Scripting.md).

Les exports Insomnia v4 JSON/YAML et les collections v5 YAML sont importés avec leur arborescence de dossiers. L’environnement de base devient des variables de collection, les sous-environnements deviennent des environnements, et les environnements, en-têtes, authentifications et scripts des dossiers deviennent des valeurs par défaut de dossier. Les références `{{ _.variable }}` et `{{ _['variable'] }}` sont normalisées. Les balises de modèle (comme le chaînage de réponses) produisent un avertissement et restent sous forme de texte ; les requêtes gRPC sont ignorées.

Les dossiers de collection Bruno (`bruno.json`, `collection.bru`, `folder.bru`, `environments/`) et les exports JSON conservent les dossiers, les valeurs par défaut, les variables d’environnement secrètes, les scripts et les assertions (converties en tests). Les collections et environnements Hoppscotch convertissent les références `<<variable>>` et conservent tous les types d’authentification. Les collections Thunder Client convertissent leurs tests déclaratifs en scripts. Les fichiers HAR regroupent les requêtes par hôte et conservent les réponses enregistrées comme exemples. Les fichiers `.http`/`.rest` conservent les `@variables`, `# @name`, les corps et les gestionnaires de réponse `> {% %}`. Les scripts importés écrits pour ces clients s’exécutent avec des objets de compatibilité ; consultez [Scripts](docs/Scripting.md#other-clients).

Importer → **Importer depuis Postman, Insomnia, Hoppscotch ou GitHub** :

- **Postman :** Monkeytail se connecte de la même façon que l’app de bureau Postman. **Se connecter à Postman** affiche la page de connexion de Postman dans une session de navigation privée (adresse e-mail et mot de passe, GitHub ou SSO) et lit la session dans la redirection finale. Monkeytail liste ensuite vos espaces de travail via la passerelle de Postman et récupère les collections, environnements et variables globales de chaque espace de travail sélectionné depuis le service de synchronisation de Postman, au format v1 utilisé par l’app de bureau. Les comptes US et UE sont tous deux pris en charge. Lorsque plusieurs espaces de travail sont importés, les environnements sont préfixés du nom de leur espace de travail.
- **Insomnia :** Monkeytail se connecte de la même façon que l’app de bureau Insomnia. **Se connecter à Insomnia** ouvre le site d’Insomnia avec une clé à usage unique ; collez le code affiché. Monkeytail ouvre la boîte de connexion scellée, déverrouille les clés de chiffrement de bout en bout du compte, liste les projets Cloud Sync de chaque organisation et récupère le dernier instantané de la branche par défaut de chaque projet sélectionné. Les documents sont déchiffrés sur l’appareil. Les projets locaux et Git Sync ne se trouvent pas dans le cloud d’Insomnia ; utilisez l’option GitHub ou exportez un fichier.
- **Hoppscotch :** saisissez votre adresse e-mail pour recevoir un lien de connexion, puis collez ce lien sans l’ouvrir. Sur hoppscotch.io, il s’agit de la connexion par lien e-mail de l’app web ; sur un serveur auto-hébergé (saisissez l’URL de son backend), il s’agit du lien magique de l’app de bureau. Les collections et environnements personnels, les variables globales ainsi que les collections et environnements de chaque équipe sont importés ; les environnements d’équipe sont préfixés du nom de l’équipe.
- **GitHub :** saisissez `owner/repo`, `owner/repo@branch` ou l’URL d’un dossier (`…/tree/branch/folder`). Tous les fichiers Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, `.http`, HAR et OpenAPI sont importés, et chaque collection Bruno est décodée par rapport à son propre `bruno.json`. Les dépôts publics ne nécessitent aucun jeton ; utilisez un jeton à granularité fine en lecture seule pour les dépôts privés. Au plus 1 000 fichiers et 40 Mo sont importés.

Bruno et Thunder Client stockent les collections sous forme de fichiers ou dans Git. Les identifiants et sessions sont envoyés uniquement au service choisi, via une session éphémère, sans cookies ni cache, et sont supprimés après l’importation.

Les formats tiers ne conservent pas tous les réglages de Monkeytail, comme les délais d’expiration des requêtes ou le choix global du proxy. Une authentification non prise en charge produit un avertissement d’importation ; les options cURL non prises en charge produisent une erreur explicite. Les chemins de fichiers importés ne sont que des métadonnées : choisissez chaque fichier avec Fichiers ou Photos avant l’envoi. Les exportations natives d’espace de travail incluent le contenu des fichiers ; les exportations Postman, Insomnia et cURL font référence aux noms de fichiers. Utilisez Corps → Exporter le fichier pour transférer les pièces jointes réelles avec les exportations tierces. gRPC, les comptes et espaces de travail d’équipe, les moniteurs et simulations dans le cloud, ainsi que les environnements d’exécution de scripts complets des autres clients ne font pas partie de cette version ; Monkeytail n’exige jamais de connexion. L’importation OpenAPI et la validation JSON Schema prennent en charge des sous-ensembles explicitement définis ; consultez [Outils API](docs/APITools.md).

Les profils de navigateur font l’aller-retour via le JSON natif et les commandes `curl-impersonate --impersonate`. Les exportations Postman et Insomnia contiennent des métadonnées `_monkeytail` pour la réimportation dans Monkeytail ; ces apps n’appliquent pas elles-mêmes les profils de navigateur.

## Données et réseau

L’espace de travail et l’historique se trouvent dans le dossier Application Support de l’app et bénéficient de la protection des fichiers de la plateforme et de la sandbox des apps Mac. Les identifiants de l’espace de travail et l’historique utilisent par défaut des fichiers locaux. **Utiliser le trousseau** est facultatif et s’applique aux identifiants de l’espace de travail, aux cookies, aux identités client et aux copies Watch. Lorsque cette option est désactivée, aucune consultation du trousseau n’a lieu au démarrage. Les anciennes valeurs du trousseau restent intactes et peuvent être restaurées en activant l’option ; les exportations incluent les valeurs enregistrées. Il n’y a ni analyse d’usage ni backend exploité par Kitta. La synchronisation iCloud Drive est activée par défaut, et la version 1.6.3 l’active une fois pour les installations existantes (désactivez **Synchronisation iCloud** dans les Réglages pour rester en local) ; elle partage les collections, les environnements, les scripts et les identifiants entre vos appareils, fusionne chaque entité selon sa dernière modification et conserve des marqueurs de suppression. Les modifications de requêtes différentes survivent aux changements simultanés ; pour une même entité, la dernière modification l’emporte. Une copie de récupération locale protégée est conservée avant l’application des changements distants. L’app reste utilisable hors ligne, et la synchronisation vérifie les changements pendant l’utilisation et au retour au premier plan. **Inclure les identifiants** détermine si l’authentification et les champs d’identifiants participent à la synchronisation iCloud ; cette option est activée sauf si vous l’avez désactivée, si bien que tout est synchronisé par défaut. Les cookies, identités client, pièces jointes, instantanés et l’historique des requêtes restent locaux. Les champs comme `Authorization` ou `X-API-Key` ne sont pas marqués automatiquement comme sensibles et restent visibles ; **Marquer comme sensible** masque une valeur. Lorsque **Inclure les identifiants** est désactivé, **Utiliser le trousseau** activé ou le masquage dans le code activé, les noms qui ressemblent à des identifiants restent protégés, sauf s’ils sont marqués comme ordinaires. Les scripts importés ou synchronisés doivent être autorisés sur chaque appareil. Changer de session iCloud sur l’appareil nécessite de désactiver puis de réactiver la synchronisation. Les corps de réponse restent en mémoire jusqu’à leur enregistrement explicite comme instantanés ou leur exportation ; les aperçus audio et vidéo utilisent des fichiers temporaires protégés, supprimés lorsque la réponse en cache correspondante est libérée. Les fichiers laissés par une session interrompue sont nettoyés au lancement après un jour. L’enregistrement explicite exporte les octets d’origine. Les cookies sont activés à la demande pour chaque requête, avec des bocaux distincts et locaux à l’appareil pour chaque environnement. Les sessions n’utilisent jamais les cookies de Safari. OAuth ouvre le fournisseur dans une session de navigation éphémère ; aucun compte Monkeytail n’est créé. Les identités client restent locales à l’appareil, dans des fichiers ou, en option, dans le trousseau. Le serveur de simulation n’écoute que sur 127.0.0.1 et s’arrête lorsque l’app passe en arrière-plan. La vérification de confiance TLS reste activée ; installez une autorité de certification de débogage et faites-lui confiance dans les Réglages d’iOS si nécessaire. ATS autorise HTTP, car cette app est un client généraliste d’API et de débogage.

Les réponses sont limitées à 20 Mo ; les aperçus texte, arborescence et octets à 1 Mo. Les images sont décodées en un aperçu de 2 048 pixels au maximum ; l’enregistrement conserve l’original. La lecture audio et vidéo n’utilise que le fichier téléchargé, les références à des médias externes étant désactivées. La mise en forme JSON, la préparation de l’arborescence et le découpage en lignes s’exécutent hors du thread principal. Les lignes de texte et d’arborescence sont affichées à la demande, les tableaux de lignes sont réutilisés pendant la recherche, et la coloration syntaxique utilise une seule expression compilée avec une limite de longueur pour les lignes longues. Le cache des réponses conserve jusqu’à 8 réponses dans 40 Mo. Les importations sont limitées à 40 Mo, les envois à 20 Mo et les métadonnées iCloud à 20 Mo. Les diffs JSONPath et JSON s’appliquent aux corps jusqu’à 2 Mo, avec des limites de nœuds et de changements. Les contextes JavaScript ont une échéance de trois secondes, utilisent un magasin de données WebKit éphémère et bloquent tout accès réseau direct et toute navigation DOM. Leur seule passerelle native est `pm.sendRequest`, limitée à 10 requêtes HTTP(S) par script via le proxy sélectionné ; il n’existe aucune passerelle vers les fichiers ou l’app. Un contexte qui dépasse l’échéance est abandonné. Les scripts sont une API pratique, pas un environnement d’exécution Node.js généraliste.

## Vérification

Tests purs du modèle, des analyseurs, des collections, de l’encodage, du JSON, de la configuration de proxy, du multipart, de la fusion/des marqueurs de suppression/des secrets de synchronisation, de JSONPath et de la comparaison de réponses :

```sh
swift test
```

Les tests d’intégration et d’interface sur simulateur utilisent des fixtures locales HTTP, TLS/HTTP2, CONNECT et SOCKS5, sans dépendance à des API publiques :

```sh
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone Duo'
# Or pass another installed simulator destination, e.g.:
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

La suite vérifie le transport, le ClientHello TLS et les SETTINGS HTTP/2 sur le réseau, le rejet des certificats, les remplacements d’en-têtes de navigateur, les redirections, la suppression des identifiants d’une origine à l’autre, l’annulation, les limites, les deux protocoles de proxy, la modification, les assertions, les erreurs, les délais et le blocage réseau des scripts, la persistance dans le trousseau, l’éviction des instantanés, les envois multipart et binaires sur les deux transports, les diagnostics par saut, ainsi qu’un parcours d’interface envoi → inspection → importation → modification → export cURL en portrait et en paysage. Les tests d’interface utilisent un espace de travail temporaire isolé et ne modifient pas les collections habituelles de l’utilisateur.

## Structure du projet

```text
Sources/MonkeytailCore/  Codable models, request builder, HTTP transport, cURL,
                        collection codecs, JSON formatting/tree
Sources/MonkeytailCurl/  Small C bridge for the static browser transport
Vendor/                 Pinned curl-impersonate XCFramework and provenance
Monkeytail/Services/    Observable workspace/persistence and WebKit script runner
Monkeytail/Views/       Native adaptive SwiftUI interface
Tests/                 Core Swift package tests
MonkeytailMac/         Mac sandbox/iCloud entitlements and app metadata
MonkeytailMacTests/    Shared advanced hosted integration tests
MonkeytailVision/      Native visionOS app and shared iCloud entitlements
MonkeytailWatch/       Compact favourite-request companion and WatchConnectivity
Packages/              System-only visionOS and bounded Watch core packages
MonkeytailTests/       Hosted simulator integration tests
MonkeytailUITests/     End-to-end device UI tests
Scripts/               Local verification and network fixtures, samples, icon packaging
docs/                  Scripting, release metadata, branding, screenshots
```

Références des protocoles : [configuration de proxy Apple](https://developer.apple.com/documentation/network/proxyconfiguration), [exécution JavaScript WebKit](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)), [schéma Postman](https://schema.postman.com/), [importation/exportation Insomnia](https://developer.konghq.com/insomnia/import-export/).

## Licence

Publié sous la [licence BSD à 3 clauses](LICENSE). Les pages publiques du produit, de l’assistance et de confidentialité sont hébergées sur [docs.kitta.co](https://docs.kitta.co/monkeytail/).

Les composants tiers conservent leurs propres licences ; leurs mentions figurent dans Réglages → Licences. Consultez la [provenance des composants tiers](Vendor/README.md) pour les binaires épinglés et la procédure de régénération.
