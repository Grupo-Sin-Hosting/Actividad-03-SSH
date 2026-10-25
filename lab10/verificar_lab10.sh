#!/usr/bin/env bash
# verificar_lab10.sh — Comprueba el Laboratorio 10 (TELNET vs SSH). Ejecutar en el servidor como root:
#   bash verificar_lab10.sh <usuario_admin>
cd "$(dirname "$0")"
ADMIN="${1:-ana}"
ok=0; total=0
revisar() {
  local desc="$1"; shift; total=$((total + 1))
  if "$@" &>/dev/null; then echo "✅ $desc"; ok=$((ok + 1)); else echo "❌ $desc"; fi
}
telnet_en_claro() { grep -q '^claro Circular2026' resultados/telnet.txt; }
ssh_oculto()      { grep -q '^oculto Circular2026' resultados/ssh.txt && grep -q '^oculto notas-confidenciales' resultados/ssh.txt; }
host_propia()     { ! grep -q 'buildkitsandbox' /etc/ssh/ssh_host_ed25519_key.pub && [[ -f resultados/.claves_host_regeneradas ]]; }
known_ok()        { ssh-keygen -F 127.0.0.1 -f ~/.ssh/known_hosts | grep -q "$(awk '{print $2}' /etc/ssh/ssh_host_ed25519_key.pub)"; }
clave_cliente()   { ssh-keygen -lf ~/.ssh/id_ed25519.pub | grep -q '(ED25519)'; }
autorizada()      { grep -qF "$(awk '{print $2}' ~/.ssh/id_ed25519.pub)" "/home/$ADMIN/.ssh/authorized_keys"; }
permisos()        { [[ $(stat -c %a "/home/$ADMIN/.ssh") == 700 && $(stat -c %a "/home/$ADMIN/.ssh/authorized_keys") == 600 ]]; }
entra_con_clave() { [[ "$(ssh -o BatchMode=yes horizonte whoami)" == "$ADMIN" ]]; }
kex_pq()          { ssh -v -o BatchMode=yes horizonte true 2>&1 | grep -q 'kex: algorithm: sntrup761x25519\|kex: algorithm: mlkem768x25519'; }
publicado()       { [[ -f /srv/horizonte/www/comunicado.html && $(stat -c %U:%G /srv/horizonte/www/comunicado.html) == "$ADMIN:webadmin" ]]; }
telnet_apagado()  { ! ss -tln | grep -q ':23 '; }

revisar "Captura TELNET: la contraseña se lee en claro"         telnet_en_claro
revisar "Captura SSH: contraseña y datos NO se leen"            ssh_oculto
revisar "Claves de host propias (no las de la imagen)"          host_propia
revisar "known_hosts con la huella real del servidor"           known_ok
revisar "Clave del cliente ed25519"                             clave_cliente
revisar "Clave pública autorizada en la cuenta de $ADMIN"       autorizada
revisar "Permisos de ~/.ssh (700) y authorized_keys (600)"      permisos
revisar "Acceso con clave y alias 'horizonte' (sin contraseña)"  entra_con_clave
revisar "Intercambio de claves híbrido post-cuántico"           kex_pq
revisar "comunicado.html publicado por scp (dueño $ADMIN, grupo webadmin)" publicado
revisar "TELNET desactivado al terminar (puerto 23 cerrado)"    telnet_apagado
echo "Resultado: $ok de $total comprobaciones"
[[ $ok -eq $total ]]
