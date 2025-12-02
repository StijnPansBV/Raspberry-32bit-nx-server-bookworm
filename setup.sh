#!/bin/bash
set -e  # stop bij fouten

echo "Update en upgrade..."
sudo apt update && sudo apt upgrade -y

echo "Installeer pakketten..."
sudo apt install -y bpytop neofetch cockpit unattended-upgrades

echo "Configureer automatische updates..."
sudo dpkg-reconfigure --priority=low unattended-upgrades

echo "Download en installeer Nx Witness..."
wget https://updates.networkoptix.com/default/41837/arm/nxwitness-server-6.0.6.41837-linux_arm32.deb
sudo apt install -f ./nxwitness-server-6.0.6.41837-linux_arm32.deb

echo "Klaar! Met veel dank aan Vanherwegen Brent die alles voor je gedaan heeft! :) 🎉"
