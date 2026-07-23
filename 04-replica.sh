#!/usr/bin/env bash
# Projet STANLEY - Groupe 5
# 04 - Promotion d'un client en replica FreeIPA (haute disponibilite)
# Prerequis : la machine doit deja etre enrolee via 03-client.sh
# Usage : sudo bash 04-replica.sh   (sur ipa2)

set -euo pipefail

ADMIN_PASS="08o7Y3/w87ah/mZZukdw8w3N"

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit etre lance en root." >&2
    exit 1
fi

if [[ ! -f /etc/ipa/default.conf ]]; then
    echo "ERREUR : machine non enrolee. Lancer d'abord 03-client.sh." >&2
    exit 1
fi

echo "=== [1/4] Paquets serveur ==="
dnf -y module enable idm:DL1 2>/dev/null || true
dnf -y install ipa-server ipa-server-dns

echo "=== [2/4] Ticket Kerberos ==="
echo "$ADMIN_PASS" | kinit admin

echo "=== [3/4] Promotion en replica ==="
# --setup-ca  : ce replica devient aussi autorite de certification
# --setup-dns : et serveur DNS, pour survivre a la perte de ipa1
ipa-replica-install \
    --unattended \
    --principal=admin \
    --admin-password="$ADMIN_PASS" \
    --setup-ca \
    --setup-dns \
    --forwarder=1.1.1.1 \
    --no-ntp

echo "=== [4/4] Verification de la topologie de replication ==="
ipa topologysegment-find domain
ipa-replica-manage list -v "$(hostname -f)" || true

cat <<'EOF'

====================================================================
 Replica operationnel.

 Test de bascule a demontrer le 21 juillet :
   1. Arreter ipa1 :            systemctl stop ipa
   2. Depuis un client :        id m.alrayan
      -> la resolution doit continuer de fonctionner via ipa2
   3. Redemarrer ipa1 :         systemctl start ipa
   4. Verifier la resynchro :   ipa-replica-manage list -v

 C'est un argument fort pour la soutenance : l'annuaire ne constitue
 pas un point de defaillance unique.
====================================================================
EOF
