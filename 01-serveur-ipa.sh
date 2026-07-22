#!/usr/bin/env bash
# Projet STANLEY - Groupe 5
# 01 - Installation du serveur FreeIPA maitre (Rocky Linux 9 / AlmaLinux 9)
# Usage : sudo bash 01-serveur-ipa.sh
# Duree : 10 a 20 minutes

set -euo pipefail

# --------------------------------------------------------------------
# Parametres du domaine STANLEY - a adapter si le Groupe 3 impose autre chose
# --------------------------------------------------------------------
DOMAINE="stanley.lan"
REALM="STANLEY.LAN"
IP_SERVEUR="192.168.56.10"
FORWARDER="1.1.1.1"          # DNS amont ; remplacer par le resolveur de l'ecole

# Mots de passe : generes aleatoirement puis affiches une seule fois.
DM_PASS="$(openssl rand -base64 18)"
ADMIN_PASS="$(openssl rand -base64 18)"

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit etre lance en root." >&2
    exit 1
fi

if [[ ! -f /etc/redhat-release ]]; then
    cat >&2 <<'EOF'
ERREUR : le role serveur FreeIPA n'est supporte que sur RHEL / Rocky / AlmaLinux.
Les paquets freeipa-server d'Ubuntu sont incomplets.
Les CLIENTS Ubuntu, eux, fonctionnent parfaitement (voir 03-client.sh).
EOF
    exit 1
fi

if [[ "$(hostname -f)" != *.* ]]; then
    echo "ERREUR : le nom d'hote n'est pas pleinement qualifie. Lancer 00-prerequis.sh." >&2
    exit 1
fi

echo "=== [1/4] Installation des paquets ==="
dnf -y module enable idm:DL1 2>/dev/null || true
dnf -y install ipa-server ipa-server-dns

echo "=== [2/4] Ouverture des flux pare-feu ==="
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service={freeipa-ldap,freeipa-ldaps,dns,ntp}
    firewall-cmd --reload
fi

echo "=== [3/4] Installation de FreeIPA (non interactif) ==="
ipa-server-install \
    --unattended \
    --realm="$REALM" \
    --domain="$DOMAINE" \
    --ds-password="$DM_PASS" \
    --admin-password="$ADMIN_PASS" \
    --hostname="$(hostname -f)" \
    --ip-address="$IP_SERVEUR" \
    --setup-dns \
    --forwarder="$FORWARDER" \
    --auto-reverse \
    --no-ntp

echo "=== [4/4] Verification ==="
echo "$ADMIN_PASS" | kinit admin
klist
ipa user-find admin

cat <<EOF

====================================================================
 FreeIPA installe.

   Web UI            : https://$(hostname -f)
   Utilisateur       : admin
   Mot de passe admin: $ADMIN_PASS
   Directory Manager : $DM_PASS

 CES DEUX SECRETS NE DOIVENT PAS RESTER DANS UN FICHIER SUR CETTE VM.
 Les placer dans le coffre du projet (livrable "procedure de gestion
 du mot de passe", Bloc 1) puis effacer l'historique du shell :
   history -c && rm -f ~/.bash_history

 Etape suivante : sudo bash 02-structure-stanley.sh
====================================================================
EOF
