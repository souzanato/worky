module Ai
  module Model
    class Gpt4o
      include Ai::Model::Logging

      DEFAULT_TIMEOUT = 300  # 5 minutos
      DEFAULT_MODEL = "gpt-4o"  # Modelo atual (GPT-5 ainda não existe)

      def initialize(timeout: DEFAULT_TIMEOUT, model: DEFAULT_MODEL)
        @model = model
        @timeout = timeout

        log_info(__method__, "Inicializando Gpt4o com modelo=#{@model}, timeout=#{@timeout}s")

        @client = OpenAI::Client.new(
          access_token: Settings.reload!.apis.openai.access_token,
          request_timeout: timeout,
          log_errors: Rails.env.development?
        )
      end

      def ask(prompt, system_message: nil, temperature: 0.7, max_tokens: nil)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Prompt recebido: #{prompt.inspect}")

        begin
          log_request(messages)

          response = @client.chat(
            parameters: {
              model: @model,
              messages: messages,
              temperature: temperature,
              max_tokens: max_tokens
            }.compact
          )

          log_info(__method__, "Resposta recebida do modelo #{@model}")
          parse_response(response)
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_with_context(messages, temperature: 0.7, max_tokens: nil)
        log_debug(__method__, "Mensagens recebidas: #{messages.inspect}")

        begin
          log_request(messages)

          response = @client.chat(
            parameters: {
              model: @model,
              messages: messages,
              temperature: temperature,
              max_tokens: max_tokens
            }.compact
          )

          log_info(__method__, "Resposta recebida com contexto do modelo #{@model}")
          parse_response(response)
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_stream(prompt, system_message: nil, temperature: 0.7, &block)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Iniciando streaming para prompt: #{prompt.inspect}")

        begin
          log_request(messages)
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
                  log_debug(__method__, "Chunk recebido: #{content.inspect}")
                  yield({ done: false, content: content, full_response: full_response }) if block_given?
                elsif chunk.dig("choices", 0, "finish_reason")
                  log_info(__method__, "Streaming finalizado")
                  yield({ done: true, content: full_response }) if block_given?
                end
              end
            }
          )

          { text: full_response }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_with_context_stream(messages, temperature: 0.7, &block)
        log_debug(__method__, "Iniciando streaming com contexto: #{messages.inspect}")

        begin
          log_request(messages)
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
                  log_debug(__method__, "Chunk recebido: #{content.inspect}")
                  yield({ done: false, content: content, full_response: full_response }) if block_given?
                elsif chunk.dig("choices", 0, "finish_reason")
                  log_info(__method__, "Streaming finalizado")
                  yield({ done: true, content: full_response }) if block_given?
                end
              end
            }
          )

          { text: full_response }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def test_connection
        log_info(__method__, "Testando conexão com API OpenAI")
        response = @client.models.list
        log_info(__method__, "Modelos disponíveis: #{response['data'].map { |m| m['id'] }}")
        { success: true, models: response["data"].map { |m| m["id"] } }
      rescue => e
        log_error(__method__, e)
        { success: false, error: e.message }
      end

      private

      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", content: system_message } if system_message
        msgs << { role: "user", content: prompt }
        log_debug(__method__, "Mensagens construídas: #{msgs.inspect}")
        msgs
      end

      def parse_response(response)
        log_debug(__method__, "Parsing response: #{response.inspect}")

        if response.is_a?(Hash)
          content = response.dig("choices", 0, "message", "content")
          usage = response["usage"]

          result = {
            text: content,
            usage: usage || {},
            model: response["model"],
            finish_reason: response.dig("choices", 0, "finish_reason")
          }
          log_info(__method__, "Parse concluído com sucesso")
          result
        else
          raise "Unexpected response format: #{response.class}"
        end
      rescue => e
        log_error(__method__, e)
        raise
      end

      def handle_timeout_error(error)
        log_error(__method__, error)
        raise "OpenAI API timeout after #{@timeout} seconds. Consider using streaming for long responses."
      end

      def handle_general_error(error)
        log_error(__method__, error)

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
        log_info(__method__, "=" * 50)
        log_info(__method__, "OpenAI API Request")
        log_info(__method__, "Model: #{@model}")
        log_info(__method__, "Timeout: #{@timeout}s")
        log_info(__method__, "Messages count: #{messages.size}")
        log_debug(__method__, "First message: #{messages.first.inspect}") if messages.any?
      end
    end
  end
end
