# Actividad 03 — De TELNET a SSH endurecido (y DNS con vistas y DNSSEC)

**Tecnología Web I (SIS-0150) · Universidad Privada Domingo Savio (UPDS) · Semestre 2/2026**
Docente: M.Sc. Ing. Jimmy Nataniel Requena Llorentty · Grupo **Sin Hosting**:
Jacqueline Cáceres · Lucas Carrasco · José María Orihuela · Juniors Parapaino · Limber Quispe · Lizeth Rodríguez

> Demuestra con evidencia la diferencia de seguridad entre TELNET y SSH y deja el servidor de la organización
> accesible solo por SSH endurecido.

| Laboratorio | Qué se hizo | Verificador |
|---|---|---|
| [Lab 9](lab09/HOJA_TRABAJO.md) | Vistas en ns1 (colegio vs internet), DNSSEC con `dnssec-policy` + NSEC3, `delv` con ancla válida y falsa, DS y monitoreo | **16 de 16** |
| [Lab 10](lab10/HOJA_TRABAJO.md) | Captura TELNET y SSH (Wireshark), claves de host propias, kex post-cuántico, clave ed25519, alias, `scp`/`sftp`/`rsync` | **11 de 11** |
| [Lab 11](lab11/HOJA_TRABAJO.md) | `sshd` endurecido (sin root, sin contraseña, `AllowGroups`), SFTP enjaulado, fail2ban + nftables con ataque simulado, túnel local | **15 de 15** |

- **Informe técnico grupal (APA 7):** [informe/](informe/) — `Informe_Tecnico_Actividad03_SSH_Grupo_Sin_Hosting.docx` / `.pdf`
- **Presentación:** [presentacion/](presentacion/) — `.pptx`
- **Bitácoras de IA:** [lab09](lab09/BITACORA_IA.md) · [lab10](lab10/BITACORA_IA.md) · [lab11](lab11/BITACORA_IA.md) (la consolidada está en el informe)
- **Roles de la defensa:** [ROLES.md](ROLES.md)

## Resultado en una tabla

| | TELNET (23) | SSH (22) |
|---|---|---|
| Usuario / contraseña / lo escrito | **Se leen en claro** en Wireshark | No se leen (cifrado ChaCha20-Poly1305) |
| Qué queda en el servidor | TELNET **desinstalado** (puerto 23 cerrado) | Solo claves ed25519, sin root, `AllowGroups sshadmins sftp-web`, kex `sntrup761x25519` primero, `LogLevel VERBOSE` |
| Puerto hacia fuera | — | Solo **2222** en el anfitrión (Docker 2222→22) |
| Fuerza bruta | — | fail2ban: 4 fallas en 10 min → bloqueo 1 h en nftables (creciente) |

## Cómo reproducir

```powershell
# Servidor del colegio (labs 2-5): contenedor horizonte-servidor-lab02
docker cp lab10 horizonte-servidor-lab02:/root/lab10
docker cp lab11 horizonte-servidor-lab02:/root/lab11
docker exec -it horizonte-servidor-lab02 bash
#   cd ~/lab10 && bash telnet_laboratorio.sh activar && bash capturar.sh telnet && bash capturar.sh ssh
#   bash telnet_laboratorio.sh desactivar && bash preparar_ssh.sh <usuario> && bash verificar_lab10.sh <usuario>
#   cd ~/lab11 && bash endurecer_ssh.sh <usuario> && bash verificar_lab11.sh <usuario>

# DNS con vistas (red_dns ampliada con la red "internet" y el nodo "externo")
cd red_dns
docker compose up -d --build
docker compose exec ns1 bash /lab/lab07/instalar_ns1.sh
docker compose exec ns2 bash /lab/lab07/instalar_ns2.sh
docker compose exec ns1 bash /lab/lab09/instalar_vistas_dnssec.sh
docker compose exec ns1 bash /lab/lab09/verificar_lab09.sh
```

⚠️ Antes de modificar `sshd`, deja **dos sesiones** abiertas en el servidor.
⚠️ Después de usar `telnet_laboratorio.sh`, revisa que no quede `inetutils-syslogd`
(`dpkg -l | grep syslogd`): se instala como dependencia y le quita `/dev/log` al journal (ver informe del Lab 11).

## Estructura

```
.
├── README.md · ROLES.md · .gitignore · .gitattributes
├── red_dns/        # compose.yaml (aula + internet, nodo externo) y Dockerfile
├── lab07/          # instaladores de ns1/ns2 que reutiliza el Lab 9 (sin clave TSIG)
├── lab09/          # ns1/ (vistas, dnssec-policy), vigilar_dns.sh, compartido/ (DS y ancla públicos)
├── lab10/          # preparar_ssh.sh, resultados/ (telnet.pcap, ssh.pcap), hoja y bitácora
├── lab11/          # ssh/10-horizonte.conf, fail2ban/horizonte-ssh.local, endurecer_ssh.sh
├── informe/        # informe grupal (APA 7) e informes de cada laboratorio
└── presentacion/   # presentación de la actividad
```

## Seguridad
- **Ninguna clave privada** está en el repositorio (SSH, DNSSEC `.private`, TSIG `.key`): ver `.gitignore`.
- `lab09/compartido/` solo tiene el **DS** y el **ancla** (clave pública).
- Los `.pcap` del Lab 10 se incluyen porque la guía los pide; solo contienen la contraseña de la usuaria de
  prueba `secretaria` creada para el laboratorio.
