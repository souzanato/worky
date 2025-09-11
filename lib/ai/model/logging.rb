# lib/ai/model/logging.rb
module Ai
  module Model
    module Logging
      def log_debug(method, message)
        AI_MODELS_LOGGER.debug(progname(method)) { message }
      end

      def log_info(method, message)
        AI_MODELS_LOGGER.info(progname(method)) { message }
      end

      def log_warn(method, message)
        AI_MODELS_LOGGER.warn(progname(method)) { message }
      end

      def log_error(method, error)
        AI_MODELS_LOGGER.error(progname(method)) { "#{error.class}: #{error.message}" }
        AI_MODELS_LOGGER.error(progname(method)) { error.backtrace.join("\n") } if error.backtrace
      end

      private

      def progname(method)
        "#{self.class.name}##{method}"
      end
    end
  end
end
