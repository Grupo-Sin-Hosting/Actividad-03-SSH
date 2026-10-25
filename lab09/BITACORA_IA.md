# Bitácora de uso de IA — Laboratorio 9 (vistas, DNSSEC con dnssec-policy y monitoreo)

Estudiante: Lizeth Rodríguez · Entorno: red Docker `red_dns` (ns1 10.10.10.2 / 172.30.0.2, ns2, cliente,
externo 172.30.0.100), Ubuntu 24.04, BIND 9.18 · Fecha: 22/10/2026

Reglas que respeté (sección 7 de la guía):
- Los archivos `.private` de la clave DNSSEC **nunca** se mostraron, copiaron ni compartieron con la IA. Solo se
  listó su nombre con `ls`. Lo que se compartió es público: el DS y el ancla (clave pública).
- Se usó `dnssec-policy` (firma y re-firma automática), no el método manual `dnssec-signzone` + cron.
- **No** se desactivó la validación en ningún momento. La prueba del ancla falsa se hizo con una copia en `/tmp`
  y el resultado esperado era justamente que fallara.
- Cada respuesta de la IA la comprobé con `named-checkconf`, `dig`, `delv`, `grep` o el verificador.

| # | Qué pregunté | Qué respondió la IA | Cómo lo verifiqué | Qué aprendí |
|---|---|---|---|---|
| 1 | Cómo agregar a `red_dns` la red `internet` y el nodo `externo` que pide la guía. | Un `compose.yaml` con la red 172.30.0.0/24, ns1 en las dos redes (10.10.10.2 y 172.30.0.2) y `externo` en 172.30.0.100; al recrearse ns1, reinstalar el Lab 7. | `docker compose ps` mostró 5 nodos; `verificar_lab07.sh` → 16 de 16. | Un contenedor puede estar en dos redes, como un servidor con dos tarjetas. |
| 2 | Cómo decide BIND 9.18 qué vista responde y por qué importa el orden (prompt 1). | Recorre las vistas en orden y usa la primera cuyo `match-clients` coincide con la IP de origen; `any` debe ir al final. | Desde el cliente `www.ue-horizonte.example` → 10.10.10.20 y desde externo → 203.0.113.20. | El orden de las vistas es parte de la seguridad. |
| 3 | Qué significa `when using 'view' statements, all zones must be in views`. | Que `named.conf.default-zones` declara zonas fuera de las vistas; hay que quitar ese `include`. | `cat named.conf` mostró que la línea seguía (VS Code no había guardado); la borré con `sed`, `grep -c` → 0 y la instalación siguió. | Leer el archivo real antes de suponer que el cambio está hecho. |
| 4 | Por qué mis cambios de VS Code no llegaban al contenedor. | Las pestañas tenían el punto ● de "sin guardar"; luego apareció un conflicto de guardado porque el archivo se había cambiado en disco con `sed`. | Revisé las pestañas, acepté la versión correcta del conflicto y confirmé con `grep nsec3param` y `grep -c default-zones`. | Guardar y comprobar desde el contenedor, no solo en el editor. |
| 5 | Qué pide BIND sin `inline-signing` (lo probé sobre una copia en `/tmp`). | En 9.18 `dnssec-policy` sobre una zona estática exige `inline-signing yes;` para firmar una copia aparte. | `named-checkconf /tmp/prueba.conf` dio exactamente ese error, sin tocar la configuración real. | Probar errores en copias para no romper el servicio. |
| 6 | La primera instalación terminó con `ls: cannot access … Kue-horizonte.example.+013+*.key`. | El script espera hasta 20 s a que BIND genere la clave y firme; si no llega, falla en el paso del DS. Volver a ejecutarlo. | La segunda ejecución mostró el DS `18104 13 2 0AD9…` y "Listo"; `ls /var/lib/bind/claves` mostró la clave 18104. | Un fallo por tiempo se distingue de un error de configuración. |
| 7 | Explicar cada campo de mi RRSIG y cuándo vence (prompt 2). | Tipo, algoritmo 13, etiquetas, TTL, vencimiento, inicio, etiqueta de clave 18104 y firmante. | El 18104 coincide con el `.key`, el DS y `rndc dnssec -status`; el vencimiento (05/11) coincide con los 14 días de la política. | Relacionar el RRSIG con la clave y la política. |
| 8 | Cómo se "firma" un nombre que no existe. | Con NSEC3: registros firmados que cubren el hueco entre dos hashes de nombres existentes. | `delv … noexiste` → `negative response, fully validated` con registros `NSEC3 1 0 0 -` (0 iteraciones, sin sal). | Por qué RFC 9276 recomienda 0 iteraciones y sin sal. |
| 9 | Cómo cambiar una letra del ancla sin tocar el original. | Un `sed` que escribe una copia en `/tmp/ancla-falsa.conf` y `diff` para mostrar el cambio. | `diff` mostró `jN/9…` → `AN/9…` y `delv` dio `broken trust chain`. | Una sola letra rompe la cadena de confianza. |
| 10 | Cómo calcular en bash los días hasta el vencimiento desde `AAAAMMDDhhmmss` (prompt 3). | Cortar la cadena con `${vence:0:8}` y `${vence:8:2}`…, pasarla a segundos con `date -u -d … +%s`, restar y dividir entre 86 400. | `vigilar_dns.sh` dijo "firmas válidas por 13 días más" (hoy 22/10 → 05/11). | Usar UTC en ambos lados para no desfasar el cálculo. |
| 11 | Por qué el monitoreo avisaba `ns1=2026100701 ns2=2026100703`. | El serial del primario era menor que el del secundario; ns2 nunca copia una zona con serial más bajo. Subirlo a la fecha de hoy. | `sed` a 2026102201 + `rndc reload horizonte.internal in interna`; los dos `dig SOA` → 2026102201 y el verificador → 16 de 16. | El serial solo puede subir; con vistas, `rndc reload` lleva `in <vista>`. |
| 12 | Qué protege DNSSEC que HTTPS no, y por qué se usa poco. | DNSSEC autentica las respuestas DNS (y la inexistencia) para todos los registros; HTTPS protege la conexión. Se usa poco por la complejidad y el riesgo operativo. | Lo contrasté con RFC 4033 y con la documentación de ISC sobre `dnssec-policy`. | Las dos capas se complementan; no se reemplazan. |

## Conclusión
La IA me sirvió para entender las salidas (vistas, RRSIG, NSEC3, delv) y para diagnosticar tres tropiezos: el
`include` de `default-zones` que VS Code no había guardado, la clave que tardó en generarse y el serial menor que
el del secundario. En cada caso la causa la confirmé con un comando antes de cambiar algo. La clave privada nunca
salió de ns1, la validación nunca se apagó y la firma la hace `dnssec-policy` sola. Resultado final:
**16 de 16**, y la misma consulta da una respuesta distinta al colegio y a internet.
