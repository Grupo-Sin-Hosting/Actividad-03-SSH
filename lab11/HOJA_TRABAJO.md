# Laboratorio 11 — Hoja de trabajo: SSH endurecido, SFTP enjaulado, fail2ban y túneles

Nombre: Lizeth Rodríguez   Fecha: 25/10/2026

Requisito cumplido: Laboratorio 10 completo (`ssh horizonte` → `lizeth` con clave ed25519, verificador 11/11).
Servidor: contenedor `horizonte-servidor-lab02` (`srv-horizonte`, OpenSSH 9.6p1, red Docker
`alternativa_docker_default`, IP 172.18.0.2). Trabajé como root con **dos sesiones abiertas** (`docker exec`):
la ventana 1 para trabajar y la ventana 2 como salvavidas, sin tocarla.

## Parte A — Auditoría inicial
**1.** `sshd -T` **antes** de endurecer:

| Opción | Valor inicial | Riesgo |
|---|---|---|
| `permitrootlogin` | `without-password` | root podía entrar por SSH con clave |
| `passwordauthentication` | `yes` | acepta contraseñas, que se pueden adivinar por fuerza bruta |
| `x11forwarding` | `yes` | reenvío gráfico innecesario en un servidor |
| `kexalgorithms` | `sntrup761x25519-sha512@openssh.com,…,diffie-hellman-group14-sha256` | post-cuántico primero, pero acepta 10 algoritmos, incluidos los viejos |
| `loglevel` | `INFO` | no registra con qué clave entró cada usuario |

**2.** `journalctl -u ssh --since today | grep -c 'Failed\|Invalid'` → **0**: el servidor no está publicado en
internet. Uno expuesto recibe muchísimos intentos. En un estudio con *honeypots* sin proteger, Comparitech registró
unos **73 000 ataques en 24 horas** (≈ 51 por minuto), y **57 763** de ellos fueron intentos de fuerza bruta contra
SSH (Security Magazine, 2021). Un servidor del colegio con el puerto 22 abierto recibiría desde cientos hasta miles de
intentos por día, de bots que prueban `root`, `admin` y contraseñas comunes.

## Parte B — Endurecer sshd (6 TODO en `ssh/10-horizonte.conf`)

```
PermitRootLogin no
PasswordAuthentication no
AllowGroups sshadmins sftp-web
Match Group sftp-web
    ChrootDirectory /srv/horizonte
    ForceCommand internal-sftp -d /www -u 0002
    AllowTcpForwarding no
    PermitTTY no
```

`sshd -T` **después**: `permitrootlogin no`, `passwordauthentication no`, `x11forwarding no`, `loglevel VERBOSE`,
`allowgroups sshadmins` / `allowgroups sftp-web` y `kexalgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org`
(solo 3, el post-cuántico primero).

Pruebas:
- `ssh horizonte whoami` → banner legal y `lizeth`.
- `ssh root@127.0.0.1` → `Permission denied (publickey)`.
- `ssh -o PubkeyAuthentication=no lizeth@127.0.0.1` → `Permission denied (publickey)`: el servidor ya ni ofrece
  contraseña.

**1. ¿Por qué el archivo va en `sshd_config.d/` y por qué ahí "gana la primera aparición"?** En Ubuntu 24.04,
`/etc/ssh/sshd_config` empieza con `Include /etc/ssh/sshd_config.d/*.conf`, así que nuestro archivo se lee **antes**
que el resto. En sshd, para casi todas las opciones **vale el primer valor que se lee** y los siguientes se ignoran.
Por eso nuestro archivo manda sobre los valores de Ubuntu sin editar el `sshd_config` original, que puede
reemplazarse en una actualización. Cada cambio queda en un archivo propio, fácil de revisar y de versionar.

**2.** **`AuthenticationMethods publickey`** exige que la autenticación sea **solo** por clave pública: aunque otra
opción quedara activada por error, no se acepta ningún otro método. **`LogLevel VERBOSE`** registra la **huella de la
clave** con la que entró cada usuario, por ejemplo
`Accepted publickey for lizeth from 127.0.0.1 … ED25519 SHA256:A36M7//ItYbT61…`. Así se sabe qué persona (qué
clave) entró, aunque varias usen la misma cuenta, y se puede revocar justo esa clave.

**3.** En `sshd_config`, un `#` **no** inicia un comentario a mitad de línea. Si se escribiera
`ForceCommand internal-sftp -d /www -u 0002 # solo sftp`, el texto `# solo sftp` pasaría a ser **parte del
comando**: `internal-sftp` recibiría argumentos inválidos y la sesión SFTP fallaría. Lo mismo con `Banner`, que
buscaría un archivo con ese nombre. Por eso los comentarios van siempre en su propia línea.

## Parte C — El equipo de comunicación (SFTP enjaulado)
`bash endurecer_ssh.sh lizeth`:
- creó los grupos `sshadmins` y `sftp-web`;
- creó la cuenta `comunicacion` (`/usr/sbin/nologin`, grupos `sftp-web` y `webadmin`) con su clave ed25519;
- validó con `sshd -t`, reinició ssh e instaló fail2ban.

TODO del script (la jaula):

```bash
chown root:root /srv /srv/horizonte
chmod 755 /srv /srv/horizonte
```

**1. Error y regla.** Antes, `/srv/horizonte` era `drwxrwsr-x root:webadmin`, escribible por el grupo, del Lab 2.
Para comprobarlo se volvió a dar escritura al grupo un momento (`chmod g+w /srv/horizonte`). `sftp` se cortó
(`Connection closed`) y el registro mostró:

```
sshd[2195]: fatal: bad ownership or modes for chroot directory "/srv/horizonte"
```

**Regla de sshd:** la carpeta del `ChrootDirectory` **y todas sus carpetas superiores** (`/srv`, `/`) deben ser de
**root** y **no** escribibles por el grupo ni por otros. Si el usuario enjaulado pudiera escribir en la raíz de su
jaula, podría crear o reemplazar archivos que los programas usan como `/etc` o `/lib` y escapar. Con
`chmod g-w` volvió a funcionar (`Changed root directory to "/srv/horizonte"`). Lo que sí debe ser escribible es la
subcarpeta `www` (`root:webadmin 2775`), donde publica el equipo.

**2. Prueba de SFTP:**

```
sftp> pwd
Remote working directory: /www
sftp> put /root/lab11/ssh/issue.net aviso.txt
sftp> chmod 664 aviso.txt
sftp> ls -l aviso.txt
-rw-rw-r--    ? 1003     1002          250 Oct 25 11:03 aviso.txt
sftp> cd /etc
stat remote: No such file or directory
```

- Empieza en `/www` (`-d /www`).
- El archivo queda **`comunicacion webadmin 664`**: el grupo lo da el setgid de `www` y los permisos, `-u 0002`.
- `cd /etc` falla porque, para él, `/` es `/srv/horizonte`.
- Muestra `1003 1002` en vez de nombres porque dentro de la jaula no existe `/etc/passwd`.

**3.** `ssh -i ~/.ssh/comunicacion_ed25519 comunicacion@127.0.0.1 id` → **`This service allows sftp connections
only.`**: `ForceCommand internal-sftp` reemplaza cualquier comando y `PermitTTY no` niega la terminal.

## Parte D — fail2ban (2 TODO en `fail2ban/horizonte-ssh.local`)

```
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
maxretry = 4
findtime = 10m
bantime = 1h
```

**1.** `fail2ban-client status sshd` → `Journal matches: _SYSTEMD_UNIT=ssh.service + _COMM=sshd`, y
`systemctl list-units` muestra la unidad **`ssh.service`**. En Ubuntu 24.04 se llama `ssh.service`, no
`sshd.service` como espera el filtro por defecto. Sin el `journalmatch` correcto, fail2ban no vería ningún ataque.

**Problema encontrado:** los mensajes de sshd **no llegaban al journal**, solo a `/var/log/auth.log`. `/dev/log` era
el socket de **`/usr/sbin/syslogd`** (paquete `inetutils-syslogd`), y no un enlace a journald. `/var/log/dpkg.log`
mostró que se instaló el **23/10 a las 21:56:54**, como dependencia de `inetutils-telnetd` al activar TELNET en el
Lab 10. El script de ese lab purgó `telnetd`, pero dejó `inetutils-telnetd` y `inetutils-syslogd`. Corrección:

```bash
apt-get purge -y inetutils-syslogd
ln -sf /run/systemd/journal/dev-log /dev/log
systemctl restart ssh fail2ban
```

Purgar `inetutils-syslogd` también quitó el demonio `inetutils-telnetd` que había quedado. Después, el journal
registró `Accepted publickey for lizeth … ED25519 SHA256:A36M7//…` y el puerto 23 siguió cerrado.

**2. Ataque simulado.** Desde un contenedor temporal `tw1-cliente-fail2ban` (IP **172.18.0.3**) en la misma red
Docker, con 6 intentos `ssh intruso@172.18.0.2`:

| Intento | Respuesta | Qué pasó |
|---|---|---|
| 1 a 3 | `Permission denied (publickey)` | sshd registra `Invalid user intruso from 172.18.0.3`; fail2ban cuenta cada línea (`Found`) |
| 4 a 6 | `Connection refused` | fail2ban ya bloqueó la IP: nftables la rechaza antes de llegar a sshd |

En modo `aggressive` cada conexión suma más de una falla (`Invalid user` y `Connection closed … [preauth]`), por eso
se alcanzó `maxretry = 4` en el tercer intento y en menos de 2 segundos.

- `fail2ban-client status sshd` → `Total failed: 20`, `Total banned: 2`, `Banned IP list: 172.18.0.3`.
- `nft list set inet f2b-table addr-set-sshd` → `elements = { 172.18.0.3 }`, con la regla
  `tcp dport 22 ip saddr @addr-set-sshd reject with icmp port-unreachable`.
- `/var/log/fail2ban.log`:

```
2026-10-25 11:30:25,720 fail2ban.actions [2413]: NOTICE [sshd] Ban 172.18.0.3
2026-10-25 11:46:10,962 fail2ban.actions [2413]: NOTICE [sshd] Unban 172.18.0.3
2026-10-25 11:47:03,343 fail2ban.actions [2413]: NOTICE [sshd] Ban 172.18.0.3
```

Las líneas `observer … # -> 2.0` corresponden a `bantime.increment`: si la IP reincide, el siguiente bloqueo dura
el doble.

**3.** `fail2ban-client set sshd unbanip 172.18.0.3` → `1`, y el conjunto de nftables quedó vacío.

## Parte E — Túneles
**1.** Desde **mi PC con Windows** (OpenSSH_for_Windows_9.5p2), con una clave propia `lizeth-pc-2026` protegida por
frase:
- La clave se creó en la PC; solo la `.pub` se copió a `authorized_keys` de lizeth, y la privada no salió de Windows.
- Primero apareció **`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`**: la PC tenía guardada la clave vieja del
  servidor (la de la imagen), anterior a regenerarla en el Lab 10. Se verificó por otro canal con
  `docker exec … ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` → `SHA256:KueRdm7E…`, igual a la del aviso.
  Solo entonces se borró esa entrada con `ssh-keygen -R "[localhost]:2222"` y se aceptó la huella verificada.
- Las primeras conexiones se cortaron (`Connection aborted` / `Connection closed`) porque la pregunta de la huella
  quedó abierta más de **20 s** y `LoginGraceTime 20` las cerró. Con la huella ya guardada, conectó sin problema.

```
ssh -N -L 9081:127.0.0.1:8081 -p 2222 -i $HOME\.ssh\id_ed25519_horizonte lizeth@127.0.0.1
curl.exe http://127.0.0.1:9081/eco   →  {"metodo": "GET", "ruta": "/eco", … "cliente": "127.0.0.1" …}
```

**2. Camino del paquete:**

```
PC: curl ─▶ 127.0.0.1:9081 (ssh escucha en la PC)
            ║ túnel cifrado (chacha20-poly1305) por el puerto 2222 → 22 del contenedor
            ▼
srv-horizonte: sshd ─▶ 127.0.0.1:8081 (API eco, solo local) ─▶ respuesta por el mismo túnel
```

La API ve la petición como `"cliente": "127.0.0.1"` porque quien la hace es sshd dentro del servidor. La API sigue
cerrada al mundo, y solo un administrador con clave puede usarla.

- **`-D 1080` (SOCKS):** túnel **dinámico**. ssh abre un proxy SOCKS en el puerto 1080 de la PC y cada conexión que
  pasa por él sale desde el servidor hacia cualquier destino. Sirve, por ejemplo, para navegar como si se estuviera
  en la red del colegio.
- **`-J` (salto):** se conecta a un servidor interno **pasando por** un servidor de salto (*bastion*), por ejemplo
  `ssh -J lizeth@bastion lizeth@srv-interno`. Solo el bastión se expone a internet y la sesión va cifrada de
  extremo a extremo.

## Parte F — Verificación
`bash verificar_lab11.sh lizeth` → **Resultado: 15 de 15 comprobaciones.**

## Reflexión
**¿Por qué endurecer SSH con claves y AllowGroups es más importante que cambiar el puerto 22?** Cambiar el puerto
es "seguridad por oscuridad": reduce el ruido de los bots más simples, pero un escaneo de puertos encuentra el nuevo
en segundos y el servidor sigue aceptando contraseñas adivinables. Las claves ed25519 eliminan el riesgo de raíz:
no hay contraseña que adivinar ni que robar en la red. `AllowGroups` reduce quién puede siquiera intentarlo.
`PermitRootLogin no` obliga a entrar con una cuenta personal (trazable con `LogLevel VERBOSE`). fail2ban corta a
quien insiste. Cambiar el puerto puede sumarse como capa extra, pero nunca reemplaza estas medidas.

**Fuentes:**
- Security Magazine. (2021, 26 de abril). *Unsecured computer attacked 51 times per minute*.
  https://www.securitymagazine.com/articles/95082-unsecured-computer-attacked-51-times-per-minute
