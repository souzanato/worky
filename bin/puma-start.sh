#!/bin/bash
set -e

APP_DIR="/opt/worky"
RUBY_PATH="/home/renato/.rvm/rubies/ruby-3.4.8/bin"
PUMA_CONFIG="$APP_DIR/config/puma.rb"
LOG_DIR="$APP_DIR/log"

# Garante que existe diretório de logs
mkdir -p "$LOG_DIR"

echo "[$(date)] Iniciando Puma em produção..." >> "$LOG_DIR/puma-start.log" 2>&1

cd "$APP_DIR"

# Exporta variáveis
export RAILS_ENV="production"
export PATH="$RUBY_PATH:$PATH"
export GEM_HOME="/home/renato/.rvm/gems/ruby-3.4.8"
export GEM_PATH="/home/renato/.rvm/gems/ruby-3.4.8:/home/renato/.rvm/gems/ruby-3.4.8@global"

# Inicia Puma usando caminho absoluto
exec "$RUBY_PATH/bundle" exec puma -C "$PUMA_CONFIG" \
  >> "$LOG_DIR/puma.log" 2>&1