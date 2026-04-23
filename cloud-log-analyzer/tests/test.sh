#!/usr/bin/env bash
# Pruebas automaticas para Variante C: detectar primer codigo 503.
# Solo valida logs_C.txt, que es el dataset asignado a esta variante.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -x ./analyzer ]]; then
  echo "[INFO] Compilando binario..."
  make
fi

# ─────────────────────────────────────────────
# Funcion: ejecutar ./analyzer con un archivo
# Soporta ejecucion nativa ARM64 o emulada
# ─────────────────────────────────────────────
run_analyzer() {
  local input_file="$1"

  if [[ $(uname -m) == "aarch64" ]]; then
    cat "$input_file" | ./analyzer
  elif command -v qemu-aarch64 >/dev/null 2>&1; then
    cat "$input_file" | qemu-aarch64 ./analyzer
  else
    echo "[WARN] Host no ARM64 y qemu-aarch64 no disponible; pruebas omitidas." >&2
    return 99
  fi
}

# ─────────────────────────────────────────────
# Salidas esperadas para Variante C
# ─────────────────────────────────────────────
expected_output() {
  local key="$1"
  case "$key" in
    logs_C.txt)
      # logs_C.txt: 200,200,301,302,404,500,503,...
      # El 503 aparece en la linea 7
      cat <<'TXT'
=== Mini Cloud Log Analyzer (Variante C) ===
Primer 503 encontrado en la linea: 7
TXT
      ;;
    *)
      echo "[SKIP] Archivo $key no corresponde a Variante C." >&2
      return 2
      ;;
  esac
}

# ─────────────────────────────────────────────
# Prueba adicional: archivo SIN ningun 503
# ─────────────────────────────────────────────
test_sin_503() {
  echo "[TEST] Validando caso sin ningun 503"

  local input
  input=$(printf "200\n404\n201\n500\n")

  local output
  if [[ $(uname -m) == "aarch64" ]]; then
    output=$(echo "$input" | ./analyzer)
  elif command -v qemu-aarch64 >/dev/null 2>&1; then
    output=$(echo "$input" | qemu-aarch64 ./analyzer)
  else
    echo "[WARN] No se puede ejecutar prueba sin 503." >&2
    return
  fi

  local expected
  expected=$(cat <<'TXT'
=== Mini Cloud Log Analyzer (Variante C) ===
No se encontro ningun codigo 503
TXT
)

  if [[ "$output" == "$expected" ]]; then
    echo "[OK] Caso sin 503"
  else
    echo "[FAIL] Caso sin 503"
    echo "--- Esperado ---"
    echo "$expected"
    echo "--- Obtenido ---"
    echo "$output"
    return 1
  fi
}

# ─────────────────────────────────────────────
# Prueba: 503 en la ultima linea sin newline final
# ─────────────────────────────────────────────
test_503_ultima_linea() {
  echo "[TEST] Validando 503 en ultima linea (sin newline final)"

  local output
  if [[ $(uname -m) == "aarch64" ]]; then
    output=$(printf "200\n404\n503" | ./analyzer)
  elif command -v qemu-aarch64 >/dev/null 2>&1; then
    output=$(printf "200\n404\n503" | qemu-aarch64 ./analyzer)
  else
    echo "[WARN] No se puede ejecutar esta prueba." >&2
    return
  fi

  local expected
  expected=$(cat <<'TXT'
=== Mini Cloud Log Analyzer (Variante C) ===
Primer 503 encontrado en la linea: 3
TXT
)

  if
