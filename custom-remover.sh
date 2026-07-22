dnf remove -y ipa-server ipa-server-dns ipa-client bind-dyndb-ldap
dnf autoremove -y
rm -rf /etc/ipa

rm -rf /var/lib/ipa

rm -rf /var/log/ipa

rm -rf /var/lib/dirsrv

rm -rf /etc/dirsrv

rm -rf /etc/pki/pki-tomcat

rm -rf /var/lib/pki

rm -rf /var/log/pki
rm -f /etc/krb5.conf

rm -rf /var/lib/krb5kdc
rm -rf /var/named/*

rm -f /etc/named.conf
rm -rf /etc/certmonger

rm -rf /var/lib/certmonger