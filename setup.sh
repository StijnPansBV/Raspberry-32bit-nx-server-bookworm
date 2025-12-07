
#!/bin/bash
set -e

############################################################
# 0. BASISINSTALLATIE
############################################################
echo "Update en upgrade..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y openssh-server cockpit bpytop unattended-upgrades neofetch figlet wget curl parted e2fsprogs

echo "Configureer unattended-upgrades..."
sudo dpkg-reconfigure unattended-upgrades

echo "Download en installeer Nx Witness (vaste versie zoals vroeger)..."
wget https://updates.networkoptix.com/default/41837/arm/nxwitness-server-6.0.6.41837-linux_arm32.deb
sudo dpkg -i nxwitness-server-6.0.6.41837-linux_arm32.deb || sudo apt install -f -y

echo "Welkomstbanner instellen..."
{
  figlet "Welkom Stijn Pans BV"
  echo "OS: $(lsb_release -d | cut -f2)"
  echo "Kernel: $(uname -r)"
  echo "Host: $(hostname)"
} | sudo tee /etc/motd
echo "neofetch" >> ~/.bashrc

############################################################
# 1. DISK WATCHDOG MET UUID + LABEL + MOUNT FIX + REBOOT
############################################################
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

# Oude fstab regels verwijderen
sed -i '/\/mnt\/media\//d' /etc/fstab

INDEX=1
SUCCESS=0
for DISK in "${DISKS[@]}"; do
    PART="${DISK}1"
    LABEL="MEDIA_${INDEX}"
    MOUNTPOINT="$BASE/$LABEL"

    # Partitie aanmaken indien nodig
    if [ ! -e "$PART" ]; then
        echo "$(date): $DISK geen partitie → aanmaken" >> "$LOGFILE"
        parted "$DISK" --script mklabel gpt
        parted "$DISK" --script mkpart primary 0% 100%
        sleep 3
        mkfs.ext4 -F "$PART"
        sleep 2
    fi

    # Label instellen
    e2label "$PART" "$LABEL"

    # UUID ophalen
    UUID=$(blkid -s UUID -o value "$PART")

    mkdir -p "$MOUNTPOINT"

    # fstab regel toevoegen met auto mount bij boot
    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID $MOUNTPOINT ext4 defaults,nofail,auto 0 0" >> /etc/fstab
        echo "$(date): fstab toegevoegd: $LABEL ($UUID)" >> "$LOGFILE"
        mount -a
    fi

    # Mounten (herstel als unmount)
    if ! mountpoint -q "$MOUNTPOINT"; then
        if mount "$MOUNTPOINT"; then
            SUCCESS=$((SUCCESS+1))
        else
            echo "$(date): MOUNT FAALDE voor $LABEL" >> "$LOGFILE"
        fi
    else
        SUCCESS=$((SUCCESS+1))
    fi

    INDEX=$((INDEX+1))
done

# Als geen enkele schijf gemount is → reboot max 1x per uur
if [ $SUCCESS -eq 0 ]; then
    NOW=$(date +%s)
    if [ ! -f "$LAST_REBOOT_FILE" ] || [ $((NOW - $(cat $LAST_REBOOT_FILE))) -ge 3600 ]; then
        echo "$(date): Geen enkele schijf gemount → herstarten" >> "$LOGFILE"
        echo "$NOW" > "$LAST_REBOOT_FILE"
        sudo reboot
    else
        echo "$(date): Geen schijven gemount, maar reboot al uitgevoerd in afgelopen uur" >> "$LOGFILE"
    fi
fi
EOF

chmod +x /usr/local/bin/disk-watchdog.sh

############################################################
# 2. NX WATCHDOG
############################################################
cat << 'EOF' > /usr/local/bin/nx-watchdog.sh
#!/bin/bash
LOGFILE="/var/log/nx-watchdog.log"
echo "$(date): NX Watchdog gestart" >> "$LOGFILE"
if ! systemctl is-active --quiet networkoptix-mediaserver.service; then
    echo "$(date): Nx Server draait niet → herstarten" >> "$LOGFILE"
    systemctl restart networkoptix-mediaserver.service
else
    echo "$(date): Nx Server OK" >> "$LOGFILE"
fi
EOF

chmod +x /usr/local/bin/nx-watchdog.sh

############################################################
# 3. SYSTEMD SERVICES + TIMERS
############################################################
# Disk watchdog
cat << 'EOF' > /etc/systemd/system/disk-watchdog.service
[Unit]
Description=Disk Watchdog Service
[Service]
ExecStart=/usr/local/bin/disk-watchdog.sh
Type=oneshot
EOF

cat << 'EOF' > /etc/systemd/system/disk-watchdog.timer
[Unit]
Description=Run Disk Watchdog every 30 seconds
[Timer]
OnBootSec=15
OnUnitActiveSec=30
[Install]
WantedBy=timers.target
EOF

# NX watchdog
cat << 'EOF' > /etc/systemd/system/nx-watchdog.service
[Unit]
Description=NX Server Watchdog
[Service]
ExecStart=/usr/local/bin/nx-watchdog.sh
Type=oneshot
EOF

cat << 'EOF' > /etc/systemd/system/nx-watchdog.timer
[Unit]
Description=Run NX Watchdog every 30 seconds
[Timer]
OnBootSec=20
OnUnitActiveSec=30
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now disk-watchdog.timer
systemctl enable --now nx-watchdog.timer

echo "=== Installatie voltooid ==="
echo "Nx Witness geïnstalleerd."
echo "Schijven stabiel gemount via UUID + LABEL, auto mount bij boot."
echo "Reboot als alle mounts falen (max 1x per uur)."
echo "Klaar! Met veel dank aan Vanherwegen Brent die zonet alles geprogrammeerd heeft voor jou! :) 🎉"
