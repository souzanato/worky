#!/usr/bin/env bash
set -e

echo "🚀 Iniciando deploy em produção..."

# Garante que tá no diretório do app
cd "$(dirname "$0")"

# Atualiza dependências Ruby
echo "📦 Instalando gems..."
RAILS_ENV=production bundle install --without development test --deployment

# Atualiza banco
echo "🗄️ Rodando migrations..."
RAILS_ENV=production bundle exec rake db:migrate

# Precompila assets
echo "🎨 Precompilando assets..."
RAILS_ENV=production bundle exec rake assets:precompile

# Limpa assets antigos (pra evitar lixo ocupando espaço)
echo "🧹 Limpando assets antigos..."
RAILS_ENV=production bundle exec rake assets:clean

# Reinicia serviços
echo "🔄 Reiniciando Puma..."
sudo systemctl restart puma

echo "🔄 Reiniciando Nginx..."
sudo systemctl restart nginx

# ==========================================================
# Verificação de serviços
# ==========================================================

echo "📡 Checando status do Puma..."
if ! systemctl is-active --quiet puma; then
  echo "❌ Puma não está rodando. Tentando debug..."
  sudo systemctl status puma --no-pager
  sudo journalctl -u puma -n 50 --no-pager
else
  echo "✅ Puma está ativo."
  sudo systemctl status puma --no-pager | head -n 10
fi

echo "📡 Checando status do Nginx..."
if ! systemctl is-active --quiet nginx; then
  echo "❌ Nginx não está rodando. Tentando debug..."
  sudo systemctl status nginx --no-pager
  sudo journalctl -u nginx -n 50 --no-pager
else
  echo "✅ Nginx está ativo."
  sudo systemctl status nginx --no-pager | head -n 10
fi

echo "🏁 Deploy finalizado com sucesso!"
