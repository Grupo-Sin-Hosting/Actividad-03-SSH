#!/usr/bin/env bash
# telnet_laboratorio.sh — Activa o desactiva TELNET SOLO para la demostración. Nunca lo dejes activo.
# Uso:  bash telnet_laboratorio.sh activar   |   bash telnet_laboratorio.sh desactivar
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta como root"; exit 1; }
case "${1:-}" in
  activar)
    dpkg -s telnetd &>/dev/null || { apt-get update -qq; apt-get install -y -qq telnetd openbsd-inetd inetutils-telnet >/dev/null; }
    update-inetd --enable telnet            # Ubuntu lo instala DESACTIVADO (#<off># en /etc/inetd.conf)
    systemctl restart openbsd-inetd
    echo "⚠️  TELNET activo en el puerto 23. Desactívalo al terminar: bash $0 desactivar" ;;
  desactivar)
    update-inetd --disable telnet 2>/dev/null || true
    systemctl disable --now openbsd-inetd 2>/dev/null || true
    apt-get purge -y -qq telnetd >/dev/null 2>&1 || true
    ss -tln | grep -q ':23 ' && echo "❌ El puerto 23 sigue abierto" || echo "✅ TELNET desactivado y desinstalado" ;;
  *) echo "Uso: bash $0 activar|desactivar"; exit 1 ;;
esac
