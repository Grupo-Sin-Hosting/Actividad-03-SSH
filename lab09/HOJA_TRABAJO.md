# Laboratorio 9 — Hoja de trabajo: vistas (split-horizon), DNSSEC y monitoreo

Nombre: Lizeth Rodríguez   Fecha: 22/10/2026

Red `red_dns` actualizada con la red `internet` (172.30.0.0/24) y el nodo `externo` (172.30.0.100). ns1 tiene dos
caras: 10.10.10.2 (colegio) y 172.30.0.2 (pública). Al recrearse ns1 se reinstaló el Laboratorio 7
(`instalar_ns1.sh` y `instalar_ns2.sh`) y `verificar_lab07.sh` dio **16 de 16**. Carpeta de trabajo: `/lab/lab09`.

## Parte A — El problema
Desde el nodo **externo** (simula internet), antes de las vistas:

| Consulta | Respuesta |
|---|---|
| `dig +short @172.30.0.2 www.horizonte.internal` | `10.10.10.20` |
| `dig +short @172.30.0.2 mail.horizonte.internal` | `10.10.10.25` |
| `dig @172.30.0.2 horizonte.internal AXFR` | `; Transfer failed.` |

**¿Qué información interna ve alguien de fuera?** Cualquiera en internet puede preguntar nombres del colegio y
recibir sus IPs privadas: el servidor web (10.10.10.20), el correo (10.10.10.25) y, adivinando nombres, otros
equipos. La transferencia completa (AXFR) **no** salió porque desde el Laboratorio 7 exige la clave TSIG, pero las
consultas una por una sí responden.

**¿Por qué es un riesgo?** Es reconocimiento gratis para un atacante: conoce el direccionamiento interno, qué
servicios hay y cómo se llaman, sin tocar la red. Esa información sirve para preparar ataques dirigidos o
phishing creíble. Además, `horizonte.internal` no tiene ningún sentido fuera del colegio.

## Parte B — Vistas
TODO completados:

| Archivo | Qué se escribió |
|---|---|
| `ns1/named.conf` | Se **borró** `include "/etc/bind/named.conf.default-zones";` |
| `ns1/named.conf.local` (vista interna) | `match-clients { "red-colegio"; };` |
| `ns1/named.conf.local` (zona externa) | `dnssec-policy "horizonte";` y `inline-signing yes;` |
| `ns1/named.conf.options` | `nsec3param iterations 0 optout no salt-length 0;` |

**1. Error con `named.conf` tal como viene:**

```
/etc/bind/named.conf.default-zones:2: when using 'view' statements, all zones must be in views
```

Ocurre porque, en cuanto existe una sola `view`, BIND exige que **todas** las zonas estén dentro de alguna vista.
`named.conf.default-zones` de Ubuntu declara fuera de las vistas las zonas por defecto (`localhost`,
`127.in-addr.arpa`, `0.in-addr.arpa`, `255.in-addr.arpa`). El instalador valida con `named-checkconf -z` y se
detuvo antes de reiniciar BIND, así que el servicio nunca quedó caído. Se borró la línea y se volvió a instalar.

**Orden de las vistas.** BIND recorre las vistas **en orden** y usa la **primera** cuyo `match-clients` coincide
con la IP de origen. La interna (`acl "red-colegio" { 10.10.10.0/24; 127.0.0.0/8; }`) va primero y la externa
(`match-clients { any; }`) al final. Si estuvieran al revés, `any` atraparía también al colegio y nadie vería la
vista interna.

**2. Tabla (el mismo nombre, dos respuestas):**

| Consulta | Desde el cliente (10.10.10.50) | Desde externo (172.30.0.100) |
|---|---|---|
| `www.ue-horizonte.example` | `10.10.10.20` | `203.0.113.20` |
| `intranet.ue-horizonte.example` | `10.10.10.21` | `NXDOMAIN` |
| `www.horizonte.internal` | `10.10.10.20` (`NOERROR`) | `REFUSED` |

El colegio llega a su web por la IP privada sin salir a internet y ve la intranet. Internet solo ve la IP
pública, la intranet "no existe" para ellos y `horizonte.internal` no se le revela: la vista externa ni siquiera
tiene esa zona, por eso responde `REFUSED`.

## Parte C — DNSSEC con dnssec-policy
**1. Sin `inline-signing yes;`**, `named-checkconf` (probado sobre una copia en `/tmp`) dice:

```
'inline-signing yes;' must also be configured explicitly for zones using dnssec-policy without a configured
'allow-update' or 'update-policy'.
```

En BIND 9.18, `dnssec-policy` necesita poder escribir en la zona. Como nuestra zona es un archivo estático (sin
actualizaciones dinámicas), hay que pedir `inline-signing`: BIND deja **intacto** el archivo que escribimos
(`db.ue-horizonte.example`) y mantiene aparte una copia firmada (`db.ue-horizonte.example.signed`) que crea, firma y
re-firma solo.

**2. Archivos que generó BIND:**

```
/var/lib/bind/claves:
Kue-horizonte.example.+013+18104.key  Kue-horizonte.example.+013+18104.private  Kue-horizonte.example.+013+18104.state
/var/lib/bind/externa:
db.ue-horizonte.example  db.ue-horizonte.example.jbk  db.ue-horizonte.example.signed  db.ue-horizonte.example.signed.jnl
```

- `.key`: la clave **pública** (DNSKEY). `+013` = algoritmo 13 (ECDSA P-256) y `18104` = etiqueta de la clave.
- `.private`: la clave **privada** con la que BIND firma. No se muestra, no se copia y no se sube al repositorio.
- `.state`: el estado de la clave para `dnssec-policy` (publicada, firmando, DS…).
- `.signed`: la zona firmada que BIND sirve; `.jnl` y `.jbk`: diarios de cambios de la firma en línea.

**3. RRSIG** (`dig +dnssec @172.30.0.2 www.ue-horizonte.example`):

```
www.ue-horizonte.example. 3600 IN RRSIG A 13 3 3600 20261105161444 20261022152550 18104 ue-horizonte.example. nMEsF/...
```

| Campo | Valor | Significado |
|---|---|---|
| Tipo cubierto | `A` | Firma el registro A de `www` |
| Algoritmo | `13` | ECDSA P-256 con SHA-256 (la CSK de la política) |
| Etiquetas | `3` | `www`, `ue-horizonte`, `example` |
| TTL original | `3600` | El TTL con el que se firmó |
| Vencimiento | `20261105161444` | 05/11/2026 16:14:44 UTC (unos 14 días: `signatures-validity 14d`) |
| Inicio | `20261022152550` | 22/10/2026 15:25:50 UTC; BIND la fecha una hora antes de firmar para tolerar relojes desfasados |
| Etiqueta de clave | `18104` | La misma clave del `.key` y del DS |
| Firmante | `ue-horizonte.example.` | La zona que firma |

**4. delv con el ancla:**

```
delv @172.30.0.2 -a /lab/lab09/compartido/ancla-ue-horizonte.conf +root=ue-horizonte.example www.ue-horizonte.example
; fully validated
www.ue-horizonte.example. 3600 IN A 203.0.113.20
```

"Fully validated" significa que delv comprobó la cadena completa: el ancla de confianza (nuestra clave pública)
valida el DNSKEY de la zona, y ese DNSKEY valida el RRSIG del registro A. La respuesta es auténtica y no fue
alterada en el camino.

Con `noexiste.ue-horizonte.example` → `; negative response, fully validated`. **Lo que no existe se firma con
NSEC3**: la zona tiene una cadena ordenada de *hashes* de los nombres que sí existen, y cada registro NSEC3 (firmado)
dice "entre este hash y el siguiente no hay nada". El servidor entrega los NSEC3 que cubren el hueco donde estaría
`noexiste` y así prueba su inexistencia sin firmar en el momento. En la salida se ve `NSEC3 1 0 0 -`: SHA-1, sin
opt-out, **0 iteraciones** y **sin sal (`-`)**, tal como se configuró (RFC 9276).

**5. Ancla falsa** (copia en `/tmp` con una sola letra cambiada, `jN/9…` → `AN/9…`):

```
;; validating ue-horizonte.example/DNSKEY: no valid signature found (DS)
;; broken trust chain resolving 'www.ue-horizonte.example/A/IN': 172.30.0.2#53
;; resolution failed: broken trust chain
```

La clave del ancla ya no coincide con la DNSKEY que firma la zona, así que la cadena se rompe y delv **no entrega
ninguna respuesta**. Esto demuestra que un atacante que envenene la caché con respuestas falsas no puede firmarlas:
sin la clave privada correcta, un resolutor que valida las rechaza (SERVFAIL) en lugar de engañar al usuario.

**6. DS:** `compartido/DS-ue-horizonte.example.txt`

```
ue-horizonte.example. IN DS 18104 13 2 0AD99597A6C6A10002F5F9B60C5051E369BC87123AB77DA8A8A7D64226F780D7
```

Es el resumen SHA-256 (tipo `2`) de la clave `18104`, algoritmo `13`. Se entrega al **registrador / zona padre**
(en Bolivia, NIC Bolivia para `.bo`) para que lo publique en la zona superior. Así la cadena de confianza empieza en
la raíz firmada y llega hasta nuestro dominio sin que cada usuario tenga que configurar un ancla a mano.

`rndc dnssec -status ue-horizonte.example in externa` → `dnssec-policy: horizonte`, clave `18104 (ECDSAP256SHA256),
CSK`, `published: yes`, `key signing: yes`, `zone signing: yes`, `No rollover scheduled` y **`ds: hidden`**: BIND
sabe que el DS todavía **no** está publicado en el padre. Mientras siga `hidden`, DNSSEC solo protege a quien use el
ancla manual (como delv aquí).

## Parte D — Monitoreo
TODO de `vigilar_dns.sh`:

```bash
fin=$(date -u -d "${vence:0:8} ${vence:8:2}:${vence:10:2}:${vence:12:2}" +%s)
dias=$(( (fin - $(date -u +%s)) / 86400 ))
```

`${vence:0:8}` toma `AAAAMMDD` y los otros cortes arman `hh:mm:ss`. `date -u` lo pasa a segundos (UTC, igual que
el RRSIG), se resta la hora actual y se divide entre 86 400 segundos por día.

Primera ejecución: **⚠️ `horizonte.internal: ns1=2026100701 ns2=2026100703`**. La zona interna del Lab 9 traía el
serial 2026100701, **menor** que el 2026100703 que ns2 tenía del Lab 7. Un secundario solo copia la zona si el
primario tiene un serial **mayor**, así que ns2 se quedaba con la versión vieja. Se subió el serial a
**2026102201** (fecha de hoy) y se recargó con `rndc reload horizonte.internal in interna`. Los dos servidores
mostraron 2026102201.

Segunda ejecución: serial igual en ns1 y ns2 ✅, firmas válidas por **13 días más** ✅, los tres servidores
responden en 4 ms ✅, consultas por vista: **30 externa / 58 interna**, y `ℹ️ DS en el padre: hidden`.

`bash /lab/lab09/verificar_lab09.sh` → **Resultado: 16 de 16 comprobaciones.**

**¿Qué pasaría si BIND se detiene 3 semanas (firmas de 14 días)?** Las firmas se renuevan cada 5 días
(`signatures-refresh`), pero solo si BIND está funcionando. Con BIND detenido, las firmas que ya circulan (en los
secundarios o cachés) vencen como máximo a los 14 días. Desde ese momento, todo resolutor que valide DNSSEC
responderá **SERVFAIL**: el dominio "desaparece" para esos usuarios, aunque los datos sigan ahí. Por eso el
monitoreo avisa cuando quedan menos de 3 días (`ALERTA_DIAS`).

## Reflexión
**¿Qué protege DNSSEC que HTTPS no protege?** HTTPS protege la conexión **después** de saber a qué IP ir. DNSSEC
protege **la respuesta del DNS**: que la IP sea la auténtica y no una inyectada por envenenamiento de caché. También
cubre lo que no es web (correo con MX, registros TXT como SPF/DMARC, CAA) y prueba que un nombre no existe. HTTPS
detecta un sitio falso por el certificado, pero solo si el usuario no ignora la advertencia, y no protege los
demás registros DNS.

**¿Por qué muchos dominios aún no lo usan?** Porque agrega trabajo y riesgo de operación: hay que mantener claves,
re-firmar y coordinar el DS con el registrador. Si algo falla (firmas vencidas, DS que no coincide), el dominio
deja de resolverse para todos los que validan, y eso es peor que no tener DNSSEC. Además, no todos los
registradores lo facilitan y muchos ven HTTPS como "suficiente". `dnssec-policy` reduce mucho ese trabajo porque
BIND genera, firma y re-firma solo.
