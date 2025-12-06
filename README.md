
# Automatische Installatie & Watchdog Services

Auteur: **Stijn Pans BV**  
Versie: **1.0**  
Datum: **2025-12-06**

---

## Beschrijving
Dit script automatiseert de installatie en configuratie van een Linux-systeem voor gebruik met **Nx Witness** en voegt twee belangrijke watchdog-mechanismen toe:

1. **Disk Watchdog**  
   - Controleert extra schijven, maakt partities en labels aan indien nodig.
   - Mount schijven automatisch via **UUID** en **LABEL**.
   - Voert een reboot uit als geen enkele schijf gemount is (max. 1x per uur).

2. **NX Watchdog**  
   - Controleert of de **Nx Witness mediaserver** draait.
   - Herstart de service indien deze niet actief is.

Daarnaast configureert het script:
- **Basisinstallatie** van essentiële pakketten.
- **Unattended upgrades** voor automatische updates.
- **Welkomstbanner** met systeeminformatie.
- **Systemd timers** voor periodieke uitvoering van watchdog scripts.

---

## Installatie
1. Zorg dat je rootrechten hebt.
2. Download het script en voer het uit:
   ```bash
   chmod +x install.sh
   ./install.sh


Dit toestel en software wordt beheerd door de firma Stijn Pans BV.
Voor ondersteuning kan je ons bereiken via:
• 	📧 support@stijn-pans.be
• 	☎️ 016 77 08 0
