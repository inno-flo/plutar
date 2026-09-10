# Plutar — journal des développements (Claude Code)

Ce fichier retrace ce qui a été mis en place avec Claude Code sur ce projet, pour garder une trace indépendante de l'historique Git.

## Objectif du projet

Une app iOS qui collecte des URL partagées depuis Safari ou d'autres apps (feuille de partage iOS) et les classe chronologiquement.

**Phase actuelle (1) :** pas de compte développeur Apple payant, donc pas d'extension de partage réelle. L'app fonctionne avec **40 URL factices**, pré-remplies au premier lancement, réparties sur les 10 derniers jours :

| Source | Nombre |
|---|---|
| macrumors.com | 5 |
| theverge.com | 5 |
| daringfireball.net | 10 |
| nytimes.com | 5 |
| lemonde.fr | 10 |
| reuters.com/technology | 5 |

**Phase 2 (à venir) :** remplacer la génération factice par une vraie Share Extension iOS, une fois le compte développeur payant disponible.

## Origine du design

Un mockup a été réalisé avec **Claude Design** (canvas multi-artboard, partagé via un lien d'artefact `claude.ai/code/artifact/...`). Plutôt que de repartir d'exports PNG, le code source du mockup a été extrait directement du bundle de l'artefact (décompression du manifeste d'assets du fichier `.dc.html`), ce qui a permis de récupérer telles quelles : la donnée de démo, les palettes de couleurs, et la logique d'affichage (React/JS) du prototype.

Éléments repris du mockup dans l'app native :

- Logo « plutar » en minuscule/italique, couleur d'accent, badge de compteur
- 3 onglets : **Date** (chronologique, par défaut), **Sources** (groupé par domaine), **Lus**
- 3 mises en page interchangeables : **Rail horaire** (par défaut), **Fiche**, **Éditoriale**
- Regroupement par jour avec en-tête « pilule » (Aujourd'hui / Hier / date) + nombre de liens
- Swipe pour supprimer + « Annuler » (5 s)
- Réglages (bouton flottant) : 7 thèmes de couleur (Couchant *par défaut*, Crépuscule, Crème, Blanc, Marine, Astronaute, Sang), 2 polices (Futura, Rounded), densité (complet / compact), mise en page
- État vide avec bouton « Simuler un partage » (remplace la vraie feuille de partage tant que la Phase 2 n'est pas là)

## Architecture technique

- **Génération de projet :** [xcodegen](https://github.com/yonaskolb/XcodeGen) à partir de [`project.yml`](project.yml) — évite de committer un `.pbxproj` généré à la main et facilite les diffs Git. Le `.xcodeproj` résultant est un projet Xcode standard, ouvrable et modifiable normalement.
- **UI :** SwiftUI, iOS 17 minimum
- **Persistance :** SwiftData (`@Model`) — le seeding des 40 liens factices se fait une seule fois, à la première ouverture de l'app (`PlutarApp.seedIfNeeded()`)
- **Bundle id :** `com.innoflo.plutar` (placeholder, à ajuster si besoin)

### Structure des fichiers

```
Plutar/
  App/PlutarApp.swift          — point d'entrée, conteneur SwiftData, seed initial
  Models/LinkItem.swift        — modèle SwiftData d'un lien
  Models/AppTheme.swift        — thèmes de couleur, polices, mises en page
  Data/SeedData.swift          — les 40 URL factices + le pool "simuler un partage"
  Views/RootView.swift         — écran principal (onglets, liste groupée, réglages, undo)
  Views/Rows/LinkRowView.swift — rendu d'un lien (rail / fiche / éditoriale)
  Views/EmptyStateView.swift   — état vide
  Views/SettingsSheet.swift    — tiroir de réglages

Design/AppIcon/                — sources vectorielles de l'icône (hors cible Xcode)
  background-light.svg         — ciel crépusculaire clair
  background-dark.svg          — ciel de nuit
  moon.svg                     — le croissant de lune (calque avant)
  page.svg                     — la page + ses lignes (calque avant)
```

## Icône d'app

Une page de journal en verre dépoli, un croissant de lune derrière, sur un ciel
dégradé — motif simple, lisible jusqu'à 40 px. Le seul rappel de marque est la
ligne de titre en `#FF4F00` (l'accent de l'app).

Trois déclinaisons 1024×1024 dans `Plutar/Assets.xcassets/AppIcon.appiconset/`,
déclarées via `appearances` dans `Contents.json` :

| Fichier | Apparence | Fond |
|---|---|---|
| `AppIcon-light-1024.png` | claire (défaut) | ciel `#8FB4E0` → `#E9D6BC` |
| `AppIcon-dark-1024.png` | `luminosity: dark` | nuit `#1B3054` → `#050A14` |
| `AppIcon-tinted-1024.png` | `luminosity: tinted` | transparent, niveaux de gris |

Conformité Liquid Glass :

- toile pleine, sans coins arrondis pré-découpés (le masque est appliqué par le système)
- contenu inscrit dans une marge d'environ 130 px, pour survivre au masque squircle
- la page est un vrai verre dépoli : le fond est échantillonné, flouté (gaussienne 34 px)
  puis lu à travers la forme — la lune transparaît légèrement au travers
- reflet spéculaire en haut à gauche de la page + liseré lumineux sur son contour
- le croissant porte un dégradé d'ombre vers le bas-droite qui lui donne du volume
  (héritage de la version en lune pleine, où sans lui le disque se lisait comme un soleil)

### Forme de la lune

La lune est **deux sphères de diamètre identique, parfaitement superposées** : une
sphère non éclairée, et le croissant lumineux devant elle. Ce que le croissant laisse
ouvert montre donc la face sombre de la lune, pas le ciel — la silhouette reste un
disque plein.

Le croissant lui-même est **construit géométriquement**, pas repris d'un glyphe :
c'est la sphère moins un second cercle décalé vers l'ouverture. Les pointes tombent
exactement là où les deux cercles se croisent — franches et posées sur le limbe, sans
capuchon arrondi ni corne qui dépasse.

Trois réglages nommés dans `MakeIcon.swift`, surchargeables par variables
d'environnement (`OPEN`, `THICK`, `WRAP`) pour tâtonner sans éditer le fichier :

| Réglage | Valeur | Rôle |
|---|---|---|
| `moonOpenAngle` | `-45°` | direction d'ouverture — haut-droite, comme `moon.fill` |
| `moonThickness` | `0.63` | plus grande largeur du croissant, en fraction du rayon |
| `moonWrap` | `70°` | demi-angle des pointes depuis l'axe d'ouverture |

La face non éclairée a son propre dégradé par déclinaison (`moonDarkInner` /
`moonDarkOuter`) : gris-bleu `#BCC6D4` → `#9CA8BA` en clair, `#36435A` → `#202B3D`
en sombre, gris moyen en teinté. Elle doit rester lisible contre son ciel — c'est la
contrainte qui fixe ces valeurs.

Épaisseur et enroulement sont calés pour que le croissant couvre **~40 % du disque**,
soit exactement ce que couvre le glyphe `moon.fill` (mesuré sur son masque alpha :
39,9 %). Même masse visuelle qu'avant, pointes propres.

### Historique des essais

L'icône est passée par trois formes de lune avant celle-ci, ce qui explique certains
choix :

1. **Disque plein orange** (l'accent) — se lisait comme un soleil. D'où le passage à
   une palette crème et l'ajout du dégradé d'ombre.
2. **Glyphe `moon.fill` en masque de découpe** — fidèle à l'UI, mais son ouverture
   vers le haut-droite plaçait le corps épais derrière la page. Une rotation de 210°
   a été essayée pour le dégager, puis abandonnée : l'ouverture devait rester celle
   du symbole. Écarté au final pour ses pointes arrondies et débordantes.
3. **Croissant à deux cercles** — pointes franches, mêmes proportions, mais sa
   concavité laissait voir le ciel : la lune n'avait plus de silhouette ronde.
4. **Deux sphères superposées** (actuel) — la concavité montre la face non éclairée.

### Sources

Les PNG sont rendus par `MakeIcon.swift` (CoreGraphics), pas dessinés à la main —
`swift MakeIcon.swift <chemin de l'appiconset>`. Avec `LAYERS=.` en plus, le script
réécrit aussi `moon.svg` à partir des mêmes constantes, donc les calques ne peuvent
pas dériver du rendu.

Les calques de `Design/AppIcon/` sont les mêmes formes à plat, sans reflets ni ombres
puisque le système les ajoute lui-même, prêts à importer dans **Icon Composer** pour
passer au format `.icon` d'iOS 26. `moon.svg` porte les deux sphères, la découpe du
croissant étant exprimée par un `<mask>` SVG (cercle blanc moins cercle noir) — tout
reste vectoriel.

## État de la vérification

Le projet compile avec succès (`xcodebuild -project Plutar.xcodeproj -scheme Plutar build` → `BUILD SUCCEEDED`).

⚠️ **Le Simulateur iOS n'a pas pu être utilisé pour vérifier visuellement l'app** : il ne fonctionne pas avec Xcode 27 bêta actuellement installé sur cette machine. Consigne en cours : ne pas utiliser le Simulateur tant que ce n'est pas résolu. La vérification se limite donc à la compilation ; le lancement réel doit être fait par l'utilisateur depuis Xcode (ou un Simulateur fonctionnel) une fois le problème réglé.

## Prochaines étapes possibles

- Résoudre le souci de Simulateur avec Xcode 27 bêta (ou tester sur un appareil physique / une version stable d'Xcode)
- Vérifier visuellement l'app une fois le Simulateur disponible, ajuster le rendu par rapport au mockup Claude Design
- Compte développeur payant → ajouter la vraie Share Extension iOS pour remplacer les données factices
- Éventuellement reconstruire l'icône dans Icon Composer (`.icon`) à partir des SVG de `Design/AppIcon/`, pour bénéficier du rendu Liquid Glass dynamique (mode « clear », teinte système) plutôt que de PNG figés
