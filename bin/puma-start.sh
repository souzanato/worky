#!/bin/bash
set -eo pipefail   # mantém erro e pipefail, mas sem -u

APP_DIR="/opt/worky"
RVM_PATH="/home/renato/.rvm/scripts/rvm"
PUMA_CONFIG="$APP_DIR/config/puma.rb"
LOG_DIR="$APP_DIR/log"

# Garante que existe diretório de logs
mkdir -p "$LOG_DIR"

echo "[$(date)] Iniciando Puma em produção..." >> "$LOG_DIR/puma-start.log" 2>&1

# Carrega RVM (se existir)
if [ -s "$RVM_PATH" ]; then
  source "$RVM_PATH"
else
  echo "[$(date)] ERRO: RVM não encontrado em $RVM_PATH" >> "$LOG_DIR/puma-start.log" 2>&1
  exit 1
fi

cd "$APP_DIR"

# Exporta variáveis se não existirem
export RAILS_ENV="${RAILS_ENV:-production}"

# Inicia Puma com log de saída e erro
exec bundle exec puma -C "$PUMA_CONFIG" \
  >> "$LOG_DIR/puma.log" 2>&1
