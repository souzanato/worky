# lib/ai/model/gpt5.rb
module Ai
  module Model
    class Gpt4o
      DEFAULT_TIMEOUT = 300  # 5 minutos
      DEFAULT_MODEL = "gpt-4o"  # Modelo atual (GPT-5 ainda não existe)

      def initialize(timeout: DEFAULT_TIMEOUT, model: DEFAULT_MODEL)
        @model = model
        @timeout = timeout

        # Configurar o cliente OpenAI com timeout personalizado
        @client = OpenAI::Client.new(
          access_token: Settings.apis.openai.api_key,
          request_timeout: timeout,  # Timeout total da requisição
          log_errors: Rails.env.development?  # Log de erros em desenvolvimento
        )

        # Se estiver usando Faraday internamente, pode configurar assim:
        # @client = OpenAI::Client.new do |config|
        #   config.access_token = ENV["OPENAI_API_KEY"]
        #   config.request_timeout = timeout
        #   config.faraday_options = {
        #     request: {
        #       open_timeout: 10,      # Timeout para estabelecer conexão
        #       timeout: timeout,      # Timeout total
        #       write_timeout: 10      # Timeout para enviar dados
        #     }
        #   }
        # end
      end

      # Pergunta única (sem contexto)
      def ask(prompt, system_message: nil, temperature: 0.7, max_tokens: nil)
        messages = build_messages(prompt, system_message)

        begin
          log_request(messages) if Rails.env.development?

          response = @client.chat(
            parameters: {
              model: @model,
              messages: messages,
              temperature: temperature,
              max_tokens: max_tokens
              # Para GPT-5 quando disponível:
              # reasoning_effort: "minimal", # mais rápido
              # verbosity: "low",            # mais direto
            }.compact  # Remove nil values
          )

          parse_response(response)
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Pergunta com contexto (sessão)
      def ask_with_context(messages, temperature: 0.7, max_tokens: nil)
        begin
          log_request(messages) if Rails.env.development?

          response = @client.chat(
            parameters: {
              model: @model,
              messages: messages,
              temperature: temperature,
              max_tokens: max_tokens
              # Para GPT-5:
              # reasoning_effort: "minimal",
              # verbosity: "low",
            }.compact
          )

          parse_response(response)
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Pergunta com streaming
      def ask_stream(prompt, system_message: nil, temperature: 0.7, &block)
        messages = build_messages(prompt, system_message)

        begin
          log_request(messages) if Rails.env.development?

          full_response = ""

          @client.chat(
            parameters: {
              model: @model,
              messages: messages,
              temperature: temperature,
              stream: proc do |chunk, _bytesize|
                content = chunk.dig("choices", 0, "delta", "content")
                if content
                  full_response += content
                  yield({ done: false, content: content, full_response: full_response }) if block_given?
                elsif chunk.dig("choices", 0, "finish_reason")
                  yield({ done: true, content: full_response }) if block_given?
                end
              end
            }
          )

          { text: full_response }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Pergunta com contexto e streaming
      def ask_with_context_stream(messages, temperature: 0.7, &block)
        begin
          log_request(messages) if Rails.env.development?

          full_response = ""

          @client.chat(
            parameters: {
              model: @model,
              messages: messages,
              temperature: temperature,
              stream: proc do |chunk, _bytesize|
                content = chunk.dig("choices", 0, "delta", "content")
                if content
                  full_response += content
                  yield({ done: false, content: content, full_response: full_response }) if block_given?
                elsif chunk.dig("choices", 0, "finish_reason")
                  yield({ done: true, content: full_response }) if block_given?
                end
              end
            }
          )

          { text: full_response }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Método para testar a conexão
      def test_connection
        response = @client.models.list
        { success: true, models: response["data"].map { |m| m["id"] } }
      rescue => e
        { success: false, error: e.message }
      end

      private

      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", content: system_message } if system_message
        msgs << { role: "user", content: prompt }
        msgs
      end

      def parse_response(response)
        if response.is_a?(Hash)
          content = response.dig("choices", 0, "message", "content")
          usage = response["usage"]

          {
            text: content,
            usage: usage || {},
            model: response["model"],
            finish_reason: response.dig("choices", 0, "finish_reason")
          }
        else
          raise "Unexpected response format: #{response.class}"
        end
      rescue => e
        Rails.logger.error "Error parsing OpenAI response: #{e.message}"
        raise
      end

      def handle_timeout_error(error)
        Rails.logger.error "OpenAI timeout after #{@timeout} seconds: #{error.message}"
        raise "OpenAI API timeout after #{@timeout} seconds. Consider using streaming for long responses."
      end

      def handle_general_error(error)
        Rails.logger.error "OpenAI API error: #{error.message}"
        Rails.logger.error error.backtrace.join("\n") if Rails.env.development?

        # Tratar erros específicos da API
        if error.message.include?("Rate limit")
          raise "OpenAI rate limit exceeded. Please wait and try again."
        elsif error.message.include?("Invalid API key")
          raise "Invalid OpenAI API key. Please check your configuration."
        elsif error.message.include?("Model not found")
          raise "Model '#{@model}' not available. Please use a valid model."
        else
          raise "OpenAI API error: #{error.message}"
        end
      end

      def log_request(messages)
        Rails.logger.info "=" * 50
        Rails.logger.info "OpenAI API Request:"
        Rails.logger.info "Model: #{@model}"
        Rails.logger.info "Timeout: #{@timeout}s"
        Rails.logger.info "Messages count: #{messages.size}"
        Rails.logger.info "First message: #{messages.first.inspect}" if messages.any?
      end
    end
  end
end
