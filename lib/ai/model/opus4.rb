require "anthropic"

module Ai
  module Model
    class Opus4
      include Ai::Model::Logging

      DEFAULT_SYSTEM_MESSAGE = "You are a helpful, concise, and knowledgeable assistant. Always respond clearly and accurately, prioritizing brand strategy context."

      def initialize(system_message: DEFAULT_SYSTEM_MESSAGE)
        @client = Anthropic::Client.new(api_key: Settings.reload!.apis.anthropic.api_key)
        @system_message = system_message
        log_info(__method__, "Inicializando Opus4 com system_message=#{@system_message.inspect}")
      end

      def ask(question, system_message: nil, &block)
        log_debug(__method__, "Pergunta recebida: #{question.inspect}")
        full_response = ""

        @client.messages.stream(
          model: "claude-opus-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [ { role: "user", content: question } ]
        ).each do |chunk|
          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk
            log_debug(__method__, "Chunk recebido: #{text_chunk.inspect}")
            block.call(text_chunk, full_response) if block_given?
          end
        end

        log_info(__method__, "Resposta finalizada com #{full_response.size} caracteres")
        { text: full_response, response: full_response }
      rescue => e
        log_error(__method__, e)
        raise
      end

      def ask_with_context(question, previous_response_id:, system_message: nil, &block)
        log_debug(__method__, "Pergunta com contexto recebida: #{question.inspect}")
        full_response = ""
        response_id = nil

        @client.messages.stream(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [ { role: "user", content: question } ]
        ).each do |chunk|
          if chunk.is_a?(Anthropic::Models::RawMessageStartEvent)
            response_id = chunk.message[:id]
            log_info(__method__, "Streaming iniciado com response_id=#{response_id}")
          end

          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk
            log_debug(__method__, "Chunk recebido: #{text_chunk.inspect}")
            block.call(text_chunk, full_response) if block_given?
          end
        end

        log_info(__method__, "Resposta com contexto finalizada, tamanho=#{full_response.size}")
        { id: response_id, text: full_response, response: full_response }
      rescue => e
        log_error(__method__, e)
        raise
      end

      private

      def ask_without_streaming(question, system_message: nil)
        log_info(__method__, "Executando sem streaming para pergunta=#{question.inspect}")
        response = @client.messages.create(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [ { role: "user", content: question } ]
        )

        text_response = response.content.first.text
        log_info(__method__, "Resposta sem streaming recebida (#{text_response.size} caracteres)")
        { text: text_response, response: text_response }
      rescue => e
        log_error(__method__, e)
        raise
      end

      def ask_with_context_without_streaming(question, previous_response_id:, system_message: nil)
        log_info(__method__, "Executando sem streaming com contexto, pergunta=#{question.inspect}")
        response = @client.messages.create(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [ { role: "user", content: question } ]
        )

        text_response = response.content.first.text
        log_info(__method__, "Resposta com contexto sem streaming recebida")
        { id: response.id, text: text_response, response: text_response }
      rescue => e
        log_error(__method__, e)
        raise
      end

      public

      def stream_response(params, &block)
        log_info(__method__, "Iniciando stream_response com params=#{params.inspect}")
        full_response = ""
        response_id = nil

        @client.messages.stream(**params).each do |chunk|
          if chunk.is_a?(Anthropic::Models::RawMessageStartEvent)
            response_id = chunk.message[:id]
            log_info(__method__, "Streaming iniciado com response_id=#{response_id}")
          end

          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk
            log_debug(__method__, "Chunk recebido: #{text_chunk.inspect}")
            block.call(text_chunk, full_response, response_id) if block_given?
          end
        end

        log_info(__method__, "Streaming finalizado, total=#{full_response.size} caracteres")
        { id: response_id, text: full_response }
      rescue => e
        log_error(__method__, e)
        raise
      end

      def ask_with_conversation(messages, system_message: nil, stream: true, &block)
        log_info(__method__, "Pergunta com conversa iniciada (stream=#{stream})")
        if stream
          ask_with_conversation_streaming(messages, system_message: system_message, &block)
        else
          ask_with_conversation_without_streaming(messages, system_message: system_message)
        end
      end

      private

      def ask_with_conversation_streaming(messages, system_message: nil, &block)
        log_info(__method__, "Streaming de conversa iniciado")
        full_response = ""
        response_id = nil

        @client.messages.stream(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: messages
        ).each do |chunk|
          if chunk.is_a?(Anthropic::Models::RawMessageStartEvent)
            response_id = chunk.message[:id]
            log_info(__method__, "Streaming iniciado com response_id=#{response_id}")
          end

          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk
            log_debug(__method__, "Chunk recebido: #{text_chunk.inspect}")
            block.call(text_chunk, full_response) if block_given?
          end
        end

        log_info(__method__, "Streaming de conversa finalizado")
        { id: response_id, text: full_response }
      rescue => e
        log_error(__method__, e)
        raise
      end

      def ask_with_conversation_without_streaming(messages, system_message: nil)
        log_info(__method__, "Conversa sem streaming iniciada")
        response = @client.messages.create(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: messages
        )

        log_info(__method__, "Resposta de conversa sem streaming recebida")
        { id: response.id, text: response.content.first.text }
      rescue => e
        log_error(__method__, e)
        raise
      end
    end
  end
end
