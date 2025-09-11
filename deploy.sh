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

# Opcional: migrar storage ativo (caso use ActiveStorage com Cloud)
# echo "📂 Migrando ActiveStorage..."
# RAILS_ENV=production bundle exec rake active_storage:update

# Reinicia o servidor (ajusta conforme teu setup, ex: puma, passenger, etc.)
echo "🔄 Reiniciando Puma..."
sudo systemctl restart puma

echo "✅ Deploy finalizado com sucesso!"
