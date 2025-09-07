# config/puma.rb

# Quantos workers (processos). Normal é usar igual ao número de cores da CPU.
workers Integer(ENV.fetch("WEB_CONCURRENCY") { 2 })

# Threads por worker. 5 a 16 é comum.
threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS") { 5 })
threads threads_count, threads_count

preload_app!

rackup      DefaultRackup
port        ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }

on_worker_boot do
  # Reconeção pro ActiveRecord
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end
