#!/usr/bin/env bash
# capturar.sh — "La prueba del espía": inicia sesión por TELNET o por SSH mientras tcpdump graba, y muestra qué
# se puede leer de la captura. Uso (en el servidor, como root):  bash capturar.sh telnet   |   bash capturar.sh ssh
set -uo pipefail
cd "$(dirname "$0")"
PROTO="${1:?Uso: bash capturar.sh telnet|ssh}"
USUARIO=secretaria; CLAVE=Circular2026; SECRETO="notas-confidenciales-5to-B"
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root"; exit 1; }
command -v expect >/dev/null && command -v tcpdump >/dev/null || apt-get install -y -qq expect tcpdump >/dev/null

# Usuaria de prueba (solo para el laboratorio)
id "$USUARIO" &>/dev/null || useradd -m -s /bin/bash "$USUARIO"
echo "$USUARIO:$CLAVE" | chpasswd

case $PROTO in
  telnet) PUERTO=23; CMD="telnet 127.0.0.1"; PIDE="login:" ;;
  ssh)    PUERTO=22; CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no $USUARIO@127.0.0.1"; PIDE="password:" ;;
  *) echo "Protocolo desconocido: $PROTO"; exit 1 ;;
esac
ss -tln | grep -q ":$PUERTO " || { echo "Nada escucha en el puerto $PUERTO (¿activaste el servicio?)"; exit 1; }

mkdir -p resultados
PCAP=resultados/$PROTO.pcap
timeout 15 tcpdump -i lo -nn -U -w "$PCAP" "tcp port $PUERTO" 2>/dev/null &
sleep 1
expect <<EOF >/dev/null 2>&1
set timeout 10
spawn $CMD
expect "$PIDE"
if {"$PROTO" == "telnet"} { send "$USUARIO\r"; expect "Password:" }
send "$CLAVE\r"
expect "\\\$ "
send "echo $SECRETO\r"
expect "\\\$ "
send "exit\r"
expect eof
EOF
sleep 2; pkill -f "tcpdump -i lo -nn -U -w $PCAP" 2>/dev/null; sleep 1

TEXTO=$(tcpdump -r "$PCAP" -A 2>/dev/null)
echo "Captura de $PROTO: $(tcpdump -r "$PCAP" 2>/dev/null | wc -l) paquetes → $PCAP (ábrelo en Wireshark)"
for dato in "$USUARIO" "$CLAVE" "$SECRETO"; do
  if grep -qa -- "$dato" <<<"$TEXTO"; then echo "  👀 se lee en claro: $dato"; else echo "  🔒 no aparece:     $dato"; fi
done
grep -aoE 'SSH-2.0-[A-Za-z0-9_.-]+' <<<"$TEXTO" | sort -u | sed 's/^/  versión anunciada: /'
{ echo "$PROTO $(date -Iseconds)"; for d in "$USUARIO" "$CLAVE" "$SECRETO"; do grep -qa -- "$d" <<<"$TEXTO" && echo "claro $d" || echo "oculto $d"; done; } > resultados/$PROTO.txt
