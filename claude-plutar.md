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
```

## État de la vérification

Le projet compile avec succès (`xcodebuild -project Plutar.xcodeproj -scheme Plutar build` → `BUILD SUCCEEDED`).

⚠️ **Le Simulateur iOS n'a pas pu être utilisé pour vérifier visuellement l'app** : il ne fonctionne pas avec Xcode 27 bêta actuellement installé sur cette machine. Consigne en cours : ne pas utiliser le Simulateur tant que ce n'est pas résolu. La vérification se limite donc à la compilation ; le lancement réel doit être fait par l'utilisateur depuis Xcode (ou un Simulateur fonctionnel) une fois le problème réglé.

## Prochaines étapes possibles

- Résoudre le souci de Simulateur avec Xcode 27 bêta (ou tester sur un appareil physique / une version stable d'Xcode)
- Vérifier visuellement l'app une fois le Simulateur disponible, ajuster le rendu par rapport au mockup Claude Design
- Compte développeur payant → ajouter la vraie Share Extension iOS pour remplacer les données factices
- Icône d'app réelle (actuellement un `AppIcon.appiconset` vide)
