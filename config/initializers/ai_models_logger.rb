# config/initializers/ai_models_logger.rb
require "logger"

AI_MODELS_LOGGER = Logger.new($stdout)
AI_MODELS_LOGGER.level = Logger::DEBUG
AI_MODELS_LOGGER.formatter = proc do |severity, datetime, progname, msg|
  formatted_time = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "[#{formatted_time}] #{severity.ljust(5)} #{progname} -- #{msg}\n"
end
