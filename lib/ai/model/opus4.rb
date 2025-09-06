# lib/ai/model/opus4.rb
require "anthropic"

module Ai
  module Model
    class Opus4
      DEFAULT_SYSTEM_MESSAGE = "You are a helpful, concise, and knowledgeable assistant. Always respond clearly and accurately, prioritizing brand strategy context."

      def initialize(system_message: DEFAULT_SYSTEM_MESSAGE)
        @client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
        @system_message = system_message
      end

      # Single question (no context) - usa streaming obrigatoriamente
      def ask(question, system_message: nil, &block)
        full_response = ""

        @client.messages.stream(
          model: "claude-opus-4-20250514", # Corrigindo o modelo
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [
            { role: "user", content: question }
          ]
        ).each do |chunk|
          # Processa apenas os eventos de texto
          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk

            # Chama o block se fornecido para processar cada chunk
            block.call(text_chunk, full_response) if block_given?
          end
        end

        {
          text: full_response,
          response: full_response
        }
      end

      # Question with context (session) - usa streaming obrigatoriamente
      def ask_with_context(question, previous_response_id:, system_message: nil, &block)
        # NOTA: A API do Anthropic não suporta previous_response_id nativamente
        # Este parâmetro é mantido para compatibilidade, mas será ignorado
        # Para manter contexto, você precisa passar o histórico completo nas messages

        full_response = ""
        response_id = nil

        @client.messages.stream(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [
            { role: "user", content: question }
          ]
          # previous_response_id removido - não é suportado pela API
        ).each do |chunk|
          # Captura o ID da mensagem no início
          if chunk.is_a?(Anthropic::Models::RawMessageStartEvent)
            response_id = chunk.message[:id]
          end

          # Processa apenas os eventos de texto
          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk

            # Chama o block se fornecido para processar cada chunk
            block.call(text_chunk, full_response) if block_given?
          end
        end

        {
          id: response_id,
          text: full_response,
          response: full_response
        }
      end

      private

      # Métodos auxiliares para compatibilidade - versões não-streaming
      def ask_without_streaming(question, system_message: nil)
        response = @client.messages.create(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [
            { role: "user", content: question }
          ]
        )

        text_response = response.content.first.text
        {
          text: text_response,
          response: text_response
        }
      end

      def ask_with_context_without_streaming(question, previous_response_id:, system_message: nil)
        # NOTA: previous_response_id removido - não suportado pela API
        response = @client.messages.create(
          model: "claude-sonnet-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: [
            { role: "user", content: question }
          ]
        )

        text_response = response.content.first.text
        {
          id: response.id,
          text: text_response,
          response: text_response
        }
      end

      public

      # Método utilitário para processar streams de forma mais simples
      def stream_response(params, &block)
        full_response = ""
        response_id = nil

        @client.messages.stream(**params).each do |chunk|
          if chunk.is_a?(Anthropic::Models::RawMessageStartEvent)
            response_id = chunk.message[:id]
          end

          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk

            block.call(text_chunk, full_response, response_id) if block_given?
          end
        end

        {
          id: response_id,
          text: full_response
        }
      end

      # Método adicional para contexto real - passa histórico completo
      def ask_with_conversation(messages, system_message: nil, stream: true, &block)
        if stream
          ask_with_conversation_streaming(messages, system_message: system_message, &block)
        else
          ask_with_conversation_without_streaming(messages, system_message: system_message)
        end
      end

      private

      def ask_with_conversation_streaming(messages, system_message: nil, &block)
        full_response = ""
        response_id = nil

        @client.messages.stream(
          model: "claude-sonnet-4-20250514", # Será corrigido depois do teste
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: messages
        ).each do |chunk|
          if chunk.is_a?(Anthropic::Models::RawMessageStartEvent)
            response_id = chunk.message[:id]
          end

          if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
            text_chunk = chunk.text
            full_response += text_chunk

            block.call(text_chunk, full_response) if block_given?
          end
        end

        {
          id: response_id,
          text: full_response
        }
      end

      def ask_with_conversation_without_streaming(messages, system_message: nil)
        response = @client.messages.create(
          model: "claude-sonnet-4-20250514", # Será corrigido depois do teste
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: messages
        )

        {
          id: response.id,
          text: response.content.first.text
        }
      end
    end
  end
end
