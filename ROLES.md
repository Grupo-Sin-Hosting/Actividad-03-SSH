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

### Lizeth Rodríguez — Claves ed25519 y sshd endurecido (Lab 11)
El servidor del colegio ahora solo acepta SSH con clave: apagamos las contraseñas (PasswordAuthentication no)
y el acceso de root (PermitRootLogin no), y solo pueden entrar los grupos sshadmins y sftp-web (AllowGroups).
La configuración va en sshd_config.d/10-horizonte.conf porque se lee primero y en sshd gana el primer valor.
Hacia fuera solo publicamos el puerto 2222; cambiar el puerto es una capa extra, la defensa real son las claves,
AllowGroups y fail2ban. Con LogLevel VERBOSE queda registrada la huella de la clave con la que entra cada persona.
Siempre trabajé con dos sesiones abiertas y validé con sshd -t antes de reiniciar.


### Jacqueline Caceres — TELNET en claro (Lab 10)
Ubuntu instala TELNET desactivado; lo activamos solo para la demostración y después lo desinstalamos.
Mientras tcpdump grababa el puerto 23, se inició sesión con la usuaria de prueba "secretaria".
En Wireshark, con Analizar > Seguir > Flujo TCP, se lee todo: "login:", el usuario, "Password:",
la contraseña Circular2026 y hasta el texto escrito en la sesión. Cualquiera en la misma red podría verlo.
TELNET todavía existe en routers e impresoras viejos porque es muy liviano y nunca se actualizaron;
en esos casos hay que reemplazarlo por SSH o aislarlo en una red de gestión.

