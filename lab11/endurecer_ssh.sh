#!/usr/bin/env bash
# endurecer_ssh.sh — SSH endurecido, SFTP enjaulado para comunicación y fail2ban.
# Uso (en el servidor, como root, DESPUÉS del Lab 10):  bash endurecer_ssh.sh <usuario_admin>
# ⚠️  Regla de oro: deja OTRA sesión SSH abierta mientras cambias sshd. Si te equivocas, la usas para arreglarlo.
set -euo pipefail
cd "$(dirname "$0")"
ADMIN="${1:?Uso: bash endurecer_ssh.sh <usuario_admin>}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root"; exit 1; }

# 0. Salvavidas: el administrador DEBE tener clave autorizada, o quedará fuera al apagar las contraseñas
[[ -s /home/$ADMIN/.ssh/authorized_keys ]] || { echo "❌ $ADMIN no tiene authorized_keys: completa el Lab 10 primero"; exit 1; }

# 1. Grupos que pueden usar SSH
getent group sshadmins >/dev/null || groupadd sshadmins
getent group sftp-web  >/dev/null || groupadd sftp-web
usermod -aG sshadmins "$ADMIN"

# 2. Cuenta del equipo de comunicación: solo SFTP para publicar en www (grupo webadmin del Lab 2)
id comunicacion &>/dev/null || useradd -m -s /usr/sbin/nologin -G sftp-web,webadmin comunicacion
[[ -f /root/.ssh/comunicacion_ed25519 ]] || ssh-keygen -q -t ed25519 -C "comunicacion-horizonte" -f /root/.ssh/comunicacion_ed25519 -N ""
install -d -o comunicacion -g comunicacion -m 700 /home/comunicacion/.ssh
install -o comunicacion -g comunicacion -m 600 /root/.ssh/comunicacion_ed25519.pub /home/comunicacion/.ssh/authorized_keys

# 3. La jaula: sshd exige que la carpeta del chroot y todas sus superiores sean de root y NO escribibles por el grupo
# TODO: si la jaula falla con 'bad ownership or modes for chroot directory' (journalctl -u ssh), corrige aquí
#       el dueño y los permisos de /srv/horizonte (NO los de www)
chown root:root /srv /srv/horizonte
chmod 755 /srv /srv/horizonte
ls -ld /srv/horizonte/www

# 4. Configuración de sshd: validar ANTES de reiniciar
install -m 644 ssh/issue.net /etc/issue.net
install -m 644 ssh/10-horizonte.conf /etc/ssh/sshd_config.d/10-horizonte.conf
sshd -t
systemctl restart ssh

# 5. fail2ban con nftables leyendo el journal
dpkg -s fail2ban &>/dev/null || { apt-get update -qq; apt-get install -y -qq fail2ban nftables python3-systemd >/dev/null; }
install -m 644 fail2ban/horizonte-ssh.local /etc/fail2ban/jail.d/horizonte-ssh.local
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd | sed -n '1,4p'
echo "✅ SSH endurecido. Prueba en OTRA terminal: ssh horizonte   y   sftp -i ~/.ssh/comunicacion_ed25519 comunicacion@127.0.0.1"
