#!/bin/bash
LOGFILE="/var/log/update.log"
REPO_DIR="/opt/Raspberry-32bit-nx-server-bookworm"

echo "$(date): Update-check gestart" >> "$LOGFILE"

# Als de repo nog niet bestaat → clone
if [ ! -d "$REPO_DIR" ]; then
    git clone https://github.com/StijnPansBV/Raspberry-32bit-nx-server-bookworm.git "$REPO_DIR"
fi

cd "$REPO_DIR"

# Haal laatste commit info op (zonder volledige download)
git fetch origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

echo "$(date): Lokale commit: $LOCAL, Remote commit: $REMOTE" >> "$LOGFILE"

# Als er een verschil is → update uitvoeren
if [ "$LOCAL" != "$REMOTE" ]; then
    echo "$(date): Nieuwe versie gevonden, update uitvoeren..." >> "$LOGFILE"
    git pull
    chmod +x setup.sh
    sudo ./setup.sh
    echo "$(date): Update voltooid" >> "$LOGFILE"
else
    echo "$(date): Geen update nodig" >> "$LOGFILE"
fi
