#!/bin/bash
set -e  # stop bij fouten

echo "Update en upgrade..."
sudo apt update && sudo apt upgrade -y

echo "Installeer SSH..."
sudo apt install openssh-server -y

echo "Installeer Cockpit..."
sudo apt install cockpit -y

echo "Installeer bpytop..."
sudo apt install bpytop -y

echo "Installeer unattended-upgrades..."
sudo apt install unattended-upgrades -y

echo "Configureer unattended-upgrades..."
sudo dpkg-reconfigure unattended-upgrades

echo "Download Nx Witness server package..."
wget https://updates.networkoptix.com/default/41837/arm/nxwitness-server-6.0.6.41837-linux_arm32.deb

echo "Installeer Nx Witness server..."
sudo dpkg -i nxwitness-server-6.0.6.41837-linux_arm32.deb
sudo apt install -f -y

echo "Installeer Neofetch..."
sudo apt install neofetch -y

echo "Installeer figlet..."
sudo apt install figlet -y

echo "Stel grote welkomstbanner met systeeminfo in..."
{
  figlet "Welkom Stijn Pans BV"
  echo "OS: $(lsb_release -d | cut -f2)"
  echo "Kernel: $(uname -r)"
  echo "Host: $(hostname)"
} | sudo tee /etc/motd

# Optioneel: Neofetch automatisch bij login
echo "neofetch" >> ~/.bashrc

echo "Klaar! Met veel dank aan Vanherwegen Brent die alles voor je gedaan heeft! :) 🎉"
