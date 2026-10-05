# Plutar — journal des développements (Claude Code)

Ce fichier retrace ce qui a été mis en place avec Claude Code sur ce projet, pour garder une trace indépendante de l'historique Git. Les sections d'état (objectif, architecture, structure, vérification) décrivent le projet **actuel** ; les sections suivantes sont un journal chronologique, et certains détails qu'elles mentionnent (données de démo, noms de fonctions) ont depuis disparu — voir « Nettoyage » et « Audit du code » plus bas.

## Objectif du projet

Une app « à lire plus tard » qui collecte les liens partagés depuis Safari ou n'importe quelle app (feuille de partage), les regroupe par jour ou par source, et suit l'état lu/non lu.

- **iOS/iPadOS** (`Plutar`) et **macOS** (`PlutarMac`), chacune avec sa propre extension de partage (`PlutarShare`, `PlutarShareMac`).
- Les quatre processus partagent la même base SwiftData (App Group `group.com.innoflo.plutar`), synchronisée entre appareils par **CloudKit** (`iCloud.com.innoflo.plutar`).
- Les données de démo (40 puis 200 liens factices, « Simuler un partage ») de la phase 1 ont été entièrement retirées une fois l'extension de partage réelle en place.

## Origine du design

Un mockup a été réalisé avec **Claude Design** (canvas multi-artboard, partagé via un lien d'artefact `claude.ai/code/artifact/...`). Plutôt que de repartir d'exports PNG, le code source du mockup a été extrait directement du bundle de l'artefact (décompression du manifeste d'assets du fichier `.dc.html`), ce qui a permis de récupérer telles quelles : la donnée de démo, les palettes de couleurs, et la logique d'affichage (React/JS) du prototype.

Éléments repris du mockup, tels qu'ils ont évolué depuis :

- Badge compteur flottant (nombre de liens de la vue courante)
- 3 vues : **À lire** (ex-« Date », chronologique, par défaut), **Sources** (groupé par domaine), **Lus**
- 3 présentations : **Simple** (ex-« Rail horaire »), **Détaillée** (ex-« Fiche »), **Éditoriale**
- Regroupement par jour avec pilule (Aujourd'hui / Hier / « 1er avril » / année si différente) + nombre de liens
- Swipe pour supprimer + « Annuler » (1,5 s, suppressions groupées)
- Réglages « Affichage » : 8 thèmes (Copenhague, Kamakura, Cap Canaveral, Tokyo, chacun en clair et nuit), Apparence (Claire / Sombre / Automatique), 4 polices (SF Pro, SF Compact, Helvetica Neue, Helvetica Neue Bold), présentation, fond noir pour les thèmes nuit

## Architecture technique

- **Génération de projet :** [xcodegen](https://github.com/yonaskolb/XcodeGen) à partir de [`project.yml`](project.yml) — ne jamais éditer le `.pbxproj` à la main. Les fichiers partagés entre cibles sont listés explicitement par cible dans `project.yml` (voir `CLAUDE.md`).
- **UI :** SwiftUI ; cibles de déploiement iOS 26.6 / macOS 26.0 (Liquid Glass, `Tab`, `glassEffect`).
- **Persistance :** SwiftData (`LinkItem`, `SourceRank`) dans le conteneur de l'App Group, avec `cloudKitDatabase: .private(...)`. Repli sur un conteneur en mémoire (alerte « Stockage indisponible ») si la base ne s'ouvre pas.
- **Enrichissement :** `LinkMetadataEnricher` (app principale uniquement) récupère titre, vignette (`LPMetadataProvider`), nom du site et extrait (une lecture HTML par lien).
- **Réglages d'affichage :** `@AppStorage`, par appareil, non synchronisés (`DisplaySettingsKey`).
- **Bundle id :** `com.innoflo.plutar` (+ `.mac`, `.PlutarShare`, `.mac.PlutarShareMac`).

### Structure des fichiers

```
Plutar/
  App/PlutarApp.swift, AppDelegate.swift   — point d'entrée iOS, push CloudKit
  Models/                                  — LinkItem, SourceRank, AppTheme (thèmes/polices/présentations),
                                             FeedMode, SidebarSelection, DisplaySettingsKey
  Persistence/                             — SharedStore (conteneur + vignettes), AppContainerBootstrap
                                             (conteneur de l'app + modificateur de cycle de vie partagé),
                                             LinkMetadataEnricher, LinkItemFactory, SharedLinkExtraction,
                                             PlatformImage, PlutarLog
  ViewModels/FeedGrouping.swift            — regroupement par jour/source, libellés de dates
  Views/RootView.swift                     — écran iOS (onglets, liste groupée, undo, secousse)
  Views/Rows/LinkRowView.swift             — rendu d'un lien (Simple / Détaillée / Éditoriale), partagé iOS/macOS
  Views/SettingsSheet.swift, SettingsSections.swift, EmptyStateView.swift, FlipCard.swift,
        ShakeGesture.swift, ShareView.swift
  Views/macOS/                             — MacRootView, MacSidebarView, MacFeedList, MacSourceRankingView,
                                             MacSettingsView, SystemAppearanceObserver
PlutarMac/                                 — point d'entrée macOS, AppDelegate
PlutarShare/, PlutarShareMac/              — ShareViewController de chaque extension (+ SharePreprocessor.js côté iOS)

Design/AppIcon/                — sources vectorielles de l'icône + MakeIcon.swift (hors cible Xcode)
  background-light.svg         — ciel crépusculaire clair
  background-dark.svg          — ciel de nuit
  moon.svg                     — le croissant de lune (calque avant)
  page.svg                     — la page + ses lignes (calque avant)
```

## Icône d'app

Une page de journal en verre dépoli et un croissant de lune, sur un **aplat de
couleur** — motif simple, lisible jusqu'à 40 px. Le seul rappel de marque coloré est
la ligne de titre en `#FF4F00` (l'accent de l'app).

Les fonds reprennent des couleurs déjà définies dans `AppTheme.swift` plutôt que des
teintes arbitraires : en clair, le bleu de fond d'une cellule de lien en **Cap
Canaveral** (`card`, `#5F8FC7` — pas son `background` `#2E5D93`, essayé d'abord) ;
en sombre, le noir **Tokyo nuit**.

Trois déclinaisons 1024×1024 dans `Plutar/Assets.xcassets/AppIcon.appiconset/`,
déclarées via `appearances` dans `Contents.json` :

| Fichier | Apparence | Fond |
|---|---|---|
| `AppIcon-light-1024.png` | claire (défaut) | aplat `#5F8FC7` (Cap Canaveral, fond de lien) |
| `AppIcon-dark-1024.png` | `luminosity: dark` | aplat `#000000` (Tokyo nuit) |
| `AppIcon-tinted-1024.png` | `luminosity: tinted` | transparent, niveaux de gris |

Conformité Liquid Glass :

- toile pleine, sans coins arrondis pré-découpés (le masque est appliqué par le système)
- contenu inscrit dans une marge d'environ 130 px, pour survivre au masque squircle
- fond en aplat, sans dégradé ni halo — la profondeur vient des éléments, pas du fond
- la page est un vrai verre dépoli : le fond est échantillonné, flouté (gaussienne 34 px)
  puis lu à travers la forme, si bien que le croissant transparaît là où elle le recouvre
- reflet spéculaire en haut à gauche de la page + liseré lumineux sur son contour
- le croissant garde un dégradé d'ombre vers le bas-droite, qui lui donne du volume

### Position de la feuille

La feuille est décalée vers le haut et vers la droite de **5 % de sa propre taille**,
soit +21,2 px et −26,5 px (`pageOffset` dans `MakeIcon.swift`, dérivé de `pageBase` et
appliqué à la fois au rectangle et à ses lignes, donc les deux ne peuvent pas se
désynchroniser).

Conséquence : la feuille se rapproche du croissant et le recouvre un peu plus — la
part visible du croissant passe de **61,3 % à 52,0 %** de sa surface. Le centrage y
gagne : hors ombre portée, le contenu tombe à moins d'1 px du centre de toile en
horizontal et 8 px en vertical, pour une marge minimale de 156 px. Ombre comprise,
telle qu'elle est cuite dans le PNG, c'est −12,5 / +13,5 px et 133 px de marge.

Un décalage de 5 % **de la toile** (51,2 px) avait d'abord été essayé : il ne laissait
que 41,9 % du croissant visible.

### Forme du croissant

Le croissant est **construit géométriquement** : la sphère de la lune moins un second
cercle décalé vers l'ouverture. Les pointes tombent exactement là où les deux cercles
se croisent — franches et posées sur le limbe, sans capuchon arrondi ni corne qui
dépasse.

| Réglage | Valeur | Rôle |
|---|---|---|
| `moonOpenAngle` | `-45°` | direction d'ouverture — haut-droite, comme `moon.fill` |
| `moonThickness` | `0.63` | plus grande largeur du croissant, en fraction du rayon |
| `moonWrap` | `70°` | demi-angle des pointes depuis l'axe d'ouverture |

Épaisseur et enroulement sont calés pour que le croissant couvre **~40 % du disque**,
soit ce que couvre le glyphe `moon.fill` (mesuré sur son masque alpha : 39,9 %).

Surchargeables par variables d'environnement pour tâtonner sans éditer le fichier :
`OPEN`, `THICK`, `WRAP`, plus `BG` pour l'aplat de la version claire (hexa sans `#`).

### Historique des essais

L'icône est passée par plusieurs états avant celui-ci, ce qui explique certains choix :

1. **Disque plein orange** (l'accent) — se lisait comme un soleil. D'où la palette
   crème et le dégradé d'ombre, tous deux conservés.
2. **Glyphe `moon.fill` en masque de découpe** — fidèle à l'UI, mais pointes arrondies
   et débordant du limbe.
3. **Croissant à deux cercles** — pointes franches, mais sa concavité laissait voir le
   fond : la lune n'avait pas de silhouette ronde.
4. **Deux sphères superposées** — la concavité montrait une face non éclairée. Abandonné
   avec le passage à l'aplat.
5. **Croissant seul sur aplat** (actuel).

Le passage au fond plat a aussi coûté le halo qui détachait la feuille en mode sombre :
son opacité de verre est passée de 0,17 à 0,24 pour compenser.

### Conformité aux HIG

Vérifié contre « App icons » (HIG, révision du 8 juin 2026, « Refined guidance for
Liquid Glass »).

Conforme : 1024×1024 sRGB, carré, pleine toile sans coins pré-découpés ; fond en
aplat (« Prefer a simple background, such as a solid color or gradient ») ; peu de
formes, aucun texte, aucune photo ; arêtes franches sur les calques avant (« avoid
soft and feathered edges » — c'est ce qui condamnait le halo) ; calques vectoriels
SVG sans effet cuit ; contenu centré (centre géométrique à 11 px à gauche et 5 px
sous le centre de toile, marge minimale 134 px).

Deux points restent ouverts :

1. **Le style attendu est « Layered ».** La table des spécifications donne
   `iOS / Layered` : le PNG aplati de l'`appiconset` est la voie de repli, pas la
   voie recommandée. C'est aussi la seule raison pour laquelle l'apparence
   **clear** manque — le format `appiconset` n'a pas d'emplacement pour elle, alors
   que les HIG la citent au même titre que dark et tinted. Passer à `.icon` via Icon
   Composer résout les deux d'un coup ; les calques sont prêts.
2. **Les PNG aplatis cuisent ce que les HIG confient au système** (« there's no need
   to include specular highlights, drop shadows between layers, beveled edges, blurs,
   glows ») : reflet, liseré, ombre portée, flou du verre, dégradé d'ombre du
   croissant. C'est assumé — sans eux un PNG plat n'a aucune profondeur — mais ils
   entreraient en conflit avec les effets système s'ils étaient importés comme
   calques. Les SVG en sont exempts, donc la voie `.icon` n'est pas polluée.

Deux écarts assumés, pour mémoire :

- **Pointes franches du croissant** contre « avoid extremely thin line weights and
  sharp corners, because they tend to lose detail and crispness in smaller icon
  sizes ». Choix explicite, à surveiller sur appareil aux petites tailles.
- **Fond sombre noir**, contre « Color backgrounds generally offer the greatest
  contrast in dark icons ». Le « Avoid using black for your icon's background » des
  HIG ne s'applique pas ici : il figure sous *Platform considerations → watchOS*, et
  l'app ne ciblait alors que l'iPhone (`TARGETED_DEVICE_FAMILY: "1"` ; elle cible
  aujourd'hui aussi l'iPad et le Mac, pas la Watch). Des marines et des
  bleus plus francs ont été essayés (`#0C1A2E`, `#16375C`, `#1E4472`) ; les deux
  derniers se rapprochaient trop du bleu de la version claire. Le noir a été
  retenu, et il fait mieux ressortir le croissant.

  L'opacité du verre de la feuille est restée à 0,24 : sur noir l'écart de luminance
  avec le panneau est plus grand que sur marine, donc elle se détache mieux, sans
  compensation.

Enfin, `background-light.svg` et `background-dark.svg` **ne sont pas à importer** dans
Icon Composer : il sait poser une couleur unie directement (« making it unnecessary to
import custom background images in most cases »). Ces fichiers ne servent qu'à
consigner les hexadécimaux.

### Sources

Les PNG sont rendus par `MakeIcon.swift` (CoreGraphics), pas dessinés à la main —
`swift MakeIcon.swift <chemin de l'appiconset>`. Avec `LAYERS=.` en plus, le script
réécrit **les quatre calques SVG** depuis les mêmes constantes, donc aucun d'eux ne
peut dériver du rendu.

Ces calques sont les mêmes formes à plat, sans reflets ni ombres puisque le système
les ajoute lui-même, prêts à importer dans **Icon Composer** pour passer au format
`.icon` d'iOS 26. `moon.svg` exprime la découpe du croissant par un `<mask>` SVG
(cercle blanc moins cercle noir) — tout reste vectoriel.

## État de la vérification

Les deux apps (et leurs extensions, compilées comme dépendances) compilent sans warning Swift :

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme Plutar -configuration Debug -destination 'generic/platform=iOS Simulator' build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme PlutarMac -configuration Debug -destination 'platform=macOS' build
```

(`xcode-select` pointe sur les Command Line Tools sur cette machine, d'où `DEVELOPER_DIR`.)

⚠️ **Le Simulateur iOS ne fonctionne pas avec Xcode 27 bêta sur cette machine** : la vérification côté Claude se limite à la compilation ; les tests visuels et sur appareil sont faits par l'utilisateur.

## Share Extension (Phase 2)

Compte développeur payant obtenu → ajout d'une vraie extension de partage iOS,
cible `PlutarShare` (`PlutarShare/`), en plus de l'app `Plutar`.

- **Stockage partagé :** `Plutar/Persistence/SharedStore.swift` ouvre le même
  `ModelContainer` (fichier `Plutar.sqlite` dans le conteneur de l'App Group
  `group.com.innoflo.plutar`) depuis l'app et l'extension, donc un lien ajouté
  via la feuille de partage apparaît dans l'app sans relancer quoi que ce
  soit. Entitlement `com.apple.security.application-groups` posé sur les deux
  cibles (`Plutar/Plutar.entitlements`, `PlutarShare/PlutarShare.entitlements`).
- **Construction du lien :** `Plutar/Persistence/LinkItemFactory.swift` — un
  lien réel n'a pas de couleur de source pré-choisie comme les 6 sources
  factices de `SeedData`, donc sa couleur de badge est dérivée
  déterministement du nom d'hôte (palette reprise de `SeedData`).
- **UI :** `PlutarShare/ShareViewController.swift` (`NSExtensionPrincipalClass`)
  extrait l'URL partagée (type `public.url`, avec repli sur `public.text` si
  le texte est lui-même une URL), puis présente `PlutarShare/ShareView.swift`
  — un formulaire minimal (titre modifiable, Annuler/Ajouter) plutôt qu'un
  reflet de `RootView`, l'extension n'affichant jamais que cet unique écran.
  `ShareErrorView` couvre l'absence d'URL exploitable ou l'échec d'ouverture
  du conteneur partagé.
- **Fichiers partagés entre cibles :** `project.yml` liste explicitement
  `LinkItem.swift`, `SourceRank.swift` et `Persistence/` dans les sources de
  `PlutarShare`, en plus de celles de `Plutar` — c'est ce qui garantit que
  les deux cibles utilisent exactement le même schéma SwiftData.
- **Config xcodegen à retenir :** pour une cible `app-extension`, tout le
  contenu de l'`Info.plist` (y compris `NSExtension`) doit passer par
  `info.properties` dans `project.yml` — xcodegen régénère le fichier depuis
  ces propriétés et écrase silencieusement tout ce qui aurait été écrit à la
  main dans le fichier plist lui-même.
- Le bouton « Simuler un partage » (état vide, feuille de réglages) n'a **pas**
  été remplacé par la vraie feuille de partage — il reste utile pour peupler
  rapidement l'app en dev, sans dépendre d'un vrai lien à partager.

Vérifié par compilation (`xcodebuild -scheme Plutar build` → `BUILD
SUCCEEDED`, `PlutarShare.appex` bien embarquée dans `Plutar.app/PlugIns`) ;
pas de vérification visuelle possible ici (Simulateur indisponible, voir
plus bas) — à tester depuis Xcode : partager un lien Safari doit proposer
« plutar » dans la feuille de partage.

### Suite : compatibilité tierce, extrait et miniature réels

Premiers essais sur appareil : le partage fonctionne, mais trois manques —
Plutar absent des apps non Apple et des suggestions de la feuille de
partage ; aucun extrait ni image récupérés (uniquement le titre), ce qui
prive la mise en page Éditoriale de contenu.

- **Règle d'activation élargie** (`PlutarShare/Info.plist` via
  `project.yml`) : la forme dictionnaire simplifiée
  (`NSExtensionActivationSupportsWebURLWithMaxCount`, etc.) ne matche que les
  items typés strictement `public.url` — plusieurs apps tierces (X,
  Mastodon, Reddit…) fournissent le lien en `public.plain-text` à la place.
  Remplacée par la forme **prédicat NSPredicate** libre, qui accepte les
  deux types ; `ShareViewController` continue de rejeter (via
  `ShareErrorView`) un texte partagé qui ne serait pas une URL valide.
  L'apparition dans la **ligne de suggestions** (au-dessus de la liste
  complète), elle, n'a pas d'API — c'est un classement appris par iOS selon
  la fréquence d'usage réel, qui se mettra à jour avec le temps.
- **Extrait et miniature récupérés après coup** — `LinkMetadataEnricher`
  (nouveau, `Plutar/Persistence/`) tourne dans l'app principale (pas dans
  l'extension : trop court en temps d'exécution pour un fetch réseau + décodage
  d'image), déclenché à chaque passage au premier plan (`PlutarApp`,
  `scenePhase == .active`) pour les liens pas encore traités
  (`LinkItem.metadataFetched == false`, mis à `false` uniquement par
  `LinkItemFactory` — les liens de démo restent à `true`, jamais repris) :
  - `LPMetadataProvider` (LinkPresentation) pour le titre réel et l'image de
    prévisualisation — mais cette API **n'expose pas** la description de la
    page, contrairement à ce qu'on pourrait attendre.
  - donc l'extrait est lu à la main : un `URLSession.data(for:)` capé à 64 Ko
    sur l'URL, puis une extraction par regex de
    `<meta property="og:description">` / `<meta name="description">` — ça
    marche quelle que soit l'app source (pas besoin du préprocesseur
    JavaScript de Safari, qui de toute façon ne s'exécute que depuis Safari).
  - la miniature est écrite en JPEG dans le conteneur de l'App Group
    (`SharedStore.thumbnailsDirectoryURL()`, sous-dossier `Thumbnails/`,
    nommée par l'UUID du lien) plutôt que dans le `Documents` de l'app, pour
    rester lisible si l'extension devait un jour l'écrire elle-même.
  - un lien qui échoue (URL morte, pas de réseau, pas de métadonnées) est
    quand même marqué `metadataFetched = true` — pas de nouvelle tentative à
    chaque lancement.
- **`LinkRowView`** affiche maintenant la vraie image quand
  `thumbnailFileName` est renseigné (via un `NSCache` en mémoire pour éviter
  de relire le JPEG à chaque redessin de cellule), et retombe sur le
  placeholder à rayures sinon — inchangé pour les 200 liens de démo, qui
  n'ont jamais de fichier réel.
- `RootView.DeletedSnapshot` (le mécanisme d'annulation à 5 s) a été mis à
  jour pour conserver `thumbnailFileName`/`metadataFetched` : sans ça,
  annuler la suppression d'un lien réel remettait à zéro son enrichissement.

**Extrait restreint aux liens non lus** : le fetch HTML (l'extrait) ne
coûtait rien tant qu'il portait sur peu de liens, mais n'a de sens que dans
Date/Sources (qui n'affichent que les non lus — voir le filtre `mode ==
.read ? … : allItems.filter { !$0.isRead }`), pas dans Lus. Séparé du reste
de l'enrichissement via un second champ dédié,
`LinkItem.excerptFetchAttempted` (indépendant de `metadataFetched`, qui
continue de couvrir titre + miniature sans condition de lecture) :
`LinkMetadataEnricher.enrichExcerpt` ne prend que les liens
`excerptFetchAttempted == false && isRead == false`. `RootView.markAsUnread`
remet `excerptFetchAttempted` à `false`, pour qu'un lien qui repasse en non
lu retente l'extrait plutôt que de rester coincé sur une précédente absence
de résultat.

Point encore ouvert, volontairement laissé de côté : [[read-cell-render-cost-deferred]]
attendait justement de vrais liens du Share Extension pour être profilé
(Instruments, en scrollant Lus) — c'est désormais possible, mais pas fait
ici (nécessite un appareil/Simulateur fonctionnel, hors de portée de cette
machine).

## Nettoyage post-Share Extension : réglages « Avancé »

Le partage réel remplaçant définitivement la simulation :

- Supprimé entièrement : le bouton « Simuler un partage » (`EmptyStateView`),
  sa feuille de confirmation `ShareSimulationSheet` et le pool de 3 liens
  factices qui l'alimentait (`SeedData.PoolEntry`/`SeedData.pool`).
- « Regénérer les liens » retiré des réglages (bouton et câblage) — plus
  aucun appelant, la fonction `regenerateLinks()` a été supprimée avec lui
  plutôt que laissée mais inutilisée.
- Nouvel en-tête **Avancé** dans Affichage, avec dans l'ordre
  « Réinitialiser le classement » puis « Vider le fil » — chacun ouvre
  désormais une boîte de dialogue de confirmation (`.confirmationDialog`)
  avant d'agir, bouton de validation en rôle `.destructive` (rouge,
  comportement standard iOS) contre un « Annuler ».

## Secouer pour changer de thème

Nouveau geste : secouer l'appareil tire un thème au hasard, restreint à la
famille clair/sombre actuellement affichée (un thème clair reste clair, un
soir reste soir) — police, mise en page et tous les autres réglages
d'Affichage restent intacts.

- **`Plutar/Views/ShakeGesture.swift`** — le geste de secousse
  (`UIEvent.EventSubtype.motionShake`), le même mécanisme système que
  « Secouer pour annuler », déjà géré par l'accéléromètre côté UIKit sans
  passer par CoreMotion. Capté en surchargeant `UIWindow.motionEnded`,
  rediffusé en `Notification`, exposé via `View.onShake { }`. C'est le
  même principe que le masquage des prix dans l'app PierreVincent.
- `RootView.shakeToRandomizeTheme()` : tire dans `AppTheme.selectable`
  filtré sur `isSoir == theme.isSoir` (le thème réellement affiché, pas le
  brut stocké — voir le correctif Automatique plus haut), en excluant le
  thème courant. Ne touche qu'à `themeRaw` — jamais `appearanceRaw`, pour
  ne pas sortir l'Apparence d'Automatique.
- Activable/désactivable via une bascule « Secouer pour changer de thème »,
  en tête de la section **Avancé** (`plutar.shakeToChangeTheme`,
  activée par défaut).

## « via Safari » au lieu de « via Partage »

iOS ne dit jamais à une extension quelle app l'a invoquée — c'est pourquoi
`sourceApp` valait systématiquement le générique « Partage ». Un cas fait
exception : **Safari seul** exécute le script JS de préprocessing d'une
extension de partage (`NSExtensionJavaScriptPreprocessingFile`), les autres
apps ne l'exécutent jamais. Sa seule présence sert donc de détection fiable.

- **`PlutarShare/SharePreprocessor.js`** — script minimal qui renvoie
  `document.title` et `document.URL` via `completionFunction`.
- **`project.yml`** — `NSExtensionJavaScriptPreprocessingFile:
  SharePreprocessor` dans `NSExtension` (le fichier est repris tel quel
  comme ressource de l'extension, vérifié dans l'`.appex` généré).
- **`ShareViewController.extractSharedURL`** — vérifie l'attachment
  `public.property-list` (`UTType.propertyList`) *avant* `public.url` :
  quand il est présent, son contenu (`NSExtensionJavaScriptPreprocessingResultsKey`)
  donne l'URL/titre réels et `sourceApp = "Safari"` ; sinon, retombe sur
  `public.url`/`public.plain-text` avec `sourceApp = "Partage"` comme avant.

Limite assumée : seul Safari est distingué. Aucune app tierce (Notes,
Mastodon, Chrome…) ne peut être identifiée par ce biais — c'est une
restriction du système, pas de l'implémentation.

## Favicons désactivés

Retirés de la même façon que « Regénérer les liens » (fonction masquée
*et* désactivée, pas seulement cachée) : `LinkRowView` reçoit désormais
`showFavicons: false` en dur (plus de `@AppStorage("plutar.showFavicons")`,
qui aurait laissé les favicons actifs pour qui l'avait déjà à `true`), et la
bascule « Afficher les favicons » a disparu d'Affichage → Présentation des
liens (qui ne garde que « Afficher les vignettes »).

## Capsules de lien, vignette Détaillée, et le vrai bug du gel/plantage

Trois demandes suite à un usage réel :

- **« via X » retiré des capsules** — `LinkRowView.hostRow` n'affiche plus
  que `item.host` ; `viaString`/le second `Text` ont disparu. Le champ
  `LinkItem.sourceApp` (Safari vs Partage générique, voir plus haut) reste
  en base — il n'était affiché qu'ici.
- **Vignette réduite de 50 % en Détaillée** — `thumbnail(size: 86)` →
  `thumbnail(size: 43)` dans `LinkRowView.cardBody`. Éditoriale (150,
  pleine largeur) inchangée.
- **Le vrai bug derrière le gel puis plantage observé** : `LinkMetadataEnricher`
  n'était pinné à aucun acteur. Appelé depuis un `.task` SwiftUI (donc
  démarré sur le main actor), mais dès le premier `await` dans une fonction
  `nonisolated` par défaut, l'exécution pouvait reprendre sur un thread
  d'arrière-plan — et les mutations de `LinkItem`/`ModelContext.mainContext`
  qui suivaient (assignations de propriétés, `context.save()`) se
  produisaient alors hors du thread principal, alors que `mainContext`
  n'est garanti utilisable que depuis là. D'où le tableau observé : gel,
  puis crash, puis au relancement quelques liens qui avaient bien reçu
  titre/image malgré tout (l'écriture avait eu le temps de partir avant que
  ça casse).

  Corrigé en épinglant tout ce qui touche `context`/`item` à `@MainActor`
  (l'enum entier, sauf les fonctions explicitement `nonisolated` :
  `fetchLinkMetadata`, `fetchMetaDescription`, `metaDescription`,
  `decodeHTMLEntities`, `saveThumbnail`). Le `await` sur une fonction
  `nonisolated` depuis du code `@MainActor` continue de libérer le thread
  principal pendant l'attente réseau — rien n'est perdu côté « ne bloque pas
  l'app », seules les écritures sur le modèle sont maintenant garanties sur
  le bon acteur. `LPMetadataProvider.timeout` fixé à 8 s (aligné sur le
  fetch HTML), pour ne plus dépendre de son délai par défaut en cas d'hôte
  qui ne répond jamais.

## Depuis : port macOS, CloudKit et finitions (sept. 2026)

Résumé des étapes suivantes (le détail est dans l'historique Git) :

- **Port macOS** (`PlutarMac`) : `NavigationSplitView` avec barre latérale (À lire, Lus, une ligne par source, « Classement »), menu contextuel au lieu des swipes, boutons de barre d'outils, Édition > Annuler pour « Marquer lu », vraie scène `Settings` (⌘,), extension de partage macOS.
- **Synchronisation CloudKit** de la base partagée ; push silencieux pour tirer les changements distants au premier plan ; re-téléchargement local des vignettes (les JPEG ne sont jamais synchronisés) ; `rollback()` du contexte sur changement distant pour afficher les liens arrivés déjà enrichis.
- **Extensions de partage** : enregistrement immédiat + HUD de confirmation de 0,7 s ; conteneur conservé pour la durée du processus et attente de l'export CloudKit (sinon rien ne partait avant la prochaine ouverture de l'app).
- **Nom réel du site** (`og:site_name`…) affiché à la place du domaine brut ; quelques noms codés en dur pour les sites qui bloquent la lecture (nytimes.com).
- **Épinglage** des liens (restent dans À lire même ouverts), Lus groupable par source, groupes repliables, séparateurs de mois, classement limité aux 15 premières sources avec suppression d'une source.
- iPad : barre d'onglets flottante (la barre latérale `sidebarAdaptable` a été essayée puis abandonnée).
- **Nettoyage** (14 sept.) : suppression de `SeedData`, des favicons, des placeholders de vignette, de `hasThumbnail` et du réglage « Afficher les vignettes ».

## Audit du code (3 oct. 2026)

Passe de réduction/optimisation sur l'ensemble du code (commit `ac42056`), commentaires conservés : environ 256 lignes de code en moins.

- **Optimisations :** une seule requête HTML par lien pour le nom du site et l'extrait (au lieu de deux) ; regex compilées une fois ; `fetchLimit` au lieu de tout charger ; regroupement des liens calculé une fois par rendu (il était recalculé pour chaque groupe à cause des séparateurs de mois, iOS et macOS) ; dossier des vignettes résolu une fois par processus ; plus de `@Query` permanente sur tous les liens dans les réglages Mac.
- **Code mutualisé :** modificateur `storeLifecycle` commun à `PlutarApp`/`PlutarMacApp` ; `ModelContext.persist`/`deleteLinks` ; alerte `saveFailureAlert` ; style de pastille des réglages ; `FeedGrouping.groups` ; `SourceRank.displayName` ; un seul `LinkItemFactory.save` pour les deux extensions ; actions, en-têtes, menus contextuels et swipes fusionnés dans `RootView`/`MacFeedList`.
- **Supprimé :** `AppTheme.selectable` (= `allCases`), `countForeground` (= `chipText`), couleurs hexadécimales dupliquées, surcharge inutilisée de `SourceRank.bump`.
- **Corrections :** annuler une suppression (iOS) conserve le nom du site ; « Marquer non lu » s'annule sur macOS.
- **Laissé en l'état :** `LinkItem.initial`, `colorHex`, `sourceApp` sont stockés mais jamais affichés — les retirer modifierait le schéma CloudKit (synchro cassée tant que tous les appareils n'ont pas été recompilés).

## Prochaines étapes possibles

- Résoudre le souci de Simulateur avec Xcode 27 bêta (ou tester sur un appareil physique / une version stable d'Xcode)
- Profiler le défilement de Lus avec de vrais liens (coût de rendu des cellules lues, laissé en suspens)
- Retirer éventuellement les champs inutilisés de `LinkItem` lors d'une prochaine migration de schéma planifiée
- Nettoyer `project.yml` : commentaires mentionnant encore `sidebarAdaptable`, réglages redondants (`MACOSX_DEPLOYMENT_TARGET`, `INFOPLIST_KEY_*`, cibles de déploiement globales 17/14)
- Éventuellement reconstruire l'icône dans Icon Composer (`.icon`) à partir des SVG de `Design/AppIcon/`, pour bénéficier du rendu Liquid Glass dynamique (mode « clear », teinte système) plutôt que de PNG figés
