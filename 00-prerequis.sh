#!/usr/bin/env bash
# Projet STANLEY - Groupe 5
# 00 - Prerequis communs a toutes les VM (serveurs IPA et clients)
# Usage : sudo bash 00-prerequis.sh <fqdn> <ip-statique>
# Exemple : sudo bash 00-prerequis.sh ipa1.stanley.lan 192.168.56.10

set -euo pipefail

FQDN="${1:?Usage: $0 <fqdn> <ip>}"
IP="${2:?Usage: $0 <fqdn> <ip>}"
SHORT="${FQDN%%.*}"
DOMAIN="${FQDN#*.}"

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit etre lance en root." >&2
    exit 1
fi

echo "=== [1/5] Nom d'hote : $FQDN ==="
hostnamectl set-hostname "$FQDN"

echo "=== [2/5] /etc/hosts ==="
# Indispensable tant que le DNS interne n'existe pas encore
sed -i "/[[:space:]]$SHORT\([[:space:]]\|$\)/d" /etc/hosts
sed -i "/^$IP[[:space:]]/d" /etc/hosts
echo "$IP  $FQDN  $SHORT" >> /etc/hosts

echo "=== [3/5] Detection de la famille de distribution ==="
if [[ -f /etc/redhat-release ]]; then
    FAMILY="rhel"
    PKG="dnf"
elif [[ -f /etc/debian_version ]]; then
    FAMILY="debian"
    PKG="apt-get"
    export DEBIAN_FRONTEND=noninteractive
else
    echo "Distribution non reconnue." >&2
    exit 1
fi
echo "Famille : $FAMILY"

echo "=== [4/5] Mise a jour et synchronisation horaire ==="
# Kerberos refuse toute authentification au-dela de 5 minutes de derive.
if [[ "$FAMILY" == "rhel" ]]; then
    $PKG -y update
    $PKG -y install chrony bind-utils vim curl
else
    $PKG -y update
    $PKG -y install chrony dnsutils vim curl
fi
systemctl enable --now chronyd 2>/dev/null || systemctl enable --now chrony
sleep 3
chronyc sources || true
timedatectl set-ntp true 2>/dev/null || true

echo "=== [5/5] Desactivation SELinux permissive (lab uniquement) ==="
# En production, ecrire les regles SELinux plutot que de le passer en permissif.
if [[ "$FAMILY" == "rhel" ]] && command -v setenforce >/dev/null 2>&1; then
    setenforce 0 || true
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true
fi

echo
echo "Prerequis termines."
echo "  FQDN     : $(hostname -f)"
echo "  Domaine  : $DOMAIN"
echo "  IP       : $IP"
echo
echo "Verifier que 'hostname -f' retourne bien un nom pleinement qualifie"
echo "avant de lancer 01-serveur-ipa.sh. Un redemarrage est conseille."
