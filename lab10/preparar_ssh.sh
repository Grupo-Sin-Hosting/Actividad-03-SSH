#!/usr/bin/env bash
# preparar_ssh.sh — Identidad propia del servidor y acceso por clave ed25519 para el administrador.
# Uso (en el servidor, como root):  bash preparar_ssh.sh <usuario_admin>     (el usuario del Lab 2, p. ej. ana)
set -euo pipefail
cd "$(dirname "$0")"
ADMIN="${1:?Uso: bash preparar_ssh.sh <usuario_admin>}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root"; exit 1; }
id "$ADMIN" &>/dev/null || { echo "No existe $ADMIN (Lab 2)"; exit 1; }

# 1. Claves de HOST propias: una imagen o VM clonada trae las mismas claves en todos los equipos (misma "cédula")
if grep -q 'buildkitsandbox\|@localhost' /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null || [[ ! -f resultados/.claves_host_regeneradas ]]; then
  # TODO 1 (resuelto): borrar las claves de host actuales y generar nuevas
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -A
  systemctl restart ssh
  mkdir -p resultados && date -Iseconds > resultados/.claves_host_regeneradas
fi
echo "Huella del servidor (compárala en la primera conexión):"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub

# 2. Par de claves del CLIENTE (aquí el cliente es root del servidor; en la vida real, tu PC)
# TODO 2 (resuelto): par ed25519 con 64 rondas, comentario y sin frase (en tu PC real, ¡usa una frase!)
[[ -f ~/.ssh/id_ed25519 ]] || ssh-keygen -t ed25519 -a 64 -C "admin-horizonte-2026" -N "" -f ~/.ssh/id_ed25519

# 3. Autorizar la clave pública en la cuenta del administrador (lo que hace ssh-copy-id)
install -d -o "$ADMIN" -g "$ADMIN" -m 700 "/home/$ADMIN/.ssh"
touch "/home/$ADMIN/.ssh/authorized_keys"
grep -qF "$(cut -d' ' -f2 ~/.ssh/id_ed25519.pub)" "/home/$ADMIN/.ssh/authorized_keys" || cat ~/.ssh/id_ed25519.pub >> "/home/$ADMIN/.ssh/authorized_keys"
chown "$ADMIN:$ADMIN" "/home/$ADMIN/.ssh/authorized_keys"
# TODO 3 (resuelto): sshd rechaza authorized_keys si otros pueden escribirlo
chmod 600 "/home/$ADMIN/.ssh/authorized_keys"

# 4. known_hosts con la huella REAL (sin aceptar a ciegas) y un alias en ~/.ssh/config
ssh-keygen -R 127.0.0.1 >/dev/null 2>&1 || true
ssh-keyscan -t ed25519 127.0.0.1 2>/dev/null >> ~/.ssh/known_hosts
if ! grep -q '^Host horizonte$' ~/.ssh/config 2>/dev/null; then
  cat >> ~/.ssh/config <<EOF

Host horizonte
    HostName 127.0.0.1
    User $ADMIN
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
fi
chmod 600 ~/.ssh/config
ssh -o BatchMode=yes horizonte 'echo "Conectado como $(whoami) a $(hostname) con clave ed25519"'