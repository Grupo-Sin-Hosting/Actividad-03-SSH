# Bitácora de uso de IA — Laboratorio 11 (SSH endurecido, SFTP, fail2ban y túneles)

Estudiante: Lizeth Rodríguez · Entorno: contenedor `horizonte-servidor-lab02` (`srv-horizonte`, Ubuntu 24.04,
OpenSSH 9.6p1, fail2ban + nftables), PC con Windows (OpenSSH_for_Windows 9.5p2) · Fecha: 25/10/2026

Reglas que respeté:
- **Dos sesiones** abiertas en el servidor antes de tocar sshd (ventana de trabajo y salvavidas). `sshd -t` validó
  la configuración antes de cada reinicio.
- **Ninguna clave privada** se pegó en la IA ni aparece en las capturas. La clave de mi PC (`lizeth-pc-2026`) se
  creó en Windows con frase; solo la `.pub` se copió al servidor.
- **No acepté huellas sin verificar**: ante "REMOTE HOST IDENTIFICATION HAS CHANGED" comparé la huella por otro
  canal (`docker exec … ssh-keygen -lf`) antes de borrar solo esa entrada.
- El ataque de fuerza bruta se hizo **solo contra mi servidor del curso**, desde un contenedor temporal en la misma
  red Docker, con 6 intentos de un usuario inexistente. Al final desbloqueé la IP.

| # | Qué pregunté | Qué respondió la IA | Cómo lo verifiqué | Qué aprendí |
|---|---|---|---|---|
| 1 | Cómo completar los 6 TODO de `10-horizonte.conf` sin romper el acceso. | Cambiar `PermitRootLogin`/`PasswordAuthentication` a `no`, `AllowGroups sshadmins sftp-web` y el bloque `Match Group sftp-web` al final; comentarios siempre en su propia línea. | `grep` del archivo, `sshd -t` en el script y `sshd -T` con los valores nuevos; root y contraseñas rechazados, lizeth entra. | `Match` va al final y los comentarios al final de línea rompen `ForceCommand`. |
| 2 | Por qué `sshd_config.d/` y "gana la primera aparición". | El `Include` está al inicio de `sshd_config`; en sshd vale el primer valor leído. | `sshd -T` mostró nuestros valores aunque el `sshd_config` de Ubuntu no se tocó. | Configurar sin editar el archivo del paquete. |
| 3 | Qué hacer con `/srv/horizonte` para la jaula. | Debe ser `root:root` y no escribible por el grupo, igual que sus superiores; `www` sigue `root:webadmin 2775`. | Antes: `drwxrwsr-x root:webadmin`. Con `chmod g+w` de prueba, sftp se cortó y `auth.log` mostró `bad ownership or modes for chroot directory`; con `g-w` volvió a `/www`. | Por qué sshd exige la raíz de la jaula solo de root. |
| 4 | Por qué `journalctl` no mostraba nada de `comunicacion`. | Comparar el journal con `/var/log/auth.log` y ver quién escucha en `/dev/log` (`ss -xlp`, `ps`). | `/dev/log` era el socket de `/usr/sbin/syslogd`; `dpkg -S` → `inetutils-syslogd`; `dpkg.log` → instalado el 23/10 21:56:54 junto con telnetd (Lab 10). | Una dependencia que queda instalada puede romper otro servicio días después. |
| 5 | Cómo arreglarlo sin romper otra cosa. | Simular primero (`apt-get -s purge`), purgar `inetutils-syslogd`, restaurar el enlace `/dev/log` y reiniciar ssh y fail2ban. | La simulación mostró que también se iba `inetutils-telnetd`; después el journal registró `Accepted publickey … SHA256:A36M7//…` y el puerto 23 siguió cerrado. | Simular antes de borrar paquetes. |
| 6 | El nombre de la unidad para `journalmatch`. | En Ubuntu 24.04 es `ssh.service`; el filtro por defecto busca `sshd.service`. | `systemctl list-units` → `ssh.service`; `Journal matches: _SYSTEMD_UNIT=ssh.service + _COMM=sshd`. | Comprobar el nombre real de la unidad. |
| 7 | Cómo simular el ataque desde otro equipo. | Un contenedor temporal en `alternativa_docker_default` que intente 6 veces `ssh intruso@172.18.0.2`; desde el propio servidor no sirve por `ignoreip 127.0.0.1/8`. | Alpine falló (comillas de PowerShell y paquete no encontrado); con la imagen `horizonte-servidor:24.04`: 3× `Permission denied` y 3× `Connection refused`, `Ban 172.18.0.3` en el log y la IP en `addr-set-sshd`. | PowerShell 5.1 borra las comillas dobles internas al pasar argumentos. |
| 8 | Por qué se bloqueó al tercer intento si `maxretry = 4`. | En modo `aggressive` cada conexión genera varias líneas que cuentan (`Invalid user` y `Connection closed … [preauth]`). | `fail2ban.log` muestra varios `Found` por segundo antes del `Ban`; `Total failed: 20` entre los dos ataques. | Cómo cuenta fail2ban las fallas. |
| 9 | Qué hacer con "REMOTE HOST IDENTIFICATION HAS CHANGED" desde Windows. | Es la clave vieja (de antes del Lab 10). Verificar la huella por otro canal y solo entonces `ssh-keygen -R "[localhost]:2222"`. | La huella del aviso y la de `ssh-keygen -lf` en el servidor coincidieron: `SHA256:KueRdm7E…`. | Aplicar en la práctica la reflexión del Lab 10. |
| 10 | Por qué la conexión desde Windows se cortaba (`Connection aborted`). | `LoginGraceTime 20`: la pregunta de la huella quedó abierta más de 20 s y el servidor cerró. | `ssh -v` llegaba a `NEWKEYS` y se cortaba; el journal mostraba la conexión de 172.18.0.1 sin intento de clave. Con la huella guardada, conectó. | Mis propias medidas de seguridad también tienen efectos que hay que entender. |
| 11 | Cómo explicar el túnel local, `-D` y `-J`. | `-L 9081:127.0.0.1:8081` publica en la PC un puerto que sale desde el servidor; `-D` crea un proxy SOCKS dinámico; `-J` salta por un bastión. | `curl.exe http://127.0.0.1:9081/eco` devolvió el JSON con `"cliente": "127.0.0.1"`; el verificador → ✅ túnel. | Alcanzar servicios internos sin exponerlos. |
| 12 | Cuántos intentos recibe un SSH en internet. | Los estudios con honeypots registran miles por día. | Lo contrasté con Security Magazine (2021): ~73 000 ataques en 24 h, 57 763 de fuerza bruta SSH. | Citar una fuente, no un número de la IA. |

## Conclusión
La IA me ayudó sobre todo a diagnosticar. El problema más importante no estaba en la guía: un `syslogd` instalado
como dependencia de TELNET en el Lab 10 le quitaba los registros al journal, y sin ellos fail2ban habría quedado
ciego. Lo confirmé con `ss`, `dpkg -S` y `dpkg.log` antes de cambiar nada. Cada respuesta la verifiqué con
`sshd -T`, el registro, `nft` o el verificador. El servidor quedó solo con claves, sin root, con SFTP enjaulado para
comunicación, fail2ban bloqueando en nftables y la API interna accesible solo por túnel. Resultado: **15 de 15**.
