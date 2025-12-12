
#!/bin/bash
set -euo pipefail

VERSION="1.0.1"  # Nieuwe versie
VERSION_FILE="/var/log/install-version"
LOGFILE="/var/log/install-script.log"
SCRIPT_PATH=$(realpath "$0")

echo "=== Installatiescript versie $VERSION gestart ===" | tee -a "$LOGFILE"

# --- 1. Versiecheck ---
if [[ -f "$VERSION_FILE" ]] && grep -q "$VERSION" "$VERSION_FILE"; then
    echo "Script al geïnstalleerd (versie $VERSION). Stop." | tee -a "$LOGFILE"
    exit 0
fi

# --- 2. Tijdzone ---
CURRENT_TZ=$(timedatectl show -p Timezone --value)
if [[ "$CURRENT_TZ" != "Europe/Brussels" ]]; then
    echo "Stel tijdzone in op Europe/Brussels..." | tee -a "$LOGFILE"
    sudo timedatectl set-timezone Europe/Brussels
fi

# --- 3. Updates & pakketten ---
echo "Update en upgrade..." | tee -a "$LOGFILE"
sudo apt update && sudo apt upgrade -y
sudo apt install -y openssh-server cockpit bpytop unattended-upgrades neofetch figlet wget curl parted e2fsprogs git
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades

# --- 4. Nx Witness ---
NX_DEB="nxwitness-server-6.0.6.41837-linux_arm32.deb"
if [[ ! -f "$NX_DEB" ]]; then
    wget -q https://updates.networkoptix.com/default/41837/arm/$NX_DEB
fi
if ! dpkg -l | grep -q "networkoptix"; then
    sudo DEBIAN_FRONTEND=noninteractive dpkg -i "$NX_DEB" || \
    sudo apt-get install -f -y
fi

# --- 5. Welkomstbanner ---
MOTD_FILE="/etc/motd"
{
  figlet "Welkom Stijn Pans BV"
  echo "OS: $(lsb_release -d | cut -f2)"
  echo "Kernel: $(uname -r)"
  echo "Host: $(hostname)"
} | sudo tee "$MOTD_FILE" > /dev/null

grep -q "neofetch" ~/.bashrc || echo "neofetch" >> ~/.bashrc

# --- 6. Disk Watchdog ---
DISK_SCRIPT="/usr/local/bin/disk-watchdog.sh"
mkdir -p /usr/local/bin /var/log /mnt/media
cat << 'EOF' > "$DISK_SCRIPT"
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
    [[ "$D" != "$OS_DISK" ]] && DISKS+=("$D")
done

IFS=$'\n' DISKS=($(sort <<<"${DISKS[*]}"))
unset IFS

INDEX=1
SUCCESS=0
for DISK in "${DISKS[@]}"; do
    PART="${DISK}1"
    LABEL="MEDIA_${INDEX}"
    MOUNTPOINT="$BASE/$LABEL"

    if [[ ! -e "$PART" ]]; then
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

if [[ $SUCCESS -eq 0 ]]; then
    NOW=$(date +%s)
    if [[ ! -f "$LAST_REBOOT_FILE" ]] || [[ $((NOW - $(cat $LAST_REBOOT_FILE))) -ge 3600 ]]; then
        echo "$NOW" > "$LAST_REBOOT_FILE"
        sudo reboot
    fi
fi
EOF
chmod +x "$DISK_SCRIPT"

# --- 7. NX Watchdog ---
NX_SCRIPT="/usr/local/bin/nx-watchdog.sh"
cat << 'EOF' > "$NX_SCRIPT"
#!/bin/bash
LOGFILE="/var/log/nx-watchdog.log"
echo "$(date): NX Watchdog gestart" >> "$LOGFILE"
if ! systemctl is-active --quiet networkoptix-mediaserver.service; then
    systemctl restart networkoptix-mediaserver.service
fi
EOF
chmod +x "$NX_SCRIPT"

# --- 8. Systemd services ---
for svc in disk-watchdog nx-watchdog; do
    SERVICE_FILE="/etc/systemd/system/$svc.service"
    TIMER_FILE="/etc/systemd/system/$svc.timer"

    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=$svc Service
[Service]
ExecStart=/usr/local/bin/$svc.sh
Type=oneshot
EOF

    cat << EOF > "$TIMER_FILE"
[Unit]
Description=Run $svc every 30 seconds
[Timer]
OnBootSec=15
OnUnitActiveSec=30
[Install]
WantedBy=timers.target
EOF
done

systemctl daemon-reload
systemctl enable disk-watchdog.timer nx-watchdog.timer

# --- 9. Auto-update ---
UPDATE_SCRIPT="/opt/update.sh"
cat << 'EOF' > "$UPDATE_SCRIPT"
#!/bin/bash
LOGFILE="/var/log/update.log"
REPO_DIR="/opt/Raspberry-32bit-nx-server-bookworm"

echo "$(date): Update-check gestart" >> "$LOGFILE"

if [[ ! -d "$REPO_DIR" ]]; then
    git clone https://github.com/StijnPansBV/Raspberry-32bit-nx-server-bookworm.git "$REPO_DIR"
fi

cd "$REPO_DIR"
git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

echo "$(date): Lokale commit: $LOCAL, Remote commit: $REMOTE" >> "$LOGFILE"

if [[ "$LOCAL" != "$REMOTE" ]]; then
    echo "$(date): Nieuwe versie gevonden, update uitvoeren..." >> "$LOGFILE"
    git pull
    chmod +x setup.sh
    sudo ./setup.sh
    echo "$(date): Update voltooid" >> "$LOGFILE"
else
    echo "$(date): Geen update nodig" >> "$LOGFILE"
fi
EOF
chmod +x "$UPDATE_SCRIPT"

# --- 10. Systemd voor update ---
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
OnUnitActiveSec=3600
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable github-update.timer || true

# --- 11. Versie opslaan en cleanup ---
echo "$VERSION" > "$VERSION_FILE"
rm -f "$SCRIPT_PATH"

echo "Installatie voltooid. Systeem wordt herstart..." | tee -a "$LOGFILE"
sudo reboot

