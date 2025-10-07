# 1. CONCERN - app/controllers/concerns/sse_streaming.rb
module SseStreaming
  extend ActiveSupport::Concern

  included do
    include ActionController::Live
  end

  class SSE
    def initialize(io)
      @io = io
    end

    def write(data, options = {})
      options.each { |k, v| @io.write "#{k}: #{v}\n" }
      @io.write "data: #{JSON.generate(data)}\n\n"
    rescue IOError
      # Cliente desconectou
    end

    def close
      @io.close
    rescue IOError
      # Já fechado
    end
  end

  private

  def stream_response(&block)
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"

    sse = SSE.new(response.stream)

    begin
      yield(sse)
    ensure
      sse.close
    end
  end
end
