#!/usr/bin/env bash
# Projet STANLEY - Groupe 5
# 05 - Keycloak en couche SSO (OIDC / SAML) federant l'annuaire FreeIPA
#      Cible : Grafana, Kibana, Jenkins, dashboard Kubernetes.
# Usage : sudo bash 05-keycloak.sh   (sur la VM kc, Ubuntu LTS)

set -euo pipefail

KC_VERSION="26.0.7"
KC_ADMIN="admin"
KC_PASS="$(openssl rand -base64 15)"
IPA_SERVEUR="ipa1.stanley.lan"
BASE_DN="dc=stanley,dc=lan"

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit etre lance en root." >&2
    exit 1
fi

echo "=== [1/4] Java et utilisateur dedie ==="
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y install openjdk-21-jre-headless curl unzip

id keycloak >/dev/null 2>&1 || useradd -r -m -U -d /opt/keycloak -s /sbin/nologin keycloak

echo "=== [2/4] Installation de Keycloak $KC_VERSION ==="
cd /tmp
curl -fsSL -O "https://github.com/keycloak/keycloak/releases/download/${KC_VERSION}/keycloak-${KC_VERSION}.tar.gz"
tar -xzf "keycloak-${KC_VERSION}.tar.gz"
rm -rf /opt/keycloak/lib /opt/keycloak/bin 2>/dev/null || true
cp -r "keycloak-${KC_VERSION}/." /opt/keycloak/
chown -R keycloak:keycloak /opt/keycloak

echo "=== [3/4] Service systemd ==="
cat > /etc/systemd/system/keycloak.service <<EOF
[Unit]
Description=Keycloak - SSO STANLEY
After=network.target

[Service]
User=keycloak
Group=keycloak
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=${KC_ADMIN}
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=${KC_PASS}
ExecStart=/opt/keycloak/bin/kc.sh start-dev --http-port=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now keycloak

echo "=== [4/4] Attente du demarrage ==="
for _ in {1..30}; do
    curl -sf http://localhost:8080/ >/dev/null 2>&1 && break
    sleep 5
done

cat <<EOF

====================================================================
 Keycloak demarre.

   Console : http://$(hostname -I | awk '{print $1}'):8080
   Compte  : ${KC_ADMIN}
   Mot de passe : ${KC_PASS}      <-- a mettre au coffre

 CONFIGURATION DE LA FEDERATION LDAP (via la console web)
 ---------------------------------------------------------
 1. Creer un realm nomme "stanley"
 2. User federation > Add provider > ldap
 3. Renseigner :
      Vendor              : Red Hat Directory Server
      Connection URL      : ldaps://${IPA_SERVEUR}
      Bind DN             : uid=admin,cn=users,cn=accounts,${BASE_DN}
      Bind credential     : <mot de passe admin IPA>
      Users DN            : cn=users,cn=accounts,${BASE_DN}
      Username LDAP attr  : uid
      RDN LDAP attribute  : uid
      UUID LDAP attribute : ipaUniqueID
      User object classes : inetOrgPerson, organizationalPerson
      Edit mode           : READ_ONLY
 4. Tester la connexion, puis "Synchronize all users"
 5. Mappers > Add > group-ldap-mapper pour importer les groupes :
      Groups DN           : cn=groups,cn=accounts,${BASE_DN}
      Group object classes: groupOfNames

 IMPORTANT : le mode READ_ONLY est deliberé. FreeIPA reste la source
 unique de verite pour l'identite ; Keycloak n'est qu'une couche de
 federation. Cela evite le deuxieme risque de la section 9 du
 document (multiplication des comptes).

 En mode --start-dev, Keycloak tourne en HTTP sans base persistante.
 Pour un usage reel : PostgreSQL + certificat TLS + kc.sh start.
====================================================================
EOF
