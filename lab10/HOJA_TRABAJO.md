# Laboratorio 10 — Hoja de trabajo: TELNET vs SSH, "la prueba del espía"

Nombre: Lizeth Rodríguez   Fecha: 25/10/2026

Servidor del colegio: contenedor `horizonte-servidor-lab02` (hostname `srv-horizonte`, Ubuntu 24.04,
OpenSSH_9.6p1 Ubuntu-3ubuntu13.19), como root. Administradora del Lab 2: `lizeth` (grupo `webadmin`).
Usuaria de prueba que crean los scripts: `secretaria` / `Circular2026` (solo para el laboratorio).

## Parte A — La prueba del espía
**1. ¿En qué estado venía TELNET en Ubuntu 24.04?** No estaba instalado: antes de activar, `/etc/inetd.conf` ni
siquiera existía y solo escuchaba SSH (puerto 22). Al instalar `telnetd` + `openbsd-inetd`, Ubuntu agrega la línea
de telnet **desactivada** (`#<off># telnet …`). El script la habilitó con `update-inetd --enable telnet`, y después
quedó así:

```
telnet  stream  tcp     nowait  root    /usr/sbin/tcpd  /usr/sbin/telnetd
```

`ss -tlnp` mostró `inetd` escuchando en el **23** y `sshd` en el **22**.

**2. Capturas** (`bash capturar.sh telnet` → 47 paquetes, y 48 al repetirlo · `bash capturar.sh ssh` → 49 paquetes, las dos veces):

| | TELNET (puerto 23) | SSH (puerto 22) |
|---|---|---|
| ¿Se lee el usuario? | **Sí**: `secretaria` | No |
| ¿Se lee la contraseña? | **Sí**: `Circular2026` | No |
| ¿Se lee lo que se escribió en la sesión? | **Sí**: `notas-confidenciales-5to-B` | No |
| ¿Qué se ve en claro? | Todo: banner del sistema, `login:`, `Password:`, usuario, contraseña, comandos y respuestas | Solo la versión (`SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.19`) y la lista de algoritmos que se negocian; el resto va cifrado |

**3. Wireshark.** Se copiaron `telnet.pcap` y `ssh.pcap` a Windows con `docker cp` y se abrieron con
*Analizar > Seguir > Flujo TCP*. En TELNET, el servidor (azul) envía `srv-horizonte login:` y `Password:`, y el
cliente (rojo) responde `secretaria` y `Circular2026` letra por letra, legibles. En SSH, después del intercambio de
versiones y de la lista de algoritmos (`sntrup761x25519-sha512@openssh.com`, `curve25519-sha256`,
`chacha20-poly1305@openssh.com`, …), solo hay bytes cifrados. Buscar `Circular2026` en el flujo SSH no da
resultados.

**4.** `bash telnet_laboratorio.sh desactivar` → `✅ TELNET desactivado y desinstalado` (puerto 23 cerrado).

**¿Por qué existe todavía TELNET en algunos equipos (routers, impresoras)?** Por herencia y por costo. Es un
protocolo muy simple que cabe en equipos con poca memoria y poco procesador, muchos equipos viejos se fabricaron
cuando no existía SSH y el fabricante nunca actualizó el firmware, y algunos administradores lo mantienen "porque
siempre funcionó". También se usa `telnet IP puerto` como herramienta para probar si un puerto responde. Lo
correcto es desactivarlo, usar SSH donde exista o, si no hay alternativa, aislar ese equipo en una red de gestión.

## Parte B — ¿Con quién estoy hablando? (claves de host)
**1.** `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` →
`256 SHA256:Qq4VT+bskfCdAKM48BSP9+23f+CAazYXFswQhhkSfIU root@buildkitsandbox (ED25519)`

El comentario `root@buildkitsandbox` indica que la clave se generó **al construir la imagen de Docker**, no en mi
servidor. Si 30 estudiantes (o 30 VMs clonadas) tienen la **misma** clave de host, todos comparten la misma
"cédula": cualquiera de ellos tiene la clave privada y puede hacerse pasar por el servidor de otro (ataque de
intermediario, *man-in-the-middle*), y el cliente no lo notaría porque la huella es la esperada. Además, la huella
ya no identifica a un equipo concreto.

**2. TODO 1** (regenerar las claves de host):

```bash
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A
```

Resultado: `ssh-keygen: generating new host keys: RSA ECDSA ED25519` y la nueva huella
`256 SHA256:KueRdm7E1rfyVx8oUxN7cupZd3rMGvWJCltIvHXiJIE root@srv-horizonte (ED25519)`.

**3.** `ssh -v … localhost true 2>&1 | grep kex:`

```
kex: algorithm: sntrup761x25519-sha512@openssh.com
kex: host key algorithm: ssh-ed25519
kex: server->client cipher: chacha20-poly1305@openssh.com MAC: <implicit> compression: none
kex: client->server cipher: chacha20-poly1305@openssh.com MAC: <implicit> compression: none
```

**sntrup761x25519** es un intercambio de claves **híbrido post-cuántico**: combina *Streamlined NTRU Prime 761*
(un algoritmo de retículos pensado para resistir computadoras cuánticas) con **X25519** (curva elíptica clásica). La
clave de sesión depende de los dos, así que hay que romper ambos para descifrar. Protege contra "guardar ahora,
descifrar después": aunque alguien grabe hoy el tráfico, una futura computadora cuántica no le bastaría. Es el
predeterminado desde OpenSSH 9.0. El servidor se identificó con su clave **ed25519** y la sesión se cifra con
**ChaCha20-Poly1305** (cifrado autenticado, por eso el MAC es `<implicit>`).

## Parte C — Acceso con clave ed25519
TODO 2 a 4 de `preparar_ssh.sh`:

```bash
[[ -f ~/.ssh/id_ed25519 ]] || ssh-keygen -t ed25519 -a 64 -C "admin-horizonte-2026" -N "" -f ~/.ssh/id_ed25519
chmod 600 "/home/$ADMIN/.ssh/authorized_keys"
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

`bash preparar_ssh.sh lizeth` → claves de host nuevas, par `admin-horizonte-2026`
(`SHA256:A36M7//ItYbT61+3SX/dkYagQmzvt6kH1xbuogu7HkY`) y
**`Conectado como lizeth a srv-horizonte con clave ed25519`**.

Al copiar el script se habían borrado sin querer las líneas `EOF` y `fi` que cierran el bloque `Host horizonte`. Se
corrigió antes de ejecutarlo.

**1. Diferencia entre `id_ed25519` e `id_ed25519.pub`.** `id_ed25519` es la clave **privada** (permisos 600, solo
root) y **nunca sale de la PC** del administrador: no se copia, no se envía y no se pega en ningún lado.
`id_ed25519.pub` es la clave **pública** (644) y es la que se copia a los servidores. Con la pública el servidor
comprueba una firma que solo la privada puede hacer, así que la contraseña ya no viaja.

**2. ¿Qué hace `authorized_keys`? ¿Por qué 600?** Es la lista de claves públicas que pueden entrar a esa cuenta
(`/home/lizeth/.ssh/authorized_keys`). Si otros usuarios pudieran escribirlo, podrían agregar su propia clave y
entrar como lizeth. Por eso `sshd` (con `StrictModes yes`) **ignora** el archivo si él o la carpeta `.ssh` tienen
permisos de escritura para el grupo u otros. Quedó `drwx------` (700) para `.ssh` y `-rw-------` (600) para
`authorized_keys`, ambos de `lizeth`.

**3. `ssh horizonte`** → `lizeth` / `srv-horizonte`. **No pidió contraseña**: el alias de `~/.ssh/config` pone
`HostName 127.0.0.1`, `User lizeth`, `IdentityFile ~/.ssh/id_ed25519` e `IdentitiesOnly yes` (usa solo esa clave y no
prueba otras). La huella del servidor se agregó a `known_hosts` con `ssh-keyscan` después de regenerarla, sin
aceptar nada a ciegas.

## Parte D — Publicar con SSH
`scp comunicado.html horizonte:/srv/horizonte/www/` → el archivo quedó de **`lizeth`** y del grupo **`webadmin`**.

- **Dueño `lizeth`**: `scp` entra como la usuaria del alias, así que ella crea el archivo.
- **Grupo `webadmin`**: en el Lab 2 la carpeta `/srv/horizonte/www` quedó `root:webadmin` con permisos `2775`.
  El bit **setgid** (la `s` de `drwxrwsr-x`) hace que todo lo que se crea dentro herede el grupo de la carpeta, y
  así cualquier miembro de `webadmin` puede editar el sitio.

Primero quedó `-rwxr-xr-x`, porque el archivo vino de Windows con permisos 755 y `scp` los conserva. Se corrigió con
`chmod 664` y `scp -p`, y quedó `-rw-rw-r-- lizeth webadmin`, igual que las demás páginas.

En el navegador de Windows, `https://www.horizonte.internal:8443/comunicado.html` muestra **"Comunicado 014/2026 — Publicado por el equipo de TI mediante SSH (scp) con clave ed25519"**. Dentro del servidor, nginx lo sirve: `curl -sk --resolve www.horizonte.internal:443:127.0.0.1 https://www.horizonte.internal/comunicado.html`
devuelve el HTML. Con `https://localhost` la conexión se rechaza (código `000`), porque desde el Lab 5 nginx solo
responde al nombre del colegio.

- `sftp horizonte` (modo lote `ls -l /srv/horizonte/www`) listó el sitio, con `comunicado.html` de `lizeth webadmin`.
- `rsync -av comunicado.html horizonte:/srv/horizonte/www/` → `sent 107 bytes received 41 bytes`: también va por SSH.
  Hubo que instalar `rsync`.

## Parte E — Verificación
`bash verificar_lab10.sh lizeth` → **Resultado: 11 de 11 comprobaciones.**

## Reflexión
**Si un día aparece "REMOTE HOST IDENTIFICATION HAS CHANGED", ¿qué hago?**

1. **Detenerme y no escribir la contraseña.** El aviso significa que la clave de host no coincide con la de
   `known_hosts`: o el servidor cambió legítimamente (se reinstaló o se regeneraron las claves, como hicimos en la
   Parte B) o alguien está en medio de la conexión.
2. **Verificar la huella por otro canal.** Preguntar al administrador o entrar por la consola física o de la VM y
   ejecutar `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, y comparar con la huella que muestra el aviso.
3. **Solo si coinciden**, borrar la entrada vieja con `ssh-keygen -R <host>` y volver a conectar, aceptando la huella
   ya verificada.

**Qué NO hago:** no borro `known_hosts` entero, no uso `StrictHostKeyChecking=no` ni `UserKnownHostsFile=/dev/null`
para "que funcione", y no acepto la nueva huella sin verificarla. Hacer eso desactiva justo la protección contra un
ataque de intermediario.
