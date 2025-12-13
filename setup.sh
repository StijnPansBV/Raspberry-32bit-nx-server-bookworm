
#!/usr/bin/env bash
set -euo pipefail

# ===========================
# Raspberry Pi NX Server Installatiescript
# Versie: 2.0.0
# ===========================
SCRIPT_VERSION="2.0.0"
SELF_URL="https://raw.githubusercontent.com/StijnPansBV/Raspberry-32bit-nx-server-bookworm/main/setup.sh"
NX_DEB="nxwitness-server-6.1.0.42176-linux_arm32.deb"
NX_URL="https://updates.networkoptix.com/default/42176/arm/$NX_DEB"
LOGFILE="/var/log/nx-install.log"
LOCKFILE="/var/lock/install-script.lock"

touch "$LOGFILE"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Script draait al." >> "$LOGFILE"; exit 0; }

trap 'echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Installatiescript faalde." >> "$LOGFILE"' ERR

# Self-update
REMOTE_VERSION=$(curl -s "$SELF_URL" | grep 'SCRIPT_VERSION=' | cut -d'"' -f2 || echo "$SCRIPT_VERSION")
if [ "$REMOTE_VERSION" != "$SCRIPT_VERSION" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Nieuwe versie gevonden ($REMOTE_VERSION). Download en voer uit..." >> "$LOGFILE"
    curl -s -o /tmp/setup.sh "$SELF_URL"
    chmod +x /tmp/setup.sh
    exec /tmp/setup.sh --updated
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Start installatie v$SCRIPT_VERSION" >> "$LOGFILE"

############################################################
# 0. BASISINSTALLATIE
############################################################
sudo apt update && sudo apt upgrade -y
PACKAGES=(openssh-server cockpit bpytop unattended-upgrades neofetch figlet wget curl parted e2fsprogs git)
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        sudo DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"
    fi
done
sudo dpkg-reconfigure -f noninteractive unattended-upgrades

############################################################
# 1. NX WITNESS INSTALLATIE
############################################################
if ! dpkg -s networkoptix-mediaserver &>/dev/null; then
    if [ ! -f "$NX_DEB" ]; then
        wget "$NX_URL"
    fi
    sudo DEBIAN_FRONTEND=noninteractive dpkg -i "$NX_DEB" || sudo apt install -f -y
fi

############################################################
# 2. WELKOMSTBANNER
############################################################
MOTD_FILE="/etc/motd"
if ! grep -q "Welkom Stijn Pans BV" "$MOTD_FILE" 2>/dev/null; then
    {
      figlet "Welkom Stijn Pans BV"
      echo "OS: $(lsb_release -d | cut -f2)"
      echo "Kernel: $(uname -r)"
      echo "Host: $(hostname)"
    } | sudo tee "$MOTD_FILE"
fi
grep -qxF "neofetch" ~/.bashrc || echo "neofetch" >> ~/.bashrc

############################################################
# 3. DISK WATCHDOG
############################################################
DISK_SCRIPT="/usr/local/bin/disk-watchdog.sh"
if [ ! -f "$DISK_SCRIPT" ]; then
cat << 'EOF' | sudo tee "$DISK_SCRIPT"
#!/usr/bin/env bash
set -euo pipefail
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

sed -i '/\/mnt\/media\//d' /etc/fstab

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

    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID $MOUNTPOINT ext4 defaults,nofail,auto 0 0" >> /etc/fstab
        mount -a
    fi

    if ! mountpoint -q "$MOUNTPOINT"; then
        mount "$MOUNTPOINT" && SUCCESS=$((SUCCESS+1))
    else
        SUCCESS=$((SUCCESS+1))
    fi

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
sudo chmod +x "$DISK_SCRIPT"
fi

############################################################
# 4. NX WATCHDOG
############################################################
NX_SCRIPT="/usr/local/bin/nx-watchdog.sh"
if [ ! -f "$NX_SCRIPT" ]; then
cat << 'EOF' | sudo tee "$NX_SCRIPT"
#!/usr/bin/env bash
set -euo pipefail
LOGFILE="/var/log/nx-watchdog.log"
echo "$(date): NX Watchdog gestart" >> "$LOGFILE"
if ! systemctl is-active --quiet networkoptix-mediaserver.service; then
    systemctl restart --no-block networkoptix-mediaserver.service
fi
EOF
sudo chmod +x "$NX_SCRIPT"
fi

############################################################
# 5. SYSTEMD TIMERS
############################################################
create_service() {
    local name="$1"
    local exec="$2"
    local timer="$3"
    local bootsec="$4"
    if [ ! -f "/etc/systemd/system/$name.service" ]; then
        cat <<EOF | sudo tee "/etc/systemd/system/$name.service"
[Unit]
Description=$name Service
[Service]
ExecStart=$exec
Type=oneshot
EOF
    fi
    if [ ! -f "/etc/systemd/system/$name.timer" ]; then
        cat <<EOF | sudo tee "/etc/systemd/system/$name.timer"
[Unit]
Description=Run $name every $timer
[Timer]
OnBootSec=$bootsec
OnUnitActiveSec=$timer
Persistent=true
[Install]
WantedBy=timers.target
EOF
    fi
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$name.timer"
}

create_service "disk-watchdog" "$DISK_SCRIPT" "60" "15"
create_service "nx-watchdog" "$NX_SCRIPT" "60" "20"

############################################################
# 6. AUTO-UPDATE TIMER
############################################################
UPDATE_SCRIPT="/usr/local/bin/update.sh"
cat << 'EOF' | sudo tee "$UPDATE_SCRIPT"
#!/usr/bin/env bash
set -euo pipefail
SELF_URL="https://raw.githubusercontent.com/StijnPansBV/Raspberry-32bit-nx-server-bookworm/main/setup.sh"
LOCAL_SCRIPT="/usr/local/bin/setup.sh"
LOGFILE="/var/log/nx-update.log"
LOCKFILE="/var/lock/nx-update.lock"
touch "$LOGFILE"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Update-script draait al." >> "$LOGFILE"; exit 0; }
trap 'echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Update-script faalde." >> "$LOGFILE"' ERR
REMOTE_VERSION=$(curl -s "$SELF_URL" | grep 'SCRIPT_VERSION=' | cut -d'"' -f2 || echo "unknown")
LOCAL_VERSION=$(grep 'SCRIPT_VERSION=' "$LOCAL_SCRIPT" | cut -d'"' -f2 || echo "unknown")
echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Lokale versie: $LOCAL_VERSION | Remote versie: $REMOTE_VERSION" >> "$LOGFILE"
if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    cp "$LOCAL_SCRIPT" "${LOCAL_SCRIPT}.bak"
    curl -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"
    exec "$LOCAL_SCRIPT" --updated
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Geen update beschikbaar." >> "$LOGFILE"
fi
EOF
sudo chmod +x "$UPDATE_SCRIPT"

cat <<EOF | sudo tee /etc/systemd/system/nx-auto-update.service
[Unit]
Description=NX Server Auto Update Service
[Service]
ExecStart=$UPDATE_SCRIPT
Type=oneshot
EOF

cat <<EOF | sudo tee /etc/systemd/system/nx-auto-update.timer
[Unit]
Description=Run NX Server Auto Update every 15 minutes
[Timer]
OnBootSec=30
OnUnitActiveSec=15min
Persistent=true
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now nx-auto-update.timer

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Installatie voltooid (v$SCRIPT_VERSION)" >> "$LOGFILE"
sudo reboot
