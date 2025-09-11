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

# Limpa assets antigos
echo "🧹 Limpando assets antigos..."
RAILS_ENV=production bundle exec rake assets:clean

# Reinicia serviços
echo "🔄 Reiniciando Puma..."
sudo systemctl restart puma

echo "🔄 Reiniciando Nginx..."
sudo systemctl restart nginx

# ==========================================================
# Função de verificação com debug
# ==========================================================
check_service() {
  local service=$1
  echo "📡 Checando status do $service..."

  # Pega status detalhado
  STATUS=$(systemctl show -p ActiveState,SubState --value $service | tr '\n' ' ')

  if [[ "$STATUS" == *"active running"* ]]; then
    echo "✅ $service está rodando."
    sudo systemctl status $service --no-pager | head -n 10
  else
    echo "❌ $service não subiu corretamente (estado: $STATUS). Debug abaixo:"
    sudo systemctl status $service --no-pager
    sudo journalctl -u $service -n 50 --no-pager
    exit 1
  fi
}

# Checa Puma e Nginx
check_service puma
check_service nginx

echo "🏁 Deploy finalizado!"
