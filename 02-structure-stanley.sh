#!/usr/bin/env bash
# Projet STANLEY - Groupe 5
# 02 - Creation de la structure STANLEY : groupes, utilisateurs de test,
#      politique de mot de passe, regles HBAC et sudo.
# Usage : sudo bash 02-structure-stanley.sh   (sur ipa1, apres 01)

set -euo pipefail

if ! klist -s 2>/dev/null; then
    echo "Aucun ticket Kerberos valide. Lancer d'abord : kinit admin" >&2
    exit 1
fi

echo "=== [1/6] Creation des groupes STANLEY ==="
# Reprise exacte des groupes fonctionnels du document de projet (Bloc 2).
creer_groupe() {
    local nom="$1" desc="$2"
    if ipa group-show "$nom" >/dev/null 2>&1; then
        echo "  - $nom (existe deja)"
    else
        ipa group-add "$nom" --desc="$desc" >/dev/null
        echo "  + $nom"
    fi
}

creer_groupe stanley-admins       "Admin STANLEY - administration globale"
creer_groupe g1-infra-physique    "Groupe 1 - Infrastructure physique"
creer_groupe g2-audiovisuel       "Groupe 2 - Audiovisuel / ecrans"
creer_groupe g3-reseau            "Groupe 3 - Reseau / securite"
creer_groupe g4-gns3              "Groupe 4 - GNS3 / emulation"
creer_groupe g5-infra-logicielle  "Groupe 5 - Infrastructure logicielle"
creer_groupe g6-ia-securite       "Groupe 6 - IA / securite"
creer_groupe g7-scenarios         "Groupe 7 - Scenarios"
creer_groupe g8-interfaces        "Groupe 8 - Interfaces"
creer_groupe g9-integration       "Groupe 9 - Integration physique"
creer_groupe formateurs           "Formateurs"
creer_groupe apprenants           "Apprenants"
creer_groupe observateurs         "Observateurs - lecture seule"

echo "=== [2/6] Politique de mot de passe ==="
ipa pwpolicy-mod --minlength=12 --minclasses=3 --history=5 \
                 --maxlife=180 --maxfail=5 --lockouttime=600 \
    || echo "  (politique deja conforme)"

echo "=== [3/6] Utilisateurs de test (membres du Groupe 5) ==="
# Convention : p.nom  -  compte d'administration : adm-p.nom
creer_user() {
    local uid="$1" prenom="$2" nom="$3" groupe="$4"
    if ipa user-show "$uid" >/dev/null 2>&1; then
        echo "  - $uid (existe deja)"
    else
        ipa user-add "$uid" --first="$prenom" --last="$nom" \
            --email="$uid@stanley.lan" --shell=/bin/bash >/dev/null
        echo "  + $uid"
    fi
    ipa group-add-member "$groupe" --users="$uid" >/dev/null 2>&1 || true
}

creer_user m.alrayan   Mohamed     AlRayan     g5-infra-logicielle
creer_user p.patrick   Patrick     Patrick     g5-infra-logicielle
creer_user c.christo   Christopher Christopher g5-infra-logicielle
creer_user a.abdelaziz Abdelaziz   Abdelaziz   g5-infra-logicielle
creer_user m.massinissa Massinissa Massinissa  g5-infra-logicielle

# Comptes d'administration separes (Bloc 3 : separation admin / utilisateur)
creer_user adm-m.alrayan Admin Alrayan stanley-admins
creer_user t.formateur   Test  Formateur formateurs
creer_user t.apprenant   Test  Apprenant apprenants

echo "=== [4/6] Regles HBAC (qui accede a quoi, depuis ou) ==="
# HBAC = l'equivalent FreeIPA des GPO de restriction d'ouverture de session.
# La regle par defaut allow_all est trop permissive : on la desactive.
ipa hbacrule-disable allow_all >/dev/null 2>&1 || true

creer_hbac() {
    local nom="$1" desc="$2" groupe="$3"
    if ipa hbacrule-show "$nom" >/dev/null 2>&1; then
        echo "  - $nom (existe deja)"
    else
        ipa hbacrule-add "$nom" --desc="$desc" >/dev/null
        ipa hbacrule-add-user "$nom" --groups="$groupe" >/dev/null
        ipa hbacrule-add-service "$nom" --hbacsvcs=sshd >/dev/null
        echo "  + $nom"
    fi
}

# Les admins accedent a toutes les machines, tous services
if ! ipa hbacrule-show admins-partout >/dev/null 2>&1; then
    ipa hbacrule-add admins-partout \
        --desc="Administrateurs STANLEY - acces total" \
        --hostcat=all --servicecat=all >/dev/null
    ipa hbacrule-add-user admins-partout --groups=stanley-admins >/dev/null
    echo "  + admins-partout"
fi

creer_hbac g5-ssh        "Groupe 5 - SSH sur les serveurs d'infrastructure" g5-infra-logicielle
creer_hbac formateurs-ssh "Formateurs - SSH sur les postes de lab"          formateurs

# Note : rattacher ensuite les machines concernees, par exemple
#   ipa hbacrule-add-host g5-ssh --hosts=cli-rk.stanley.lan
# Les apprenants n'ont volontairement AUCUNE regle SSH par defaut.

echo "=== [5/6] Regles sudo centralisees ==="
if ! ipa sudorule-show admins-sudo-all >/dev/null 2>&1; then
    ipa sudorule-add admins-sudo-all \
        --desc="Administrateurs STANLEY - sudo complet" \
        --hostcat=all --cmdcat=all --runasusercat=all >/dev/null
    ipa sudorule-add-user admins-sudo-all --groups=stanley-admins >/dev/null
    echo "  + admins-sudo-all"
fi

# Sudo limite pour le Groupe 5 : redemarrage de services, pas de shell root
if ! ipa sudocmd-show "/bin/systemctl restart" >/dev/null 2>&1; then
    ipa sudocmd-add "/bin/systemctl restart" \
        --desc="Redemarrage de service" >/dev/null 2>&1 || true
fi
if ! ipa sudorule-show g5-sudo-services >/dev/null 2>&1; then
    ipa sudorule-add g5-sudo-services \
        --desc="Groupe 5 - redemarrage de services uniquement" \
        --hostcat=all >/dev/null
    ipa sudorule-add-user g5-sudo-services --groups=g5-infra-logicielle >/dev/null
    ipa sudorule-add-allow-command g5-sudo-services \
        --sudocmds="/bin/systemctl restart" >/dev/null 2>&1 || true
    echo "  + g5-sudo-services"
fi

echo "=== [6/6] Recapitulatif ==="
echo
echo "Groupes :"
ipa group-find --sizelimit=0 | grep "Group name:" || true
echo
echo "Regles HBAC :"
ipa hbacrule-find --sizelimit=0 | grep "Rule name:" || true

cat <<'EOF'

====================================================================
 Structure STANLEY en place.

 A faire ensuite :
   1. Definir les mots de passe temporaires :
        ipa passwd m.alrayan
   2. Rattacher les machines aux regles HBAC :
        ipa hbacrule-add-host g5-ssh --hosts=cli-rk.stanley.lan
   3. Enroler les clients : sudo bash 03-client.sh

 ATTENTION : allow_all a ete desactivee. Tant qu'aucune regle HBAC
 ne couvre une machine, personne sauf stanley-admins ne pourra s'y
 connecter. C'est voulu, mais garder une session root ouverte sur
 ipa1 pendant les tests.
====================================================================
EOF
