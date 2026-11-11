# Xiaomi Domotique Mobile — feuille de route

## Objectif
Personnaliser LuCI Mobile (Flutter, GPL-3.0) pour surveiller un routeur Xiaomi OpenWrt et les équipements réseau depuis un iPhone, avec une interface française soignée. L'identification spécifique des appareils Tuya est exclue à la demande de l'utilisateur. Ne pas remplacer LuCI/Argon.

## Contraintes non négociables
- Ne pas modifier les paramètres réseau du routeur durant le développement.
- Ne jamais exposer LuCI RPC sur Internet ; connexion locale ou VPN seulement.
- Conserver le fonctionnement et les écrans de l'application d'origine.
- Aucune donnée de démonstration présentée comme une mesure réelle.
- Aucune alerte ou mesure de trafic par appareil annoncée sans source technique vérifiée.
- Ne pas ajouter de télémétrie, de service payant ou de dépendance cloud.
- Toute action de blocage, redémarrage ou modification doit demander confirmation.
- Respecter la licence GPL-3.0 et conserver les mentions d'origine.

## Phase 1 — Audit et design
- Inventorier les écrans Flutter, la navigation, les thèmes et les chaînes ARB.
- Vérifier les clés manquantes dans `lib/l10n/app_fr.arb` par rapport à `app_en.arb`.
- Proposer un thème sombre mobile : Accueil, Appareils, Sécurité, Réglages.
- Prévoir les états chargement, erreur, hors ligne et absence de données.

## Phase 2 — Surveillance en lecture seule
- Tableau de bord : état WAN, Wi-Fi, CPU, RAM, disponibilité et débit global, si remontés par RPC.
- Inventaire réseau standard : nom, IP, MAC, interface et dernier état connu selon les données réellement disponibles. Ne pas ajouter de reconnaissance Tuya ni de catégorisation domotique spécifique.
- Nouveaux équipements : comparer les identifiants connus à une liste locale, avec gestion des adresses MAC privées/aléatoires et des faux positifs.
- Sécurité : afficher uniquement des indicateurs étayés par les données OpenWrt disponibles.

## Phase 3 — Validation
- `flutter analyze` et `flutter test` ; tests de traduction et de non-régression.
- Tester en premier lieu sur simulateur ou appareil de développement ; ne pas prétendre avoir testé sur le Xiaomi sans connexion effective.
- Étudier les contraintes de signature et de distribution iOS avant toute promesse d'installation d'une version modifiée.

## État initial vérifié
- Fork `skeudy7/xiaomi-domotique-mobile` accessible en écriture.
- Sur le routeur : `rpcd-mod-luci` et `rpcd-mod-iwinfo` installés ; objet `luci-rpc` disponible.
- Application LuCI Mobile officielle : connexion fonctionnelle sur iPhone, confirmée par l'utilisateur.
