#!/bin/bash
# ---------------------------------------------------------------------------
# El vigía de la cocina — busca videos sin preparar y los prepara.
#
# Hace UNA sola pregunta, por cada video de cada academia:
#     ¿ya existe su hls/<ruta>/master.m3u8?
# Si no existe, lo cocina. Nada más. SE ARREGLA SOLO: si la cocina estaba
# apagada o algo falló a mitad, en la vuelta siguiente lo agarra igual.
#
# VERSIÓN VPS (ING-09, casa = cero, 15/8/2026). Las academias salen de
# academias.conf (una por renglón) y cada una tiene su alias r2-<academia>.
#
# Uso:
#   vigia-cocina.sh            → recorre todas las academias de academias.conf
#   vigia-cocina.sh artedehoy  → solo esa
#
# Corre en el VPS de Chile. Lo dispara un timer de systemd (cada 10 min).
# ---------------------------------------------------------------------------
set -uo pipefail

RAIZ=/opt/druidatech-cocina
COCINA="$RAIZ/cocina-hls.sh"
LOG="$RAIZ/vigia.log"
CANDADO="$RAIZ/.vigia.lock"
FALLOS="$RAIZ/fallos"      # un archivo por video que no salio, con la cuenta
TOPE=3                     # despues de 3 intentos se deja de insistir

exec 9>"$CANDADO"
flock -n 9 || { echo "$(date +%F\ %T) ya hay una cocina andando, salgo" >> "$LOG"; exit 0; }

decir() { echo "$(date +%F\ %T) $*" >> "$LOG"; }

DEPOSITOS="${1:-}"
if [ -z "$DEPOSITOS" ]; then
  DEPOSITOS=$(grep -v '^\s*#' "$RAIZ/academias.conf" | grep -v '^\s*$')
fi

for DEP in $DEPOSITOS; do
  ALIAS="r2-$DEP"
  # Los videos de la academia, sin meterse en lo ya cocinado (hls/).
  VIDEOS=$(mc ls --recursive "$ALIAS/$DEP" 2>/dev/null \
           | awk '{print $NF}' | grep -Ei '\.(mp4|mov|m4v|mkv|webm)$' | grep -v '^hls/')

  for KEY in $VIDEOS; do
    BASE="${KEY%.*}"
    if mc stat "$ALIAS/$DEP/hls/$BASE/master.m3u8" >/dev/null 2>&1; then
      continue                                   # ya está preparado
    fi

    # Un video que no se puede preparar NUNCA (formato raro, archivo cortado) no
    # puede quedar reintentándose cada 10 minutos para siempre: se insiste 3
    # veces y después se deja anotado para que lo miremos nosotros.
    mkdir -p "$FALLOS"
    MARCA="$FALLOS/$(printf '%s' "$DEP/$KEY" | md5sum | cut -c1-16)"
    VECES=$(cat "$MARCA" 2>/dev/null || echo 0)
    if [ "$VECES" -ge "$TOPE" ]; then
      continue                                   # ya se intentó bastante
    fi

    decir "cocinando $DEP/$KEY"
    INICIO=$(date +%s)
    if "$COCINA" "$DEP" "$KEY" >>"$LOG" 2>&1; then
      decir "listo $DEP/$KEY ($(( ($(date +%s) - INICIO) / 60 )) min)"
      rm -f "$MARCA"
    else
      VECES=$((VECES + 1)); echo "$VECES" > "$MARCA"
      if [ "$VECES" -ge "$TOPE" ]; then
        decir "FALLÓ $DEP/$KEY por ${VECES}ª vez — SE DEJA DE INSISTIR, hay que mirarlo (el aula sigue usando el video original)"
      else
        decir "FALLÓ $DEP/$KEY (intento $VECES de $TOPE) — se reintenta"
      fi
    fi
  done
done

decir "vuelta terminada"
