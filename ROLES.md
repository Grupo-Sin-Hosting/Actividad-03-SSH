# Roles de la defensa — Actividad 03

| Integrante | GitHub | Rama | Parte | Debe poder explicar |
|---|---|---|---|---|
| Lucas Carrasco | @Lukitas2005 | `rol-dns-vistas` | Entorno y DNS profesional (Lab 9) | Arquitectura, vistas y su orden, DNSSEC con `dnssec-policy`, NSEC3, delv con ancla falsa, DS |
| Jacqueline Cáceres | @jacquelinesubia321-spec | `rol-telnet` | TELNET en claro (Lab 10, Parte A) | Captura con Wireshark (Seguir flujo TCP), qué se lee en claro, por qué TELNET sigue en routers/impresoras |
| José María Orihuela | — | `rol-ssh-identidad` | SSH cifrado e identidad (Lab 10, B y C) | Comparación del tráfico, `buildkitsandbox`, kex post-cuántico `sntrup761x25519`, "REMOTE HOST IDENTIFICATION HAS CHANGED" |
| Lizeth Rodríguez | @lixinrodriguez1-eng | `rol-sshd-endurecido` | Claves ed25519 y sshd endurecido (Lab 11, A y B) + coordinación | Tabla antes/después, `sshd_config.d`, puerto 2222, `AllowGroups`, `VERBOSE`; repositorio |
| Juniors Parapaino | @ederjuniorparapaino | `rol-sftp-tunel` | scp, SFTP enjaulado y túnel (Labs 10 D, 11 C y E) | Setgid de `webadmin`, regla del chroot, `ForceCommand`, túnel `-L`, `-D` y `-J` |
| Limber Quispe | — | `rol-fail2ban` | fail2ban y fuerza bruta (Lab 11, D) | `journalmatch`, problema de `/dev/log`, ataque, Ban/Unban, nftables |

Cada integrante: crea su rama, agrega en `ROLES.md` (debajo de su fila, en la sección "Notas") un resumen de su
parte con sus palabras, y abre un Pull Request que diga `Closes #N` (su issue).

## Notas de cada integrante

### Lucas Carrasco — Entorno y DNS profesional (Lab 9)
El entorno tiene dos partes: el servidor srv-horizonte en Docker, que solo publica SSH en el puerto 2222,
y la red red_dns, donde ns1 tiene dos caras: una para el colegio (10.10.10.2) y otra para internet (172.30.0.2).
Antes, desde internet se veían las IP internas. Con las vistas de BIND, el mismo nombre responde distinto:
el colegio recibe 10.10.10.20 e internet 203.0.113.20, y horizonte.internal da REFUSED desde fuera.
El orden importa: gana la primera vista que coincide, por eso "any" va al final.
El dominio público está firmado con dnssec-policy (ECDSA P-256 y NSEC3 sin iteraciones ni sal).
Con delv y el ancla correcta sale "fully validated"; con una sola letra cambiada, "broken trust chain".
El DS 18104 se entrega al registrador para que la cadena empiece en la raíz.

### Lizeth Rodríguez — Claves ed25519 y sshd endurecido (Lab 11)
El servidor del colegio ahora solo acepta SSH con clave: apagamos las contraseñas (PasswordAuthentication no)
y el acceso de root (PermitRootLogin no), y solo pueden entrar los grupos sshadmins y sftp-web (AllowGroups).
La configuración va en sshd_config.d/10-horizonte.conf porque se lee primero y en sshd gana el primer valor.
Hacia fuera solo publicamos el puerto 2222; cambiar el puerto es una capa extra, la defensa real son las claves,
AllowGroups y fail2ban. Con LogLevel VERBOSE queda registrada la huella de la clave con la que entra cada persona.
Siempre trabajé con dos sesiones abiertas y validé con sshd -t antes de reiniciar.

### Juniors Parapaino — SCP, SFTP enjaulado y túneles SSH (Labs 10 y 11)

En el Laboratorio 10 utilizamos SCP para publicar archivos en el servidor Horizonte y comprobamos cómo el grupo webadmin y el permiso setgid ayudan a gestionar los archivos compartidos.

En el Laboratorio 11 configuramos al usuario comunicacion para utilizar únicamente SFTP, encerrado mediante chroot en /srv/horizonte. Verificamos que comienza en /www, no puede acceder a /etc ni abrir una terminal, y que los archivos publicados tienen permisos 664.

También implementamos un túnel SSH con -L 9081:127.0.0.1:8081 para acceder desde Windows a la API interna del servidor. Aprendimos además que -D permite crear un proxy SOCKS y -J sirve para conectarse mediante un servidor bastión.

Finalmente, ejecutamos el verificador del Laboratorio 11 y obtuvimos 15 de 15 comprobaciones correctas.
### Limber Quispe — Fail2ban y fuerza bruta (Lab 11)

En el Laboratorio 11 configuramos Fail2ban para proteger el servidor Horizonte contra ataques de fuerza bruta por SSH. Establecimos un máximo de 4 intentos fallidos durante 10 minutos, con un bloqueo inicial de una hora y un tiempo mayor para reincidentes.

Realizamos una prueba desde otro contenedor con la IP `172.18.0.3`. Después de varios intentos fallidos, Fail2ban bloqueó automáticamente esa dirección mediante nftables. Posteriormente, utilizamos `unbanip` para retirar el bloqueo.

También identificamos un problema con los registros del servidor: el servicio syslogd instalado durante el Laboratorio 10 interfería con el envío de mensajes al journal. Corregimos el problema y verificamos que Fail2ban pudiera detectar los intentos fallidos.

Aprendimos que no basta con instalar una herramienta de seguridad: es necesario comprobar que realmente detecta y bloquea los ataques.

### Jacqueline Caceres — TELNET en claro (Lab 10)
Ubuntu instala TELNET desactivado; lo activamos solo para la demostración y después lo desinstalamos.
Mientras tcpdump grababa el puerto 23, se inició sesión con la usuaria de prueba "secretaria".
En Wireshark, con Analizar > Seguir > Flujo TCP, se lee todo: "login:", el usuario, "Password:",
la contraseña Circular2026 y hasta el texto escrito en la sesión. Cualquiera en la misma red podría verlo.
TELNET todavía existe en routers e impresoras viejos porque es muy liviano y nunca se actualizaron;
en esos casos hay que reemplazarlo por SSH o aislarlo en una red de gestión.

