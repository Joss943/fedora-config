# macOS sur Xiaomi Pad 5 (nabu, Snapdragon 860 / SM8150-AC) : le vrai état de l'art (novembre 2026)

## Conclusion en 30 secondes

| Objectif | Faisable ? | Comment |
|---|---|---|
| macOS **natif** sur la Pad 5 (remplacer Android par macOS) | **Non, impossible** | macOS n'a ni noyau, ni pilotes, ni chaîne de démarrage pour un SoC Qualcomm. Personne au monde ne l'a fait, ce n'est pas une question de temps ou de recherche. |
| Linux complet sur la Pad 5 (étape obligatoire) | **Oui, excellent** | Ubuntu 26.04 LTS communautaire, noyau 7.3.3, GPU Adreno 640 accéléré, Wi-Fi, BT, son, stylet, 120 Hz, dual-boot avec Android. |
| macOS **dans une VM émulée** sur la Pad 5 | **Oui, mais lent** | QEMU + TCG (émulation x86-64 pure, pas de KVM) + OpenCore. macOS Catalina démarre et s'installe. Preuve de concept, pas un usage quotidien. |
| macOS **ARM (Apple Silicon) en VM** sur la Pad 5 | **Pas aujourd'hui** | Les projets existent (orchard, vmapple-cli, Ambrosia) mais exigent 16 Go de RAM ou KVM + Pointer Authentication. La Pad 5 a 6 Go et un CPU ARMv8.2 sans PAC. |
| macOS **utilisable au quotidien** sur l'écran de la Pad 5 | **Oui** | Bureau distant vers un vrai Mac ou un Mac mini loué dans le cloud, depuis Ubuntu ou Android. |

Ce dossier contient quatre scripts prêts à l'emploi :

- `01-pc-installer-ubuntu-nabu.sh` (sur le PC) : installe Ubuntu 26.04 sur la tablette, en mode seul ou dual-boot avec Android.
- `02-tablette-macos-vm.sh` (sur la tablette, sous Ubuntu) : télécharge macOS depuis les serveurs Apple, prépare OpenCore et génère `run-macos.sh` réglé pour l'émulation (modes `INSTALLED=1` après installation et `HEADLESS=1` pour VNC).
- `03-tablette-look-macos.sh` (sur la tablette) : habille Ubuntu en macOS, en natif et accéléré par le GPU (thème WhiteSur, dock, boutons à gauche, police Inter). Réversible avec `revert`.
- `04-tablette-mac-distant.sh` (sur la tablette) : installe Remmina et RustDesk pour afficher un vrai Mac, local ou loué dans le cloud, sur l'écran de la Pad 5.

La commande QEMU de `run-macos.sh` a été **testée** en émulation pure (TCG, aucun KVM) : OpenCore s'affiche en une minute. Capture : `preuve-opencore-tcg.png`.

---

## 1. Pourquoi macOS natif est impossible (et le restera)

1. **Pas de noyau pour ce SoC.** XNU ne contient que le support des puces Apple (et des PC Intel jusqu'à macOS 26 Tahoe, dernière version Intel). Aucun pilote pour Snapdragon : ni GPU Adreno, ni Wi-Fi WCN3990, ni UFS, ni écran, ni tactile, ni gestion d'énergie.
2. **Pas de chaîne de démarrage.** macOS ARM exige iBoot et des firmwares signés par Apple. La Pad 5 démarre via XBL/ABL Qualcomm puis, pour Linux/Windows, via un UEFI communautaire (Aloha UEFI / EDK2). Rien ne peut charger un noyau macOS ARM dessus.
3. **Code fermé.** Contrairement à Linux ou même Windows on ARM (qui tourne sur la Pad 5 grâce au projet Renegade), on ne peut pas écrire les pilotes manquants : macOS n'accepte que des kexts signés et le cœur du système est fermé.
4. **Hackintosh = PC Intel/AMD uniquement.** OpenCore fait croire à macOS Intel qu'il est sur un Mac. Il n'y a rien d'équivalent pour un ARM non-Apple, et le projet Asahi fait l'inverse (Linux sur Mac).

## 2. Ce qu'il faut installer d'abord : Ubuntu 26.04 sur la Pad 5

Le port Linux de la Pad 5 est l'un des plus aboutis du monde Android. État matériel (release du 8 novembre 2026, Kumar-Jy / TheMojoMan, noyau 7.3.3-krjy) :

| Fonction | État |
|---|---|
| Écran 2560x1600 120 Hz, tactile 10 points, stylet Xiaomi (pression, inclinaison) | OK |
| GPU Adreno 640 : Vulkan 1.3 (Turnip), OpenGL 4.6 (Freedreno) | OK |
| Wi-Fi, Bluetooth 5.0, 4 haut-parleurs, micros | OK |
| Batterie, charge 15 W, veille S2idle, capteurs et rotation auto | OK |
| USB-C OTG (clavier, souris, hub, stockage) | OK |
| Décodage vidéo matériel (Iris) | OK avec option module |
| Sortie vidéo USB-C DisplayPort | Impossible (limite matérielle) ; DisplayLink OK |
| Caméras | Pas de pilote mainline (CAMSS SM8150 non supporté) |

### Procédure

1. **Déverrouiller le bootloader** (Mi Unlock, compte Xiaomi, attente d'environ 7 jours). Sauvegarder toutes les données.
2. Installer `adb`/`fastboot` sur le PC.
3. **Mode seul (efface Android)** :
   ```bash
   ./01-pc-installer-ubuntu-nabu.sh single
   ```
   Équivalent manuel (tablette en Fastboot : Power + Volume bas) :
   ```bash
   fastboot flash boot_ab images/alohauefi.img
   fastboot flash cust    images/esp.img
   fastboot flash userdata images/rootfs.img
   fastboot reboot
   ```
4. **Mode dual-boot (Android conservé)** : démarrer le TWRP modifié `mod-hybrid` (`fastboot boot twrp.img`), Advanced > Terminal, commande `partition`, disposition « Dual-boot », reboot en recovery, puis :
   ```bash
   ./01-pc-installer-ubuntu-nabu.sh dual
   ```
   ou flasher le ZIP `ubuntu-nabu-installer.zip` directement depuis TWRP (méthode recommandée par le projet, elle patche le boot Android pour que les deux systèmes coexistent via rEFInd).
5. Premier démarrage : assistant GNOME. Mettre à jour (`sudo apt update && sudo apt upgrade`). Les noyaux arrivent par le dépôt APT du projet et les UKI se régénèrent seuls.

Dépannage connu : écran noir au boot sur les unités à UFS Samsung (maintenir Power 10 s et relancer), rotation/luminosité nécessitant le service `hexagonrpcd`, correctif tout-en-un dans le `TROUBLESHOOTING.md` du projet.

## 3. macOS en machine virtuelle sur la tablette (preuve de concept)

### Pourquoi c'est lent : pas de KVM sur un Snapdragon grand public

Sur la Pad 5, le firmware Qualcomm démarre Linux en **EL1** ; l'hyperviseur Qualcomm (QHEE) occupe EL2. `/dev/kvm` n'existe donc pas, même si le noyau est compilé avec KVM. Le remplacement d'hyperviseur `qhypstub` n'existe que pour MSM8916/8939, pas pour SM8150. Toute VM est donc exécutée par **TCG**, le traducteur logiciel de QEMU : chaque instruction x86 du Mac est convertie en ARM64 à la volée. Ordre de grandeur : 10 à 30 fois plus lent que le natif.

### Pourquoi macOS Intel plutôt que macOS ARM

| Voie | Projets | Pourquoi non sur la Pad 5 |
|---|---|---|
| macOS ARM (vmapple) sous KVM | vmapple-cli, reims-vgpu | Exige KVM (impossible, voir ci-dessus) et un CPU avec Pointer Authentication (ARMv8.3). Le Kryo 485 est ARMv8.2. |
| macOS ARM (vmapple) sous TCG | orchard, expérience steelbrain/Ambrosia | Fonctionne sur PC x86 avec 16 Go de RAM et un GPU Vulkan ; le guest demande 10 Go. La Pad 5 n'a que 6 Go. Code de recherche, un seul hôte testé. |
| **macOS Intel + OpenCore sous TCG** | OSX-KVM, OpenCore | Chaîne mature, 3 Go de RAM suffisent, aucun Mac requis pour télécharger l'image (serveurs de récupération Apple). **C'est la voie retenue.** |

### Procédure sur la tablette (sous Ubuntu)

```bash
chmod +x 02-tablette-macos-vm.sh
./02-tablette-macos-vm.sh catalina      # ou big-sur, mojave, high-sierra
~/macos-vm/OSX-KVM/run-macos.sh
```

Le script :

1. installe `qemu-system-x86`, `dmg2img`, `zram-tools` (zram à 50 % pour compenser les 6 Go) ;
2. clone OSX-KVM (OpenCore préconfiguré + OVMF) ;
3. télécharge `BaseSystem.dmg` de Catalina chez Apple via `fetch-macOS-v2.py` (le `macrecovery.py` d'OpenCorePkg), le convertit en `.img` ;
4. crée un disque qcow2 de 64 Go (dynamique) ;
5. écrit `run-macos.sh` avec les réglages validés : `-accel tcg,thread=multi` (utilise les 4 gros cœurs A76), `-cpu Penryn` avec SSE4.2/AVX/AES, 3 Go de RAM, `q35`, `isa-applesmc`, OpenCore sur SATA, affichage `vmware-svga` en 1024x768.

Dans la VM : OpenCore → « macOS Base System » → Utilitaire de disque, formater le disque 64 Go en APFS → installer. Prévoir plusieurs heures et plusieurs redémarrages (choisir « macOS Installer » puis « macOS » dans OpenCore).

### Validation réelle (émulation pure, sans KVM)

Test mené sur un hôte x86 à 4 cœurs sans `/dev/kvm`, donc en TCG comme sur la tablette, avec l'image Catalina téléchargée chez Apple (48/48 blocs vérifiés contre la liste de contrôle signée) :

| Étape | Résultat |
|---|---|
| OpenCore (menu de démarrage) | 40 s |
| Noyau Darwin 19.6.0 lancé | + 15 s |
| launchd, « Early boot complete » | + 2 min |
| Installeur graphique (« Launching the Language Chooser ») | + 4 min |
| Fenêtre « macOS Recovery », examen des volumes (capture `preuve-macos-recovery-tcg.png`) | + 14 min |
| Fenêtre « macOS Utilities » : Réinstaller macOS, Utilitaire de disque (capture `preuve-macos-utilities-tcg.png`) | + 17 min |

**macOS Sonoma (14.6) aussi** : même test avec le modèle CPU `Skylake-Client` (Sonoma exige AVX2) et 4 Go de RAM. Noyau Darwin 23.6.0 lancé, espace utilisateur à 4 min, écran de récupération complet (Réinstaller macOS Sonoma, Safari, Utilitaire de disque) à 16 min. Capture `preuve-sonoma-recovery-tcg.png`. Le script `02` choisit le bon modèle CPU tout seul selon la version demandée.

À ce stade l'installeur est pleinement utilisable à la souris et au clavier : Utilitaire de disque pour formater le disque virtuel en APFS, puis « Reinstall macOS » qui télécharge Catalina complet depuis les serveurs Apple. Le test s'est arrêté là.

**Le piège qui bloque tout le monde en émulation** : avec la ligne `-cpu Penryn` classique d'OSX-KVM, le démarrage reste figé sur la pomme. Le journal série montre une panique `invalid opcode` dans `corecrypto gcm_init` : dès qu'AES-NI est annoncé, la bibliothèque crypto d'Apple utilise PCLMULQDQ, que le modèle Penryn de QEMU n'expose pas. Sous KVM, le vrai processeur exécute l'instruction quand même ; sous TCG, l'émulateur la refuse. La correction tient en un drapeau : `+pclmulqdq` (déjà dans `run-macos.sh`). Un seul cœur ou quatre, même résultat.

### Attentes réalistes

- Sur la Pad 5, l'hôte est ARM, donc traduction x86→ARM64 en plus : comptez 2 à 5 min pour OpenCore, 15 à 40 min pour l'installeur, plusieurs heures d'installation.
- Une fois installé : le Finder, Terminal, Safari léger répondent, avec des secondes de latence. Pas d'accélération graphique (QuickTime, Xcode, jeux, vidéos : non).
- Pourquoi Catalina : dernière version « légère » avant Big Sur, ne requiert pas AVX2 (Ventura et plus l'exigent, et TCG avec `-cpu Penryn` ne l'expose pas). Big Sur fonctionne aussi mais est plus lourd.
- Ne pas monter la RAM de la VM au-delà de 3 Go sur une Pad 5 (Ubuntu + GNOME ont besoin du reste). Si ça swappe : `RAM=2560 ./run-macos.sh`.

## 4. Un macOS fluide sur la Pad 5 : apparence native et déport d'écran

Si l'objectif est d'utiliser macOS sur la tablette (et pas de prouver qu'il y tourne), deux compléments font la différence :

- **Apparence macOS native** (`03-tablette-look-macos.sh`) : thème WhiteSur clair/sombre style Monterey pour GTK et GNOME Shell, icônes et curseurs WhiteSur, police Inter, boutons de fenêtre à gauche, dock Ubuntu en bas centré et auto-masqué façon Dock macOS, lanceur d'applications façon Launchpad, recherche par la touche Super façon Spotlight, gestes 3 doigts natifs. Tout tourne sur l'Adreno 640 à 120 Hz. `./03-tablette-look-macos.sh revert` restaure Ubuntu.
- **Mac réel sur l'écran de la Pad 5** (`04-tablette-mac-distant.sh`) : Remmina (VNC vers le Partage d'écran macOS en réseau local, 2560x1600 plein écran, tactile en souris) et RustDesk (à travers Internet sans ouvrir de port). Côté Mac : Réglages > Général > Partage > Partage d'écran, avec mot de passe VNC.
- **Pas de Mac ?** Mac mini Apple Silicon loués à l'heure ou au mois (Scaleway en Europe, MacStadium, MacinCloud, AWS EC2 Mac). Connexion identique. C'est la solution standard des développeurs iOS sans Mac.

## 5. Note légale

La licence macOS n'autorise l'exécution du système que sur du matériel Apple, y compris en machine virtuelle. La procédure de la partie 3 télécharge macOS depuis les serveurs publics d'Apple sans contourner de DRM, mais son usage sur un appareil non-Apple relève de ta responsabilité.

## Sources

- Ubuntu 26.04 nabu, état matériel, installeur et dépannage : <https://github.com/Kumar-Jy/xiaomi-nabu-ubuntu> et sa release du 08/11/2026 <https://github.com/Kumar-Jy/xiaomi-nabu-ubuntu/releases>
- Port d'origine et noyaux : <https://github.com/TheMojoMan/Xiaomi-Nabu> ; wiki communautaire : <https://linux-on-nabu.gitbook.io/linux-for-mi-pad-5>
- postmarketOS nabu : <https://pkgs.postmarketos.org/package/master/postmarketos/aarch64/device-xiaomi-nabu> ; Arch Linux ARM nabu : <https://github.com/ppanzenboeck/nabu-arch-linux>
- Caméra sans pilote mainline : <https://github.com/xianlly/nabu-linux-camera>
- Windows on ARM sur Pad 5 (Renegade Project) : <https://renegade-project.tech/en/install/> et <https://github.com/ket0x4/NabuWindowsScript>
- Pas d'EL2/KVM sur Snapdragon grand public : <https://xdaforums.com/t/booting-in-el2-for-kvm-use.4215531/> ; qhypstub (MSM8916 seulement) : <https://github.com/msm8916-mainline/qhypstub>
- OSX-KVM (OpenCore, OVMF, fetch-macOS-v2.py) : <https://github.com/kholia/OSX-KVM>
- macOS Intel émulé sous TCG, temps de boot observés (17 min / 8 min multicore) : <https://github.com/utmapp/UTM/discussions/4349> et <https://github.com/techmore/ElementaryOS_MSeries/issues/267>
- macOS ARM en VM sans Mac, prérequis KVM + PAC : <https://github.com/guoPhineas/vmapple-cli>
- macOS ARM sous TCG sur PC (16 Go, guest 10 Go) : <https://github.com/yaelliethy/orchard> ; expérience Ambrosia/reims-vgpu : <https://github.com/steelbrain/experiment-macOS-arm64-on-linux-x86>
- Machine QEMU vmapple (doc officielle) : <https://www.qemu.org/docs/master/system/arm/vmapple.html>
- Darling (couche de compatibilité macOS sur Linux), ARM64 tout juste expérimental : <https://phoronix.com/news/Darling-Using-AI-macOS-Linux>
