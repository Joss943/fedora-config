# Kickstart Fedora 44 — poste ingé réseau/système
# Design : dock macOS (WhiteSur) + boutons fenêtre à droite (Windows) + GSConnect (KDE) + dark
# Lignes marquées ADAPTE : à vérifier/modifier avant utilisation

lang fr_FR.UTF-8
keyboard fr
timezone Europe/Paris --utc
network --bootproto=dhcp --activate

rootpw --lock
# ADAPTE : génère le hash avec `openssl passwd -6` et colle-le ici
user --name=joss --groups=wheel --iscrypted --password=$6$REMPLACE_PAR_TON_HASH

# ADAPTE : --drives=sda cible UN disque précis (vérifie avec `lsblk` sur la machine cible).
# Sans --drives=, clearpart efface TOUS les disques détectés par l'installeur.
clearpart --all --initlabel --drives=sda
autopart --type=btrfs
bootloader
reboot

%packages
@^workstation-product-environment

# -- Desktop / extensions packagées Fedora --
gnome-tweaks
gnome-extensions-app
gnome-shell-extension-dash-to-dock
gnome-shell-extension-appindicator
gnome-shell-extension-caffeine
gnome-shell-extension-blur-my-shell
gnome-shell-extension-user-theme
gnome-shell-extension-gsconnect

# -- Dépendances thème WhiteSur + extensions git --
git
sassc
glib2-devel
libgtop2
lm_sensors

# -- Boîte à outils réseau --
nmap
nmap-ncat
tcpdump
wireshark
mtr
traceroute
whois
bind-utils
iperf3
net-tools
ethtool
wireguard-tools

# -- Admin système --
htop
btop
tmux
vim-enhanced
tree
jq
ncdu
fastfetch
ansible
openssh-server

# -- Virtualisation (libvirt + virt-manager) --
@virtualization
%end

%post

mkdir -p /etc/dconf/profile /etc/dconf/db/local.d

cat > /etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF

# --- Extensions activées par défaut ---
# UUID = nom du dossier dans /usr/share/gnome-shell/extensions/ une fois installée
cat > /etc/dconf/db/local.d/00-extensions << 'EOF'
[org/gnome/shell]
enabled-extensions=['dash-to-dock@micxgx.gmail.com', 'appindicatorsupport@rgcjonas.gmail.com', 'caffeine@patapon.info', 'blur-my-shell@aunetx', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'compiz-alike-magic-lamp-effect@hermes83.github.com', 'gsconnect@andyholmes.github.io', 'clipboard-indicator@tudmotu.com', 'Vitals@CoreCoding.com']
EOF

# --- Thème WhiteSur (le dock/l'esthétique macOS reste ce qui se fait de mieux côté GTK) ---
cd /tmp
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git
cd WhiteSur-gtk-theme && ./install.sh -d /usr/share/themes -c dark -i fedora
cd /tmp
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git
cd WhiteSur-icon-theme && ./install.sh -d /usr/share/icons

# Noms réels installés (évite de deviner la casse exacte produite par le script)
GTK_THEME=$(ls /usr/share/themes 2>/dev/null | grep -i whitesur | grep -i dark | head -n1)
ICON_THEME=$(ls /usr/share/icons 2>/dev/null | grep -i whitesur | head -n1)

# --- Extensions absentes des dépôts dnf, clonées depuis leurs repos officiels ---
EXT_DIR=/usr/share/gnome-shell/extensions

# Effet "genie" à la minimisation (macOS)
cd /tmp
git clone --depth=1 https://github.com/hermes83/compiz-alike-magic-lamp-effect.git
mkdir -p ${EXT_DIR}/compiz-alike-magic-lamp-effect@hermes83.github.com
cp -r compiz-alike-magic-lamp-effect/* ${EXT_DIR}/compiz-alike-magic-lamp-effect@hermes83.github.com/

# Historique du presse-papier (équivalent Win+V de Windows)
git clone --depth=1 https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator.git ${EXT_DIR}/clipboard-indicator@tudmotu.com

# Monitoring CPU/RAM/temp/réseau dans la barre du haut
git clone --depth=1 https://github.com/corecoding/Vitals.git ${EXT_DIR}/Vitals@CoreCoding.com

# Compile les schemas de tout ce qui vient d'être cloné
for d in ${EXT_DIR}/*/schemas; do
  [ -d "$d" ] && glib-compile-schemas "$d"
done

rm -rf /tmp/WhiteSur-gtk-theme /tmp/WhiteSur-icon-theme /tmp/compiz-alike-magic-lamp-effect

# --- Apparence : dark, WhiteSur, dock macOS en bas, boutons fenêtre à droite (Windows) ---
cat > /etc/dconf/db/local.d/01-look << EOF
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='${GTK_THEME}'
icon-theme='${ICON_THEME}'
show-battery-percentage=true
clock-show-weekday=true

[org/gnome/desktop/peripherals/touchpad]
tap-to-click=true

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'

[org/gnome/shell/extensions/user-theme]
name='${GTK_THEME}'

[org/gnome/shell/extensions/dash-to-dock]
dock-position='BOTTOM'
extend-height=false
transparency-mode='FIXED'
dash-max-icon-size=48
unity-backlit-items=true
EOF

dconf update

# --- Ingé réseau : capture Wireshark sans root + ports GSConnect ---
usermod -aG wireshark joss
firewall-offline-cmd --add-port=1714-1764/tcp
firewall-offline-cmd --add-port=1714-1764/udp

# SSH entrant : installé mais désactivé par défaut. Décommente si tu veux y accéder à distance dès le boot.
# systemctl enable sshd

%end
