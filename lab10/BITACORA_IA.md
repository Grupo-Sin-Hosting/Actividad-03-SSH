# Bitácora de uso de IA — Laboratorio 10 (TELNET vs SSH)

Estudiante: Lizeth Rodríguez · Entorno: contenedor `horizonte-servidor-lab02` (`srv-horizonte`, Ubuntu 24.04,
OpenSSH 9.6p1), Wireshark en Windows · Fecha: 23–25/10/2026

Reglas que respeté (sección 7 de la guía):
- **Nunca** pegué la clave privada en la IA ni en las capturas: de `id_ed25519` solo se mostró el nombre y los
  permisos con `ls -l`. Lo único que se compartió son huellas (`SHA256:…`) y la clave pública, que son públicas.
- **No** acepté huellas a ciegas: después de regenerar las claves de host, `known_hosts` se llenó con
  `ssh-keyscan` contra el propio servidor y la huella se comparó con `ssh-keygen -lf`. Las opciones
  `StrictHostKeyChecking=no` y `UserKnownHostsFile=/dev/null` solo aparecen en el script del docente (usuaria de
  prueba) y en una consulta de diagnóstico a `localhost` para ver el `kex`; no quedaron en ninguna configuración.
- TELNET se activó solo para la captura y se **desactivó y desinstaló** al terminar (verificador ✅ puerto 23
  cerrado).
- Las pruebas fueron únicamente contra mi servidor del curso, y la contraseña de las capturas es la de la usuaria
  de prueba `secretaria`.

| # | Qué pregunté | Qué respondió la IA | Cómo lo verifiqué | Qué aprendí |
|---|---|---|---|---|
| 1 | Revisión de mi `preparar_ssh.sh` con los 4 TODO. | Los comandos estaban bien, pero al pegar se habían borrado `EOF` y `fi`, que cierran el bloque `Host horizonte`; sin ellos el script da error de sintaxis. | Reemplacé el archivo y el script terminó con `Conectado como lizeth … con clave ed25519`. | Un heredoc necesita su `EOF` en la columna 1. |
| 2 | Qué significa `root@buildkitsandbox` en la huella del servidor (prompt 2). | La clave se creó al construir la imagen; todos los que usan la imagen comparten la misma clave de host y uno podría hacerse pasar por el servidor de otro. Se corrige con `rm /etc/ssh/ssh_host_*` y `ssh-keygen -A`. | Después de `preparar_ssh.sh`: `root@srv-horizonte` con otra huella (`KueRdm7E…`); verificador ✅ claves de host propias. | Clonar VMs o imágenes también clona la identidad. |
| 3 | Por qué en el Explorador no aparecía "Seguir flujo TCP". | Esa opción está dentro de Wireshark, que no estaba instalado (los `.pcap` tenían icono genérico). | Instalé Wireshark y abrí `telnet.pcap`: *Analizar > Seguir > Flujo TCP*. | Distinguir la herramienta del archivo. |
| 4 | Cómo leer el flujo TCP de TELNET y de SSH. | En TELNET, rojo = cliente y azul = servidor, todo en texto. En SSH solo se leen la versión y la lista de algoritmos; lo demás va cifrado. | Vi `login:`/`secretaria` y `Password:`/`Circular2026`; en SSH, la búsqueda de `Circular2026` no encontró nada. | Qué ve exactamente un espía en la red. |
| 5 | Explicar cada algoritmo negociado en mi `ssh -v` (prompt 1). | `sntrup761x25519-sha512`: kex híbrido post-cuántico (NTRU Prime + X25519); `ssh-ed25519`: identidad del servidor; `chacha20-poly1305`: cifrado autenticado (MAC implícito). | Coincide con la lista del flujo SSH en Wireshark y con el verificador (✅ intercambio híbrido post-cuántico); lo contrasté con las notas de versión de OpenSSH 9.0. | Por qué importa el riesgo de "guardar ahora, descifrar después". |
| 6 | Comparar ed25519, ecdsa y rsa para la clave del cliente. | ed25519 tiene claves cortas (256 bits) y es rápido; RSA necesita 3072 bits o más; ECDSA depende de un buen generador aleatorio al firmar. `-a 64` agrega rondas que protegen la privada si tiene frase. | `ls -l ~/.ssh` → `id_ed25519` 600 y `.pub` 644; `authorized_keys` de lizeth con 600. | En la PC real la clave debe tener frase. |
| 7 | Por qué `comunicado.html` quedó `-rwxr-xr-x`. | Vino de Windows con 755 por `docker cp` y `scp` conserva los permisos del original. | `chmod 664` + `scp -p` → `-rw-rw-r-- lizeth webadmin`. | Revisar los permisos, no solo dueño y grupo. |
| 8 | Por qué `curl https://localhost/comunicado.html` daba `000`. | nginx (Lab 5) solo responde HTTPS al nombre del colegio; hay que pedir `www.horizonte.internal`. | `curl -sk --resolve www.horizonte.internal:443:127.0.0.1 …` devolvió el HTML; `systemctl is-active nginx` → active. | El nombre (SNI) importa en HTTPS. |
| 9 | Pasos seguros ante "REMOTE HOST IDENTIFICATION HAS CHANGED" (prompt 3). | Detenerse, verificar la huella por otro canal (consola), comparar y solo entonces `ssh-keygen -R`; nunca desactivar la comprobación. | Lo relacioné con lo que hice: regeneré la clave, `ssh-keygen -R 127.0.0.1` y `ssh-keyscan`, comparando la huella con `ssh-keygen -lf`. | La advertencia es una protección, no un error que hay que callar. |

## Conclusión
La prueba del espía me mostró con mis propias capturas por qué TELNET no se puede usar: usuario, contraseña y todo
lo que se escribe viajan legibles, mientras que en SSH solo se ve la versión. La IA me ayudó a interpretar los
algoritmos y a encontrar tres detalles: el `EOF` borrado, Wireshark que faltaba y los permisos del comunicado. Cada
respuesta la comprobé con `ls`, `ssh -v`, Wireshark o el verificador. La clave privada nunca salió del servidor y
TELNET quedó desinstalado. Resultado: **11 de 11**.
