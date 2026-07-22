#!/usr/bin/env bash
# Projet STANLEY - Groupe 5
# 03 - Enrolement d'un client dans le domaine (Ubuntu LTS ou Rocky 9)
#      + durcissement SSH conforme au Bloc 3.
# Usage : sudo bash 03-client.sh

set -euo pipefail

DOMAINE="stanley.lan"
REALM="STANLEY.LAN"
IP_SERVEUR="192.168.56.10"
SERVEUR="ipa1.${DOMAINE}"

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit etre lance en root." >&2
    exit 1
fi

read -rsp "Mot de passe de l'utilisateur admin IPA : " ADMIN_PASS
echo

echo "=== [1/5] Pointage DNS vers le serveur IPA ==="
if [[ -f /etc/redhat-release ]]; then
    FAMILY="rhel"
    dnf -y install ipa-client openssh-clients
else
    FAMILY="debian"
    export DEBIAN_FRONTEND=noninteractive
    apt-get -y install freeipa-client oddjob-mkhomedir
fi

# Le client doit resoudre les enregistrements SRV du domaine.
IFACE="$(ip route show default | awk '/default/ {print $5; exit}')"
if command -v resolvectl >/dev/null 2>&1 && [[ -n "${IFACE:-}" ]]; then
    resolvectl dns "$IFACE" "$IP_SERVEUR"
    resolvectl domain "$IFACE" "$DOMAINE"
fi
grep -q "$SERVEUR" /etc/hosts || echo "$IP_SERVEUR  $SERVEUR  ipa1" >> /etc/hosts

echo "=== [2/5] Enrolement dans le domaine ==="
ipa-client-install \
    --unattended \
    --domain="$DOMAINE" \
    --realm="$REALM" \
    --server="$SERVEUR" \
    --principal=admin \
    --password="$ADMIN_PASS" \
    --mkhomedir \
    --enable-dns-updates \
    --no-ntp \
    --force-join

echo "=== [3/5] Creation automatique des repertoires personnels ==="
if [[ "$FAMILY" == "debian" ]]; then
    pam-auth-update --enable mkhomedir || true
else
    authselect enable-feature with-mkhomedir 2>/dev/null || true
    systemctl enable --now oddjobd 2>/dev/null || true
fi

echo "=== [4/5] Durcissement SSH (Bloc 3) ==="
SSHD=/etc/ssh/sshd_config
cp "$SSHD" "${SSHD}.bak.$(date +%F-%H%M%S)"

regle() {
    local cle="$1" val="$2"
    sed -i "/^#\?${cle}[[:space:]]/d" "$SSHD"
    echo "${cle} ${val}" >> "$SSHD"
}

regle PermitRootLogin        no      # interdiction du root direct
regle PubkeyAuthentication   yes
regle GSSAPIAuthentication   yes     # SSO Kerberos
regle GSSAPICleanupCredentials yes
regle ChallengeResponseAuthentication no
regle X11Forwarding          no
regle LogLevel               VERBOSE # journalisation des connexions -> Elastic
regle MaxAuthTries           4

# Cles publiques lues depuis l'annuaire, pas depuis ~/.ssh/authorized_keys.
# C'est ce qui rend la revocation instantanee et globale.
regle AuthorizedKeysCommand     /usr/bin/sss_ssh_authorizedkeys
regle AuthorizedKeysCommandUser nobody

# PasswordAuthentication : laisse a yes pour la phase de test.
# A basculer sur no une fois les cles SSH de chacun deposees dans l'annuaire.
regle PasswordAuthentication yes

sshd -t && systemctl restart sshd
echo "  Configuration SSH validee et appliquee."

echo "=== [5/5] Verification ==="
echo "$ADMIN_PASS" | kinit admin >/dev/null 2>&1 || true
id admin || echo "  (attention : resolution de 'admin' impossible)"
sss_cache -E 2>/dev/null || true
systemctl restart sssd

cat <<EOF

====================================================================
 Client enrole dans $REALM.

 Tests a effectuer :
   id m.alrayan            -> l'annuaire doit resoudre l'utilisateur
   su - m.alrayan          -> connexion, repertoire personnel cree
   kinit m.alrayan && klist -> ticket Kerberos obtenu
   ssh m.alrayan@autre-machine -> AUCUN mot de passe demande (SSO)

 Le dernier test est la demonstration attendue le 21 juillet.

 Si 'id' ne resout rien :
   sss_cache -E && systemctl restart sssd
 Si la connexion est refusee : verifier les regles HBAC sur ipa1,
 allow_all ayant ete desactivee par le script 02.
====================================================================
EOF
