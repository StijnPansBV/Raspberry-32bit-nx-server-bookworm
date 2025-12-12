
#!/bin/bash
set -e

VERSION="3.3.0"
VERSION_FILE="/var/log/install-version"
LOGFILE="/var/log/install-script.log"
SCRIPT_PATH=$(realpath "$0")

echo "=== Installatiescript versie $VERSION gestart ===" | tee -a "$LOGFILE"

# Versiecheck
if grep -q "$VERSION" "$VERSION_FILE" 2>/dev/null; then
    echo "Script al geïnstalleerd (versie $VERSION). Stop." | tee -a "$LOGFILE"
    exit 0
fi

# Tijdzone instellen
echo "Stel tijdzone in op Europe/Brussels..." | tee -a "$LOGFILE"
sudo timedatectl set-timezone Europe/Brussels

# Basisinstallatie
sudo apt update && sudo apt upgrade -y
sudo apt install -y openssh-server cockpit bpytop unattended-upgrades neofetch figlet wget curl parted e2fsprogs git
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades

# Nx Witness installeren
NX_DEB="nxwitness-server-6.0.6.41837-linux_arm32.deb"
if [ ! -f "$NX_DEB" ]; then
    wget https://updates.networkoptix.com/default/41837/arm/$NX_DEB
fi
sudo dpkg -i $NX_DEB || sudo apt-get install -f -y

# Welkomstbanner
{
  figlet "Welkom Stijn Pans BV"
  echo "OS: $(lsb_release -d | cut -f2)"
  echo "Kernel: $(uname -r)"
  echo "Host: $(hostname)"
} | sudo tee /etc/motd
grep -q "neofetch" ~/.bashrc || echo "neofetch" >> ~/.bashrc

# Disk watchdog script
mkdir -p /usr/local/bin /var/log /mnt/media
cat << 'EOF' > /usr/local/bin/disk-watchdog.sh
#!/bin/bash
LOGFILE="/var/log/disk-watchdog.log"
BASE="/mnt/media"
LAST_REBOOT_FILE="/var/log/last_disk_reboot"
echo "$(date): Disk Watchdog gestart" >> "$LOGFILE"

OS_PART=$(df / | tail -1 | awk '{print $1}')
OS_DISK="/dev/$(lsblk -no PKNAME $OS_PART)"
ALL_DISKS=($(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'))

DISKS=()
for D in "${ALL_DISKS[@]}"; do
    [ "$D" != "$OS_DISK" ] && DISKS+=("$D")
done

IFS=$'\n' DISKS=($(sort <<<"${DISKS[*]}"))
unset IFS

INDEX=1
SUCCESS=0
for DISK in "${DISKS[@]}"; do
    PART="${DISK}1"
    LABEL="MEDIA_${INDEX}"
    MOUNTPOINT="$BASE/$LABEL"

    if [ ! -e "$PART" ]; then
        parted "$DISK" --script mklabel gpt
        parted "$DISK" --script mkpart primary 0% 100%
        sleep 3
        mkfs.ext4 -F "$PART"
        sleep 2
    fi

    e2label "$PART" "$LABEL"
    UUID=$(blkid -s UUID -o value "$PART")
    mkdir -p "$MOUNTPOINT"

    LINE="UUID=$UUID $MOUNTPOINT ext4 defaults,nofail,auto 0 0"
    if grep -q "$MOUNTPOINT" /etc/fstab; then
        sed -i "\|$MOUNTPOINT|c\\$LINE" /etc/fstab
    else
        echo "$LINE" >> /etc/fstab
    fi

    mount "$MOUNTPOINT" && SUCCESS=$((SUCCESS+1))
    INDEX=$((INDEX+1))
done

if [ $SUCCESS -eq 0 ]; then
    NOW=$(date +%s)
    if [ ! -f "$LAST_REBOOT_FILE" ] || [ $((NOW - $(cat $LAST_REBOOT_FILE))) -ge 3600 ]; then
        echo "$NOW" > "$LAST_REBOOT_FILE"
        sudo reboot
    fi
fi
EOF
chmod +x /usr/local/bin/disk-watchdog.sh

# NX watchdog script
cat << 'EOF' > /usr/local/bin/nx-watchdog.sh
#!/bin/bash
LOGFILE="/var/log/nx-watchdog.log"
echo "$(date): NX Watchdog gestart" >> "$LOGFILE"
if ! systemctl is-active --quiet networkoptix-mediaserver.service; then
    systemctl restart networkoptix-mediaserver.service
fi
EOF
chmod +x /usr/local/bin/nx-watchdog.sh

# Systemd services en timers voor watchdogs
for svc in disk-watchdog nx-watchdog; do
    echo "[Unit]
Description=$svc Service
[Service]
ExecStart=/usr/local/bin/$svc.sh
Type=oneshot" > "/etc/systemd/system/$svc.service"

    echo "[Unit]
Description=Run $svc every 30 seconds
[Timer]
OnBootSec=15
OnUnitActiveSec=30
[Install]
WantedBy=timers.target" > "/etc/systemd/system/$svc.timer"
done

systemctl daemon-reload
systemctl enable --now disk-watchdog.timer
systemctl enable --now nx-watchdog.timer

# Auto-update script
cat << 'EOF' > /opt/update.sh
#!/bin/bash
LOGFILE="/var/log/update.log"
REPO_DIR="/opt/Raspberry-32bit-nx-server-bookworm"

echo "$(date): Update-check gestart" >> "$LOGFILE"

if [ ! -d "$REPO_DIR" ]; then
    git clone https://github.com/StijnPansBV/Raspberry-32bit-nx-server-bookworm.git "$REPO_DIR"
fi

cd "$REPO_DIR"
git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
    echo "$(date): Nieuwe versie gevonden, update uitvoeren..." >> "$LOGFILE"
    git pull
    chmod +x setup.sh
    sudo ./setup.sh
    echo "$(date): Update voltooid" >> "$LOGFILE"
else
    echo "$(date): Geen update nodig" >> "$LOGFILE"
fi
EOF
chmod +x /opt/update.sh

# Systemd service en timer voor update (elke 15 minuten)
cat << EOF > /etc/systemd/system/github-update.service
[Unit]
Description=GitHub Auto Update Service
After=network.target

[Service]
ExecStart=/opt/update.sh
Type=oneshot
EOF

cat << EOF > /etc/systemd/system/github-update.timer
[Unit]
Description=GitHub Auto Update Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=900   # 15 minuten
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now github-update.timer

# Versie opslaan en script verwijderen
echo "$VERSION" > "$VERSION_FILE"
rm -f "$SCRIPT_PATH"

# Automatische reboot
echo "Installatie voltooid. Systeem wordt herstart..." | tee -a "$LOGFILE"
sudo reboot
