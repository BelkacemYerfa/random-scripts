#!/usr/bin/env bash
# Projet STANLEY - Groupe 5
# 99 - Script de demonstration / verification pour la soutenance du 21 juillet.
#      Parcourt les criteres de reussite du document et affiche le resultat.
# Usage : bash 99-demo-21-juillet.sh   (sur ipa1, apres kinit admin)

set -uo pipefail   # pas de -e : on veut voir TOUS les tests, meme en echec

OK=0
KO=0

titre() { printf "\n\033[1m--- %s\033[0m\n" "$1"; }
test_ok()  { printf "  \033[32m[OK]\033[0m  %s\n" "$1"; OK=$((OK+1)); }
test_ko()  { printf "  \033[31m[KO]\033[0m  %s\n" "$1"; KO=$((KO+1)); }

verifier() {
    local libelle="$1"; shift
    if "$@" >/dev/null 2>&1; then test_ok "$libelle"; else test_ko "$libelle"; fi
}

echo "===================================================="
echo " STANLEY - Groupe 5 - Verification du 21 juillet"
echo " $(date '+%d/%m/%Y %H:%M')"
echo "===================================================="

titre "1. Services de l'annuaire"
verifier "Service IPA actif"          systemctl is-active ipa
verifier "Annuaire LDAP (389-DS)"     systemctl is-active dirsrv.target
verifier "KDC Kerberos"               systemctl is-active krb5kdc
verifier "DNS interne"                systemctl is-active named
verifier "Interface web (httpd)"      systemctl is-active httpd

titre "2. Kerberos"
if klist -s 2>/dev/null; then
    test_ok "Ticket Kerberos valide"
    klist | sed 's/^/      /'
else
    test_ko "Aucun ticket Kerberos - lancer : kinit admin"
    echo "  Les tests suivants vont echouer."
fi

titre "3. Annuaire de test fonctionnel"
verifier "Requete utilisateur (admin)"  ipa user-find admin
NB_USERS=$(ipa user-find --sizelimit=0 2>/dev/null | grep -c "User login:" || echo 0)
echo "      Utilisateurs dans l'annuaire : $NB_USERS"

titre "4. Groupes et roles definis"
for g in stanley-admins g1-infra-physique g3-reseau g5-infra-logicielle \
         formateurs apprenants observateurs; do
    verifier "Groupe $g" ipa group-show "$g"
done

titre "5. Regles d'acces (HBAC)"
if ipa hbacrule-show allow_all 2>/dev/null | grep -q "Enabled: FALSE"; then
    test_ok "allow_all desactivee (acces non permissif par defaut)"
else
    test_ko "allow_all encore active - acces trop permissif"
fi
verifier "Regle admins-partout"  ipa hbacrule-show admins-partout
verifier "Regle g5-ssh"          ipa hbacrule-show g5-ssh

titre "6. Politique de mot de passe"
if ipa pwpolicy-show 2>/dev/null | grep -q "Min length: 12"; then
    test_ok "Longueur minimale de 12 caracteres"
else
    test_ko "Politique de mot de passe non conforme"
fi

titre "7. Regles sudo centralisees"
verifier "Regle admins-sudo-all"     ipa sudorule-show admins-sudo-all
verifier "Regle g5-sudo-services"    ipa sudorule-show g5-sudo-services

titre "8. Durcissement SSH"
if grep -qE "^PermitRootLogin[[:space:]]+no" /etc/ssh/sshd_config 2>/dev/null; then
    test_ok "Connexion root directe interdite"
else
    test_ko "PermitRootLogin non positionne a 'no'"
fi
if grep -q "sss_ssh_authorizedkeys" /etc/ssh/sshd_config 2>/dev/null; then
    test_ok "Cles SSH lues depuis l'annuaire (revocation centralisee)"
else
    test_ko "Cles SSH encore locales - revocation non centralisee"
fi

titre "9. Replication"
if ipa-replica-manage list 2>/dev/null | grep -q .; then
    test_ok "Topologie de replication presente"
    ipa-replica-manage list 2>/dev/null | sed 's/^/      /'
else
    echo "      Aucun replica (optionnel - voir 04-replica.sh)"
fi

titre "10. Sauvegarde"
if ls /var/lib/ipa/backup/ >/dev/null 2>&1 && [ -n "$(ls -A /var/lib/ipa/backup/ 2>/dev/null)" ]; then
    test_ok "Au moins une sauvegarde presente"
    ls -1 /var/lib/ipa/backup/ | tail -3 | sed 's/^/      /'
else
    test_ko "Aucune sauvegarde - lancer : ipa-backup"
fi

echo
echo "===================================================="
printf " Resultat : \033[32m%d reussis\033[0m / \033[31m%d echoues\033[0m\n" "$OK" "$KO"
echo "===================================================="
echo
echo "Demonstration en direct a faire devant le jury :"
echo "  1. Creer un utilisateur      : ipa user-add demo --first=Demo --last=Jury"
echo "  2. L'ajouter a un groupe     : ipa group-add-member apprenants --users=demo"
echo "  3. Le resoudre depuis un client : id demo"
echo "  4. Le desactiver             : ipa user-disable demo"
echo "  5. Montrer que l'acces est immediatement refuse sur TOUTES les machines"
echo

[ "$KO" -eq 0 ]
