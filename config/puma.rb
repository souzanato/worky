if ENV.fetch("RAILS_ENV", "development") == "development"
  threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
  threads threads_count, threads_count

  port ENV.fetch("PORT", 3000)

  plugin :tmp_restart
  plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

  pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
end

# config/puma.rb
if ENV.fetch("RAILS_ENV", "development") == "production"
  # 3 workers (deixa 1 core mais livre)
  workers Integer(ENV.fetch("WEB_CONCURRENCY") { 3 })

  # 15 threads por worker = 45 conexões SSE simultâneas
  threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS") { 15 })
  threads threads_count, threads_count

  preload_app!
  port ENV.fetch("PORT") { 3000 }
  environment "production"

  # Timeout longo para streaming
  worker_timeout 3600
  worker_shutdown_timeout 30

  before_fork do
    ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
  end

  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end

  plugin :tmp_restart
end
