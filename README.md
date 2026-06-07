# ⚡ POWER TYCOON — Tycoon de Production & Vente d'Électricité

Tycoon Roblox **100 % généré par le code** (aucun objet à placer à la main dans
Studio). Tu lances une partie de test et le tycoon se construit tout seul :
dalle, générateurs (solaire / éolien / hydro / nucléaire / VIP), batteries,
câbles néon, pads d'achat avec prix en 3D, et une interface premium animée.

---

## 🗂️ Arborescence du projet

```
Roblox-2/
├── default.project.json          ← mapping Rojo (sync auto vers Studio)
├── README.md
├── .gitignore
└── src/
    ├── shared/                   → ReplicatedStorage > Shared
    │   ├── GameConfig.luau           (ModuleScript) — TOUTE la config / l'équilibrage
    │   ├── Format.luau               (ModuleScript) — formatage des nombres ($, W)
    │   └── Remotes.luau              (ModuleScript) — crée/expose les RemoteEvents
    │
    ├── server/                   → ServerScriptService
    │   └── MainServer.server.luau    (Script)       — point d'entrée serveur
    │
    ├── serverstorage/            → ServerStorage > Modules
    │   ├── BuildingFactory.luau      (ModuleScript) — le "BuildingModule" (géométrie)
    │   ├── DataService.luau          (ModuleScript) — DataStore + backup (anti-perte)
    │   ├── MarketService.luau        (ModuleScript) — prix du marché fluctuant
    │   ├── MonetizationService.luau  (ModuleScript) — Gamepasses & Dev Products
    │   └── PlotService.luau          (ModuleScript) — cœur du gameplay (plots, éco)
    │
    └── client/                   → StarterPlayer > StarterPlayerScripts
        └── ClientMain.client.luau    (LocalScript)  — toute l'UI + effets 3D
```

### Où chaque fichier doit finir dans l'Explorer Roblox

| Fichier source                        | Emplacement final dans Studio                              | Type           |
|---------------------------------------|-----------------------------------------------------------|----------------|
| `src/shared/GameConfig.luau`          | `ReplicatedStorage > Shared > GameConfig`                 | ModuleScript   |
| `src/shared/Format.luau`              | `ReplicatedStorage > Shared > Format`                     | ModuleScript   |
| `src/shared/Remotes.luau`             | `ReplicatedStorage > Shared > Remotes`                    | ModuleScript   |
| `src/server/MainServer.server.luau`   | `ServerScriptService > MainServer`                        | Script         |
| `src/serverstorage/BuildingFactory.luau`   | `ServerStorage > Modules > BuildingFactory`          | ModuleScript   |
| `src/serverstorage/DataService.luau`       | `ServerStorage > Modules > DataService`              | ModuleScript   |
| `src/serverstorage/MarketService.luau`     | `ServerStorage > Modules > MarketService`            | ModuleScript   |
| `src/serverstorage/MonetizationService.luau` | `ServerStorage > Modules > MonetizationService`    | ModuleScript   |
| `src/serverstorage/PlotService.luau`       | `ServerStorage > Modules > PlotService`              | ModuleScript   |
| `src/client/ClientMain.client.luau`   | `StarterPlayer > StarterPlayerScripts > ClientMain`       | LocalScript    |

> ⚠️ Les noms des dossiers `Shared` (dans ReplicatedStorage) et `Modules`
> (dans ServerStorage) doivent être respectés **à l'identique** : les scripts
> se retrouvent par ces chemins.

---

## 🚀 Installation

### Option A — Rojo (recommandé, automatique)

1. Installe [Rojo](https://rojo.space/) (extension Studio + CLI `aftman`/`foreman`).
2. À la racine du projet : `rojo serve`
3. Dans Studio, ouvre le plugin Rojo → **Connect**. Toute l'arborescence
   ci-dessus est créée automatiquement.
4. Appuie sur **Play** ▶️ — le tycoon se construit sous tes yeux.

### Option B — Copier/coller manuel dans Studio

1. Crée les dossiers (`Folder`) et scripts comme dans le tableau ci-dessus
   (clic droit → *Insert Object*).
2. Colle le contenu de chaque fichier `.luau` dans le script correspondant.
   - `*.server.luau` → **Script**
   - `*.client.luau` → **LocalScript**
   - `*.luau`        → **ModuleScript**
3. Appuie sur **Play** ▶️.

---

## 🔧 LA SEULE étape manuelle : les IDs de monétisation

Le code de monétisation est **complet et actif**. La seule chose que le code ne
peut pas inventer, ce sont les **IDs des Gamepasses / Developer Products** :
ils se créent sur le **Creator Hub** (Monetization) et sont propres à TON jeu.

Ouvre `ReplicatedStorage > Shared > GameConfig` et remplace les `Id = 0` :

```lua
GameConfig.Gamepasses = {
    DoubleEnergy = { Id = 0, ... },  -- ← mets ton vrai Gamepass ID
    AutoSell     = { Id = 0, ... },  -- ← idem
    VIP          = { Id = 0, ... },  -- ← idem
}
GameConfig.Products = {
    Cash10k     = { Id = 0, ... },   -- ← ton Developer Product ID
    Cash100k    = { Id = 0, ... },
    FullBattery = { Id = 0, ... },
}
```

Tant qu'un `Id` vaut `0`, la fonctionnalité est **désactivée proprement**
(aucune erreur) : le jeu tourne, le bouton affiche juste « non configuré ».

---

## 💾 Sauvegarde (DataStore)

- Pour tester la sauvegarde en Studio : **Game Settings → Security →
  *Enable Studio Access to API Services*** (activé).
- Si l'API n'est pas dispo, le jeu passe en **mode SESSION-ONLY** : il tourne
  normalement mais ne sauvegarde pas (au lieu de planter).
- Sécurité anti-perte : DataStore **principal + backup** sur clés séparées, et
  si le chargement initial échoue, on **n'écrase jamais** la sauvegarde existante.

---

## 🎮 Boucle de jeu

1. **Produire** : achète des générateurs (pads au sol) → Watts/seconde.
2. **Stocker** : les Watts s'accumulent dans la batterie (capacité max).
3. **Vendre** : bouton **VENDRE** (ou marche sur le pad vert) → Watts × prix
   du marché × multiplicateur de rebirth = **$**.
4. **Marché** : le prix de l'énergie fluctue toutes les 60 s (sinusoïde + bruit).
5. **Auto-Sell** : vend automatiquement (réglage gratuit ou Gamepass).
6. **Rebirth** ⭐ : recommence à zéro contre un bonus **permanent** sur les ventes.

Tout l'équilibrage (prix, production, capacités, rebirth, marché) se règle
dans **`GameConfig.luau`**.
