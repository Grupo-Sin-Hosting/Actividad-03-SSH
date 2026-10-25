#!/usr/bin/env bash
# instalar_vistas_dnssec.sh — ns1 con vistas (interna/externa) y el dominio público firmado con DNSSEC.
# Ejecutar EN ns1 (después del Lab 7):  bash /lab/lab09/instalar_vistas_dnssec.sh
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root (o con sudo)"; exit 1; }
[[ -s /etc/bind/transferencia.key ]] || { echo "Primero completa el Laboratorio 7 en ns1"; exit 1; }

# 1. Carpetas: zonas por vista, claves DNSSEC y registro de consultas (todo escribible por bind)
install -d -o bind -g bind -m 755 /var/lib/bind/interna /var/lib/bind/externa /var/log/named
install -d -o bind -g bind -m 750 /var/lib/bind/claves

# 2. Zonas y configuración
install -o bind -g bind -m 644 ns1/db.horizonte.internal ns1/db.10.10.10 /var/lib/bind/
install -o bind -g bind -m 644 ns1/db.ue-horizonte.example.interna /var/lib/bind/interna/db.ue-horizonte.example
install -o bind -g bind -m 644 ns1/db.ue-horizonte.example.externa /var/lib/bind/externa/db.ue-horizonte.example
install -o root -g bind -m 644 ns1/named.conf ns1/named.conf.options ns1/named.conf.local /etc/bind/

# 3. Validar todo (incluidas las zonas de cada vista) y aplicar
if ! salida=$(named-checkconf -z 2>&1); then echo "$salida" | grep -v "loaded serial"; exit 1; fi
systemctl restart named
for i in $(seq 1 20); do                                   # esperar a que BIND genere la clave y firme
  ls /var/lib/bind/claves/Kue-horizonte.example.+013+*.key &>/dev/null && [[ -s /var/lib/bind/externa/db.ue-horizonte.example.signed ]] && break
  sleep 1
done

# 4. El DS (lo que se entregaría a NIC Bolivia / al registrador) y el ancla de confianza para probar con delv
install -d -m 755 compartido
CLAVE=$(ls /var/lib/bind/claves/Kue-horizonte.example.+013+*.key | head -1)
dnssec-dsfromkey -2 "$CLAVE" > compartido/DS-ue-horizonte.example.txt
awk '$4=="DNSKEY" && $5==257 {k=""; for(i=8;i<=NF;i++) k=k $i; printf "trust-anchors {\n  ue-horizonte.example. static-key %s %s %s \"%s\";\n};\n", $5,$6,$7,k}' "$CLAVE" \
  > compartido/ancla-ue-horizonte.conf
echo "DS para el registrador:"; cat compartido/DS-ue-horizonte.example.txt
echo "Listo. Prueba desde 'externo':  delv @172.30.0.2 -a /lab/lab09/compartido/ancla-ue-horizonte.conf +root=ue-horizonte.example www.ue-horizonte.example"
