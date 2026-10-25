#!/usr/bin/env bash
# verificar_lab11.sh — Comprueba el SSH endurecido, el SFTP enjaulado, fail2ban y los túneles.
# Uso (en el servidor, como root):  bash verificar_lab11.sh <usuario_admin>
cd "$(dirname "$0")"
ADMIN="${1:-ana}"
ok=0; total=0
revisar() {
  local desc="$1"; shift; total=$((total + 1))
  if "$@" &>/dev/null; then echo "✅ $desc"; ok=$((ok + 1)); else echo "❌ $desc"; fi
}
T() { sshd -T | grep -i "^$1 " | cut -d' ' -f2-; }
SFTP=(sftp -b - -i /root/.ssh/comunicacion_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=no comunicacion@127.0.0.1)

root_rechazado() { ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@127.0.0.1 true 2>&1 | grep -q 'Permission denied'; }
admin_entra()    { [[ "$(ssh -o BatchMode=yes horizonte whoami)" == "$ADMIN" ]]; }
admin_grupo()    { id -nG "$ADMIN" | grep -qw sshadmins && T allowgroups | grep -q sshadmins; }
sftp_publica()   { rm -f /srv/horizonte/www/prueba-sftp.txt; echo hola > /root/prueba-sftp.txt
                   printf 'put /root/prueba-sftp.txt prueba-sftp.txt\nchmod 664 prueba-sftp.txt\n' | "${SFTP[@]}" >/dev/null 2>&1
                   [[ $(stat -c '%U:%G %a' /srv/horizonte/www/prueba-sftp.txt) == "comunicacion:webadmin 664" ]]; }
sftp_enjaulado() { printf 'cd /etc\n' | "${SFTP[@]}" 2>&1 | grep -qi 'No such file'; }
sin_terminal()   { ssh -i /root/.ssh/comunicacion_ed25519 -o BatchMode=yes comunicacion@127.0.0.1 id 2>&1 | grep -q 'sftp connections only'; }
kex_pq()         { T kexalgorithms | grep -q '^sntrup761x25519'; }
huella_log()     { journalctl -u ssh --no-pager | grep -q "Accepted publickey for $ADMIN .* ED25519 SHA256:"; }
banner_ascii()   { [[ -s /etc/issue.net ]] && ! LC_ALL=C grep -q '[^[:print:][:space:]]' /etc/issue.net; }
f2b_ve_ssh()     { fail2ban-client status sshd | grep -q '_SYSTEMD_UNIT=ssh.service'; }
f2b_bloquea()    { fail2ban-client set sshd banip 203.0.113.66 >/dev/null; local r=1
                   nft list set inet f2b-table addr-set-sshd 2>/dev/null | grep -q 203.0.113.66 && r=0
                   fail2ban-client set sshd unbanip 203.0.113.66 >/dev/null; return $r; }
tunel_local()    { ssh -o BatchMode=yes -f -N -L 9082:127.0.0.1:8081 horizonte && sleep 1
                   curl -s http://127.0.0.1:9082/eco | grep -q '"metodo"'; local r=$?; pkill -f 'L 9082:127.0.0.1:8081'; return $r; }

revisar "sshd -t sin errores"                                   sshd -t
revisar "root no puede entrar por SSH"                           root_rechazado
revisar "Contraseñas desactivadas (solo claves)"                 test "$(T passwordauthentication)" = no
revisar "$ADMIN entra con su clave (alias horizonte)"             admin_entra
revisar "Solo los grupos sshadmins y sftp-web (y $ADMIN en sshadmins)" admin_grupo
revisar "comunicacion publica por SFTP (archivo 664, grupo webadmin)" sftp_publica
revisar "comunicacion está enjaulado (no ve /etc)"               sftp_enjaulado
revisar "comunicacion no obtiene terminal (solo SFTP)"           sin_terminal
revisar "Intercambio de claves post-cuántico primero"            kex_pq
revisar "El registro guarda la huella de la clave usada"         huella_log
revisar "Aviso legal en ASCII (/etc/issue.net)"                  banner_ascii
revisar "fail2ban activo"                                        systemctl is-active fail2ban
revisar "fail2ban lee el journal de ssh.service"                 f2b_ve_ssh
revisar "fail2ban bloquea en nftables"                           f2b_bloquea
revisar "Túnel local: API interna 8081 alcanzable por SSH"       tunel_local
echo "Resultado: $ok de $total comprobaciones"
[[ $ok -eq $total ]]
