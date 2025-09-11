if ENV.fetch("RAILS_ENV", "development") == "development"
  threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
  threads threads_count, threads_count

  port ENV.fetch("PORT", 3000)

  plugin :tmp_restart
  plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

  pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
end

if ENV.fetch("RAILS_ENV", "development") == "production"
  workers Integer(ENV.fetch("WEB_CONCURRENCY") { 2 })

  threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS") { 5 })
  threads threads_count, threads_count

  preload_app!

  port        ENV.fetch("PORT") { 3000 }
  environment "production"

  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end

  plugin :tmp_restart
end
