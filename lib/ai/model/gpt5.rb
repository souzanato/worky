module Ai
  module Model
    class Gpt5
      include Ai::Model::Logging

      DEFAULT_TIMEOUT = 600  # 10 minutos para reasoning models
      DEFAULT_MODEL = "gpt-5"
      MAX_BATCH_ITERATIONS = 10

      def initialize(timeout: DEFAULT_TIMEOUT, model: DEFAULT_MODEL)
        @model = model
        @timeout = timeout

        log_info(__method__, "Inicializando Gpt5 com modelo=#{@model}, timeout=#{@timeout}s")
        log_info(__method__, "⚠️  Reasoning models podem demorar muito! Use 'medium' ou 'low' para respostas mais rápidas.")

        @client = OpenAI::Client.new(
          access_token: Settings.reload!.apis.openai.access_token,
          request_timeout: timeout,
          log_errors: Rails.env.development?
        )
      end

      def ask(prompt, action, system_message: nil, temperature: 0.7, max_tokens: nil, force_minimal_effort: false, reasoning_effort: "minimal", auto_batches: true, sse: nil)
        if force_minimal_effort == true
          reasoning_effort = "minimal"
        else
          custom_attributes = action&.ai_action&.custom_attributes
          if custom_attributes.is_a?(Hash)
            new_reasoning_effort = custom_attributes&.dig("reasoning", "effort")
            reasoning_effort = new_reasoning_effort unless new_reasoning_effort.nil?
          end
        end

        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Prompt recebido: #{prompt.inspect}")
        log_info(__method__, "Reasoning effort: #{reasoning_effort}")

        sse.write({ progress: 60, message: "Prompt recebido..." }, event: "status") if sse
        sse.write({ progress: 60, message: "Reasoning effort: #{reasoning_effort}" }, event: "status") if sse

        if reasoning_effort == "high"
          log_info(__method__, "⚠️  AVISO: 'high' pode demorar muito (5-10 min). Considere 'medium' ou 'low'.")
          log_info(__method__, "⚠️  Para respostas rápidas, use ask_stream() em vez de ask().")
        end

        begin
          result = execute_with_batches(messages, max_tokens, reasoning_effort, auto_batches, action, sse)
          log_info(__method__, "Resposta completa recebida (#{result[:batch_count]} batch(es))")
          result
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e, reasoning_effort)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_with_context(messages, action, temperature: 0.7, max_tokens: nil, reasoning_effort: "minimal", auto_batches: true)
        log_debug(__method__, "Mensagens recebidas: #{messages.inspect}")
        log_info(__method__, "Reasoning effort: #{reasoning_effort}")

        if reasoning_effort == "high"
          log_info(__method__, "⚠️  AVISO: 'high' pode demorar muito. Considere 'medium' ou use streaming.")
        end

        begin
          result = execute_with_batches(messages, max_tokens, reasoning_effort, auto_batches, action)
          log_info(__method__, "Resposta completa com contexto recebida (#{result[:batch_count]} batch(es))")
          result
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e, reasoning_effort)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_stream(prompt, system_message: nil, temperature: 0.7, reasoning_effort: "minimal", &block)
        messages = build_messages(prompt, system_message)
        input_text = format_messages_as_input(messages)

        log_debug(__method__, "Iniciando streaming para prompt: #{prompt.inspect}")
        log_info(__method__, "Reasoning effort: #{reasoning_effort}")
        log_info(__method__, "✅ Streaming é recomendado para reasoning models!")

        begin
          log_request_responses_api(input_text)
          full_response = ""

          @client.responses.stream(
            parameters: {
              model: @model,
              input: input_text,
              reasoning: { effort: reasoning_effort }
            }
          ) do |chunk|
            # Processa os chunks do Responses API
            if chunk.is_a?(Hash) && chunk.dig("output")
              content = extract_text_from_output(chunk["output"])
              if content && !content.empty?
                full_response += content
                log_debug(__method__, "Chunk recebido: #{content.inspect}")
                yield({ done: false, content: content, full_response: full_response }) if block_given?
              end
            elsif chunk.is_a?(Hash) && chunk["type"] == "done"
              log_info(__method__, "Streaming finalizado")
              yield({ done: true, content: full_response }) if block_given?
            end
          end

          { text: full_response }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e, reasoning_effort)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_with_context_stream(messages, temperature: 0.7, reasoning_effort: "minimal", &block)
        input_text = format_messages_as_input(messages)

        log_debug(__method__, "Iniciando streaming com contexto: #{messages.inspect}")
        log_info(__method__, "Reasoning effort: #{reasoning_effort}")
        log_info(__method__, "✅ Streaming é recomendado para reasoning models!")

        begin
          log_request_responses_api(input_text)
          full_response = ""

          @client.responses.stream(
            parameters: {
              model: @model,
              input: input_text,
              reasoning: { effort: reasoning_effort }
            }
          ) do |chunk|
            if chunk.is_a?(Hash) && chunk.dig("output")
              content = extract_text_from_output(chunk["output"])
              if content && !content.empty?
                full_response += content
                log_debug(__method__, "Chunk recebido: #{content.inspect}")
                yield({ done: false, content: content, full_response: full_response }) if block_given?
              end
            elsif chunk.is_a?(Hash) && chunk["type"] == "done"
              log_info(__method__, "Streaming finalizado")
              yield({ done: true, content: full_response }) if block_given?
            end
          end

          { text: full_response }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e, reasoning_effort)
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

      def detect_batches(response_text:)
        log_debug(__method__, "Verificando batches no texto: #{response_text&.slice(0, 80)}...")

        return false if response_text.nil? || response_text.strip.empty?
        text = response_text.downcase

        patterns = [
          "[batch end — continue in next batch]",
          "[batch start]",
          /\bbatch\s*\d+/i,
          /\[\s*batch\s*\d+.*?\]/i,
          /next\s+batch/i,
          /the\s+next\s+batch/i,
          /following\s+batch/i,
          /further\s+batches/i,
          /batch\s*\(\d+\s*[-—]\s*\d+\)/i,
          /\bpart\s*\d+/i,
          /\bpart\s+\d+\s+of\s+\d+/i,
          /next\s+part/i,
          /following\s+part/i,
          /\bto\s+be\s+continued\b/i,
          /\bpróximo\s+lote\b/i,
          /\bcontinuación\b/i,
          /\bà\s+suivre\b/i,
          /continue\s+(in|with|to)\s+/i,
          /\bmore\s+to\s+come\b/i,
          /\bcontinued\b/i,
          /\(\s*\d+\s*[-—]\s*\d+\s*\)/,
          /\d+\s*[-—]\s*\d+\s*(signals|items|entries|results|pages)?/i,
          /\.\.\.$/,
          /the\s+next\s+\w+\s+will\s+follow/i
        ]

        found = patterns.any? { |pattern| pattern.is_a?(Regexp) ? text.match?(pattern) : text.include?(pattern) }
        log_info(__method__, "Batch detectado? #{found}")
        found
      end

      def has_batches?(content)
        log_debug(__method__, "Analisando conteúdo para batches (tamanho=#{content&.size})")

        prompt = <<-markdown
          # TASK
          You are a specialized detector.
          Your task is to analyze the given text and decide if it indicates that the response is split into multiple batches, parts, or continuations.

          # CRITERIA
          - Look for signals such as explicit mentions of *batch*, *part*, *segment*, *continued*, *next section*, or any structured phrasing that implies the output is incomplete and more content will follow.
          - Ignore domain-specific words (e.g., "signals", "items", "pages").
          - Focus only on whether the text suggests continuation in another batch/part.
          - Do not provide explanations.

          # OUTPUT FORMAT
          Respond strictly with one of the following values:
          - `true` → if the text suggests there are additional batches/parts/continuations.
          - `false` → if the text appears to be complete.

          # INPUT
          #{content}
        markdown

        messages = [ { role: "user", content: prompt } ]
        response = @client.chat(
          parameters: {
            model: "gpt-4o",
            messages: messages,
            tools: [
              {
                type: "function",
                function: {
                  name: "detect_batches",
                  description: "Check if a given response text indicates batched output",
                  parameters: {
                    type: :object,
                    properties: {
                      response_text: { type: :string, description: "The raw response text" }
                    },
                    required: [ "response_text" ]
                  }
                }
              }
            ],
            tool_choice: "required"
          }
        )

        message = response.dig("choices", 0, "message")
        if message["role"] == "assistant" && message["tool_calls"]
          log_info(__method__, "Tool call detect_batches disparada")
          messages << message

          message["tool_calls"].each do |tool_call|
            tool_call_id = tool_call.dig("id")
            function_name = tool_call.dig("function", "name")
            function_args = JSON.parse(tool_call.dig("function", "arguments"), symbolize_names: true)

            function_response =
              case function_name
              when "detect_batches"
                detect_batches(**function_args)
              end

            messages << {
              tool_call_id: tool_call_id,
              role: "tool",
              name: function_name,
              content: function_response.to_s
            }
          end

          second_response = @client.chat(parameters: { model: "gpt-4o", messages: messages })
          result = second_response.dig("choices", 0, "message", "content") == "true"
          log_info(__method__, "Resultado final batches? #{result}")
          result
        end
      end

      private

      def execute_with_batches(messages, max_tokens, reasoning_effort, auto_batches, action, sse)
        start_time = Time.now
        accumulated_text = ""
        accumulated_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
        batch_count = 0
        current_input = format_messages_as_input(messages)
        previous_response_id = nil
        progress = 60
        previous_response_id = nil

        loop do
          batch_start_time = Time.now
          batch_count += 1
          progress += 1
          sse.write({ progress: progress, message: "Executando batch ##{batch_count}" }, event: "status") if sse
          log_info(__method__, "Executando batch ##{batch_count}")

          if batch_count > MAX_BATCH_ITERATIONS
            log_error(__method__, "Limite de batches atingido (#{MAX_BATCH_ITERATIONS})")
            break
          end

          log_request_responses_api(current_input)

          params = {
            model: @model,
            input: current_input,
            reasoning: { effort: reasoning_effort }
          }

          params[:max_output_tokens] = max_tokens if max_tokens
          params[:previous_response_id] = previous_response_id if previous_response_id

          response = @client.responses.create(parameters: params)

          parsed = parse_responses_response(response)
          accumulated_text += parsed[:text] || ""
          previous_response_id = response["id"]

          # Acumula usage
          if parsed[:usage]
            accumulated_usage[:prompt_tokens] += parsed[:usage]["input_tokens"] || 0
            accumulated_usage[:completion_tokens] += parsed[:usage]["output_tokens"] || 0
            accumulated_usage[:total_tokens] = accumulated_usage[:prompt_tokens] + accumulated_usage[:completion_tokens]
          end

          # Verifica se deve continuar com batches
          unless auto_batches
            log_info(__method__, "Auto-batches desabilitado, retornando resultado único")
            break
          end

          has_more_batches = detect_batches(response_text: parsed[:text])

          unless has_more_batches
            sse.write({ progress: progress, message: "Nenhum batch adicional detectado, finalizando..." }, event: "status") if sse
            log_info(__method__, "Nenhum batch adicional detectado, finalizando")
            break
          end

          sse.write({ progress: progress, message: "Batch detectado! Solicitando próximo batch..." }, event: "status") if sse
          log_info(__method__, "Batch detectado! Solicitando próximo batch...")

          # Para continuar com Responses API, usamos previous_response_id
          current_input = "Por favor, continue com o próximo batch."

          # Pequeno delay para evitar rate limit
          sleep(0.5)
        end

        # tempo total de execução
        accumulated_usage[:execution_seconds] = Time.now - start_time

        {
          text: accumulated_text,
          usage: accumulated_usage,
          model: @model,
          batch_count: batch_count,
          reasoning_effort: reasoning_effort,
          finish_reason: "completed_with_batches"
        }
      end


      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", content: system_message } if system_message
        msgs << { role: "user", content: prompt }
        log_debug(__method__, "Mensagens construídas: #{msgs.inspect}")
        msgs
      end

      def format_messages_as_input(messages)
        # Responses API usa "input" como string ou array de objetos de conteúdo
        # Vamos concatenar as mensagens em formato de conversa
        messages.map do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]
          "#{role}: #{content}"
        end.join("\n\n")
      end

      def extract_text_from_output(output)
        log_debug(__method__, "Extraindo texto de output: #{output.inspect}")

        return "" unless output.is_a?(Array)

        result = output.map do |item|
          next unless item.is_a?(Hash)

          # Tenta diferentes estruturas possíveis
          if item["content"].is_a?(Array)
            # Formato: { "content": [{ "type": "text", "text": "..." }] }
            item["content"].map do |content_item|
              if content_item.is_a?(Hash)
                content_item["text"] || content_item[:text]
              end
            end.compact.join
          elsif item["content"].is_a?(String)
            # Formato: { "content": "texto direto" }
            item["content"]
          elsif item["text"].is_a?(String)
            # Formato: { "text": "texto direto" }
            item["text"]
          elsif item[:text].is_a?(String)
            # Formato com símbolos: { text: "texto direto" }
            item[:text]
          end
        end.compact.join

        log_debug(__method__, "Texto extraído (#{result.size} chars): #{result[0..100]}...")
        result
      end

      def parse_responses_response(response)
        log_debug(__method__, "=" * 50)
        log_debug(__method__, "DEBUGGING RESPONSE STRUCTURE:")
        log_debug(__method__, "Response keys: #{response.keys.inspect}")
        log_debug(__method__, "Output type: #{response['output'].class}")
        log_debug(__method__, "Output: #{response['output'].inspect}")
        log_debug(__method__, "=" * 50)

        if response.is_a?(Hash)
          # Responses API retorna { "output": [...], "usage": {...} }
          text = extract_text_from_output(response["output"])

          if text.nil? || text.empty?
            log_error(__method__, "❌ TEXTO VAZIO! Tentando extração alternativa...")
            log_error(__method__, "Response completa: #{response.inspect}")

            # Tenta extração direta
            if response["output"].is_a?(Array) && response["output"].first
              first_item = response["output"].first
              log_debug(__method__, "Primeiro item: #{first_item.inspect}")

              # Tenta pegar qualquer texto encontrado
              text = first_item.to_s if text.empty?
            end
          end

          usage = response["usage"]

          result = {
            text: text,
            usage: usage || {},
            model: response["model"],
            finish_reason: response["status"]
          }

          log_info(__method__, "Parse concluído - Texto: #{text&.size || 0} chars")
          result
        else
          raise "Unexpected response format: #{response.class}"
        end
      rescue => e
        log_error(__method__, e)
        log_error(__method__, "Response que causou erro: #{response.inspect}")
        raise
      end

      def handle_timeout_error(error, reasoning_effort = nil)
        log_error(__method__, error)

        suggestion = if reasoning_effort == "high"
          "GPT-5 com reasoning='high' pode demorar 5-10 minutos! Sugestões:\n" \
          "1. Use reasoning_effort: 'medium' ou 'low' para respostas mais rápidas\n" \
          "2. Use ask_stream() para ver o progresso em tempo real\n" \
          "3. Aumente o timeout: Gpt5.new(timeout: 900) # 15 minutos"
        else
          "Timeout após #{@timeout} segundos. Sugestões:\n" \
          "1. Use ask_stream() para respostas longas\n" \
          "2. Aumente o timeout ao inicializar: Gpt5.new(timeout: 900)"
        end

        raise "OpenAI API timeout. #{suggestion}"
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
        log_info(__method__, "OpenAI Chat API Request")
        log_info(__method__, "Model: #{@model}")
        log_info(__method__, "Timeout: #{@timeout}s")
        log_info(__method__, "Messages count: #{messages.size}")
        log_debug(__method__, "First message: #{messages.first.inspect}") if messages.any?
      end

      def log_request_responses_api(input)
        log_info(__method__, "=" * 50)
        log_info(__method__, "OpenAI Responses API Request")
        log_info(__method__, "Model: #{@model}")
        log_info(__method__, "Timeout: #{@timeout}s")
        log_debug(__method__, "Input preview: #{input&.slice(0, 200)}...")
      end
    end
  end
end
