require "anthropic"

module Ai
  module Model
    class Opus4
      include Ai::Model::Logging

      DEFAULT_SYSTEM_MESSAGE = "You are a helpful, concise, and knowledgeable assistant. Always respond clearly and accurately, prioritizing brand strategy context."
      MAX_BATCH_ATTEMPTS = 10

      def initialize(system_message: DEFAULT_SYSTEM_MESSAGE)
        @client = Anthropic::Client.new(api_key: Settings.reload!.apis.anthropic.api_key)
        @system_message = system_message
        log_info(__method__, "Inicializando Opus4 com system_message=#{@system_message.inspect}")
      end

      def ask(question, action, sse: nil, system_message: nil, &block)
        log_debug(__method__, "Pergunta recebida: #{question.inspect}")

        enhanced_question = should_use_batch?(question) ? question + batch_prompt : question

        if sse
          ask_with_batch_streaming(enhanced_question, action, sse: sse, system_message: system_message, &block)
        else
          ask_with_batch(enhanced_question, action, system_message: system_message, sse: sse)
        end
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

      # ======================================================
      # 🚨 Checagem semântica com GPT5-Nano
      # ======================================================
      def semantic_completion_check(original_prompt, partial_response)
        nano = Ai::Model::Gpt5Nano.new

        check_prompt = <<~PROMPT
          You are a semantic evaluator.
          Compare the ORIGINAL PROMPT and the PARTIAL RESPONSE.

          ORIGINAL PROMPT:
          #{original_prompt}

          PARTIAL RESPONSE:
          #{partial_response}

          TASK:
          1. Determine if the response fully satisfies the original prompt requirements.
          2. If incomplete, identify which sections or elements are missing.
          3. Output ONLY valid JSON in the following format:

          {
            "complete": true|false,
            "missing_sections": ["..."]
          }
        PROMPT

        result = nano.ask(check_prompt, nil, system_message: "You are a strict JSON validator.")
        JSON.parse(result[:text]) rescue { "complete" => false, "missing_sections" => [ "semantic check failed" ] }
      end

      def ask_with_batch(question, action, system_message: nil, sse: nil)
        log_info(__method__, "Iniciando processamento em batch sem streaming")

        messages = [ { role: "user", content: question } ]
        full_response = ""
        responses = []
        batch_count = 0

        loop do
          batch_count += 1
          break if batch_count > MAX_BATCH_ATTEMPTS

          log_info(__method__, "Processando batch #{batch_count}/#{MAX_BATCH_ATTEMPTS}")
          sse.write({ progress: 60 + batch_count, message: "Processing batch #{batch_count}..." }, event: "status") if sse

          payload = build_payload(messages, action, system_message)
          response = @client.messages.create(**payload)
          batch_text = response.content.first.text
          batch_text = clean_continuation_content(full_response, batch_text) if batch_count > 1

          full_response += batch_text
          responses << response

          # ✅ Verificação semântica
          check = semantic_completion_check(question, full_response)
          if !check["complete"]
            log_info(__method__, "Semantic check: incompleto, faltando #{check['missing_sections']}")
            messages = build_continuation_messages(messages, batch_text)
            sleep(0.5)
            next
          else
            log_info(__method__, "Semantic check: resposta completa")
            break
          end
        end

        { text: full_response, response: full_response, batch_count: batch_count, responses: responses }
      rescue => e
        log_error(__method__, e)
        raise
      end

      def ask_with_batch_streaming(question, action, sse: nil, system_message: nil, &block)
        log_info(__method__, "Iniciando processamento em batch com streaming")

        messages = [ { role: "user", content: question } ]
        full_response = ""
        batch_count = 0

        loop do
          batch_count += 1
          break if batch_count > MAX_BATCH_ATTEMPTS

          log_info(__method__, "Processando batch #{batch_count}/#{MAX_BATCH_ATTEMPTS} com streaming")
          sse.write({ progress: 60 + batch_count, message: "Processing batch #{batch_count}..." }, event: "status") if sse && batch_count > 1

          payload = build_payload(messages, action, system_message)
          batch_response = ""

          @client.messages.stream(**payload).each do |chunk|
            if chunk.is_a?(Anthropic::Helpers::Streaming::TextEvent)
              text_chunk = chunk.text
              text_chunk = clean_first_chunk(full_response, text_chunk) if batch_count > 1 && batch_response.empty? && full_response.length > 0
              batch_response += text_chunk
              full_response += text_chunk
              log_debug(__method__, "Chunk do batch #{batch_count}: #{text_chunk.inspect}")
              block.call(text_chunk, full_response) if block_given?
            end
          end

          # ✅ Verificação semântica
          check = semantic_completion_check(question, full_response)
          if !check["complete"]
            log_info(__method__, "Semantic check: incompleto, faltando #{check['missing_sections']}")
            messages = build_continuation_messages(messages, batch_response)
            sleep(0.5)
            next
          else
            log_info(__method__, "Semantic check: resposta completa")
            break
          end
        end

        { text: full_response, response: full_response, batch_count: batch_count }
      rescue => e
        log_error(__method__, e)
        raise
      end

      # ======================================================
      # Restante dos métodos auxiliares (sem mudanças)
      # ======================================================

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
        { id: response.id, text: response.content.first.text }
      rescue => e
        log_error(__method__, e)
        raise
      end

      def batch_prompt
        "\n\n---\n\n## Response Management\n\n**IMPORTANT - Batch Continuation Protocol**: Due to the comprehensive nature of this analysis, if you need to continue:\n- End ONLY with: **\"Continue in next batch...\"** (exact text)\n- Do NOT add this phrase unless you actually need to continue\n- Do NOT use phrases like \"Continue if further...\" or \"May continue...\"\n- If analysis is complete, end naturally without continuation phrases"
      end

      def should_use_batch?(question)
        indicators = [
          /comprehensive/i, /detailed analysis/i, /complete report/i,
          /full assessment/i, /extensive/i, /pestle/i,
          /swot/i, /market analysis/i
        ]
        text = question.downcase
        indicators.any? { |p| text.match?(p) } || question.length > 500
      end

      def build_continuation_messages(original_messages, partial_response)
        continuation = original_messages.dup
        continuation << { role: "assistant", content: partial_response }
        continuation << { role: "user", content: "The response is incomplete. Please continue exactly from where you stopped, without repeating previous content." }
        continuation
      end

      def build_payload(messages, action, system_message)
        payload = {
          model: "claude-opus-4-20250514",
          max_tokens: 8000,
          temperature: 0.7,
          system: system_message || @system_message,
          messages: messages
        }
        payload.merge!(action.ai_action.custom_attributes) if action&.ai_action&.custom_attributes&.is_a?(Hash)
        payload
      end

      def clean_continuation_content(previous_text, new_content)
        return new_content if previous_text.nil? || new_content.nil?
        [ 200, 100, 50 ].each do |len|
          last = previous_text.slice(-len..-1)
          return new_content[last.strip.length..-1].strip if last && new_content.start_with?(last.strip)
        end
        new_content
      end

      def clean_first_chunk(previous_text, chunk)
        return chunk if previous_text.nil? || chunk.nil?
        [ 50, 25, 10 ].each do |len|
          last = previous_text.slice(-len..-1)
          return chunk[last.strip.length..-1] if last && chunk.start_with?(last.strip)
        end
        chunk
      end
    end
  end
end
