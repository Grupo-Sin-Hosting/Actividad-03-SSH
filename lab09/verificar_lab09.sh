#!/usr/bin/env bash
# verificar_lab09.sh — Comprueba las vistas y DNSSEC. Ejecutar EN ns1:  bash /lab/lab09/verificar_lab09.sh
# Truco: desde ns1, "dig @10.10.10.2" sale con IP del colegio (vista interna) y "dig @172.30.0.2" con su IP
# pública (vista externa), así que un solo nodo puede probar las dos caras.
cd "$(dirname "$0")"
ok=0; total=0
revisar() {
  local desc="$1"; shift; total=$((total + 1))
  if "$@" &>/dev/null; then echo "✅ $desc"; ok=$((ok + 1)); else echo "❌ $desc"; fi
}
IN=10.10.10.2; EX=172.30.0.2; ANCLA=compartido/ancla-ue-horizonte.conf
r()      { dig +short +norec @"$1" "${@:2}" | tail -1; }
estado() { dig +norec @"$1" "${@:2}" | grep -o 'status: [A-Z]*' | cut -d' ' -f2; }
firmado(){ dig +dnssec +norec @$EX www.ue-horizonte.example A | grep -q 'RRSIG'; }
validado(){ delv @$EX -a $ANCLA +root=ue-horizonte.example www.ue-horizonte.example 2>&1 | grep -q 'fully validated'; }
nx_val() { delv @$EX -a $ANCLA +root=ue-horizonte.example noexiste.ue-horizonte.example 2>&1 | grep -q 'negative response, fully validated'; }
nsec3()  { dig +dnssec +norec @$EX noexiste.ue-horizonte.example | grep -q 'NSEC3'; }
falsa()  { sed 's/"\([A-Za-z0-9]\)/"X/' $ANCLA > /tmp/ancla-falsa.conf; delv @$EX -a /tmp/ancla-falsa.conf +root=ue-horizonte.example www.ue-horizonte.example 2>&1 | grep -q 'broken trust chain'; }
interna_sin_firma(){ ! dig +dnssec +norec @$IN www.ue-horizonte.example A | grep -q RRSIG; }

revisar "named-checkconf -z (todas las zonas de todas las vistas)" named-checkconf -z
revisar "Interna: www.ue-horizonte.example → 10.10.10.20"       test "$(r $IN www.ue-horizonte.example)" = 10.10.10.20
revisar "Interna: intranet existe (10.10.10.21)"                 test "$(r $IN intranet.ue-horizonte.example)" = 10.10.10.21
revisar "Interna: horizonte.internal sigue funcionando"          test "$(r $IN www.horizonte.internal)" = 10.10.10.20
revisar "ns2 sigue copiando la zona interna"                     test "$(r 10.10.10.3 www.horizonte.internal)" = 10.10.10.20
revisar "Externa: www.ue-horizonte.example → 203.0.113.20"      test "$(r $EX www.ue-horizonte.example)" = 203.0.113.20
revisar "Externa: intranet NO existe (NXDOMAIN)"                 test "$(estado $EX intranet.ue-horizonte.example)" = NXDOMAIN
revisar "Externa: horizonte.internal no se revela (REFUSED)"     test "$(estado $EX www.horizonte.internal)" = REFUSED
revisar "Externa: respuestas firmadas (RRSIG)"                   firmado
revisar "Externa: inexistencia probada con NSEC3"                nsec3
revisar "delv: respuesta 'fully validated' con el ancla"         validado
revisar "delv: NXDOMAIN también validado"                        nx_val
revisar "delv: con un ancla falsa → 'broken trust chain'"        falsa
revisar "La vista interna no necesita firmas"                    interna_sin_firma
revisar "DS generado para el registrador"                        grep -q ' IN DS ' compartido/DS-ue-horizonte.example.txt
revisar "Monitoreo sin alertas (vigilar_dns.sh)"                 bash vigilar_dns.sh
echo "Resultado: $ok de $total comprobaciones"
[[ $ok -eq $total ]]
