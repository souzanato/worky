require "net/http"
require "uri"
require "json"

module Ai
  module Model
    class Grok
      include Ai::Model::Logging

      DEFAULT_TIMEOUT = 300  # 5 minutos
      DEFAULT_MODEL = "grok-4"
      BASE_URL = "https://api.x.ai"

      def initialize(timeout: DEFAULT_TIMEOUT, model: DEFAULT_MODEL)
        @model = model
        @timeout = timeout
        @api_key = Settings.reload!.apis.xai.api_key
        @base_uri = URI(BASE_URL)

        log_info(__method__, "Inicializando Grok com modelo=#{@model}, timeout=#{@timeout}s")
      end

      def ask(prompt, system_message: nil, temperature: 0.7, max_tokens: nil, stream: true)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Prompt recebido: #{prompt.inspect}")

        begin
          log_request(messages)
          if stream
            ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens)
          else
            ask_without_stream(messages, temperature: temperature, max_tokens: max_tokens)
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_with_context(messages, temperature: 0.7, max_tokens: nil, stream: true)
        log_debug(__method__, "Mensagens recebidas: #{messages.inspect}")

        begin
          log_request(messages)
          if stream
            ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens)
          else
            ask_without_stream(messages, temperature: temperature, max_tokens: max_tokens)
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_stream(prompt, system_message: nil, temperature: 0.7, max_tokens: nil, &block)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Iniciando streaming para prompt: #{prompt.inspect}")

        begin
          log_request(messages)
          ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens, &block)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def ask_with_context_stream(messages, temperature: 0.7, max_tokens: nil, &block)
        log_debug(__method__, "Iniciando streaming com contexto: #{messages.inspect}")

        begin
          log_request(messages)
          ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens, &block)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def test_connection
        log_info(__method__, "Testando conexão com API Grok")
        uri = URI("#{BASE_URL}/v1/models")
        http = create_http_client(uri)

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"

        response = http.request(request)
        if response.code == "200"
          data = JSON.parse(response.body)
          log_info(__method__, "Modelos disponíveis: #{data['data'].map { |m| m['id'] }}")
          { success: true, models: data["data"].map { |m| m["id"] } }
        else
          log_error(__method__, "HTTP #{response.code}: #{response.body}")
          { success: false, error: "HTTP #{response.code}: #{response.body}" }
        end
      rescue => e
        log_error(__method__, e)
        { success: false, error: e.message }
      end

      def detect_batches(response_text:)
        log_debug(__method__, "Verificando batches no texto: #{response_text&.slice(0, 80)}...")

        return false if response_text.nil? || response_text.strip.empty?
        text = response_text.downcase

        patterns = [
          "[batch end – continue in next batch]",
          "[batch start]",
          /\bbatch\s*\d+/i,
          /\[\s*batch\s*\d+.*?\]/i,
          /next\s+batch/i,
          /the\s+next\s+batch/i,
          /following\s+batch/i,
          /further\s+batches/i,
          /batch\s*\(\d+\s*[-–]\s*\d+\)/i,
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
          /\(\s*\d+\s*[-–]\s*\d+\s*\)/,
          /\d+\s*[-–]\s*\d+\s*(signals|items|entries|results|pages)?/i,
          /\.\.\.$/,
          /the\s+next\s+\w+\s+will\s+follow/i
        ]

        found = patterns.any? { |pattern| pattern.is_a?(Regexp) ? text.match?(pattern) : text.include?(pattern) }
        log_info(__method__, "Batch detectado? #{found}")
        found
      end

      def has_batches?(content)
        log_debug(__method__, "Analisando conteúdo para batches (tamanho=#{content&.size})")

        prompt = <<-MARKDOWN
          # TASK
          You are a specialized detector.#{'  '}
          Your task is to analyze the given text and decide if it indicates that the response is split into multiple batches, parts, or continuations.#{'  '}

          # CRITERIA
          - Look for signals such as explicit mentions of *batch*, *part*, *segment*, *continued*, *next section*, or any structured phrasing that implies the output is incomplete and more content will follow.#{'  '}
          - Ignore domain-specific words (e.g., "signals", "items", "pages").#{'  '}
          - Focus only on whether the text suggests continuation in another batch/part.#{'  '}
          - Do not provide explanations.#{'  '}

          # OUTPUT FORMAT
          Respond strictly with one of the following values:#{'  '}
          - `true`#{'  '}
          - `false`#{'  '}

          # INPUT
          #{content}
        MARKDOWN

        messages = [ { "role" => "user", "content" => prompt } ]
        payload = {
          model: @model,
          messages: messages,
          tools: [
            {
              type: "function",
              function: {
                name: "detect_batches",
                description: "Check if a given response text indicates batched output",
                parameters: {
                  type: "object",
                  properties: {
                    response_text: { type: "string", description: "The raw response text" }
                  },
                  required: [ "response_text" ]
                }
              }
            }
          ],
          tool_choice: "required"
        }

        response = make_request("/v1/chat/completions", payload)
        message = response.dig("choices", 0, "message")

        if message["role"] == "assistant" && message["tool_calls"]
          log_info(__method__, "Tool call detect_batches disparada")
          messages << message

          message["tool_calls"].each do |tool_call|
            tool_call_id = tool_call.dig("id")
            function_name = tool_call.dig("function", "name")
            function_args = JSON.parse(tool_call.dig("function", "arguments"))

            function_response =
              case function_name
              when "detect_batches"
                detect_batches(response_text: function_args["response_text"])
              end

            messages << {
              tool_call_id: tool_call_id,
              role: "tool",
              name: function_name,
              content: function_response.to_s
            }
          end

          second_response = make_request("/v1/chat/completions", { model: @model, messages: messages })
          result = second_response.dig("choices", 0, "message", "content") == "true"
          log_info(__method__, "Resultado final batches? #{result}")
          result
        end
      end

      private

      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", content: system_message } if system_message
        msgs << { role: "user", content: prompt }
        log_debug(__method__, "Mensagens construídas: #{msgs.inspect}")
        msgs
      end

      def ask_without_stream(messages, temperature: 0.7, max_tokens: nil)
        payload = { model: @model, messages: messages, temperature: temperature, stream: false }
        payload[:max_tokens] = max_tokens if max_tokens
        log_info(__method__, "Enviando requisição sem streaming")
        response = make_request("/v1/chat/completions", payload)
        parse_response(response)
      end

      def ask_stream_internal(messages, temperature: 0.7, max_tokens: nil, &block)
        payload = { model: @model, messages: messages, temperature: temperature, stream: true }
        payload[:max_tokens] = max_tokens if max_tokens
        log_info(__method__, "Enviando requisição com streaming")

        full_response = ""
        make_streaming_request("/v1/chat/completions", payload) do |chunk_data|
          if chunk_data["choices"] && chunk_data["choices"][0]
            choice = chunk_data["choices"][0]
            if choice["delta"] && choice["delta"]["content"]
              content = choice["delta"]["content"]
              full_response += content
              log_debug(__method__, "Chunk recebido: #{content.inspect}")
              yield({ done: false, content: content, full_response: full_response }) if block_given?
            elsif choice["finish_reason"]
              log_info(__method__, "Streaming finalizado")
              yield({ done: true, content: full_response }) if block_given?
            end
          end
        end

        { text: full_response }
      end

      def create_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = 10
        http.write_timeout = 10
        http
      end

      def make_request(endpoint, payload)
        uri = URI("#{BASE_URL}#{endpoint}")
        http = create_http_client(uri)

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = payload.to_json

        response = http.request(request)
        if response.code.start_with?("2")
          log_info(__method__, "Resposta recebida com sucesso HTTP #{response.code}")
          JSON.parse(response.body)
        else
          log_error(__method__, "HTTP #{response.code}: #{response.body}")
          raise "HTTP #{response.code}: #{response.body}"
        end
      end

      def make_streaming_request(endpoint, payload, &block)
        uri = URI("#{BASE_URL}#{endpoint}")
        http = create_http_client(uri)

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "text/event-stream"
        request["Cache-Control"] = "no-cache"
        request.body = payload.to_json

        http.request(request) do |response|
          if response.code.start_with?("2")
            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                next if line.strip.empty?
                if line.start_with?("data: ")
                  data_content = line[6..-1]
                  next if data_content.strip == "[DONE]"
                  begin
                    chunk_data = JSON.parse(data_content)
                    log_debug(__method__, "Streaming chunk parseado: #{chunk_data.inspect}")
                    yield(chunk_data) if block_given?
                  rescue JSON::ParserError
                    log_warn(__method__, "Chunk inválido ignorado: #{data_content}")
                  end
                end
              end
            end
          else
            log_error(__method__, "HTTP #{response.code}: #{response.body}")
            raise "HTTP #{response.code}: #{response.body}"
          end
        end
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
        raise "Grok API timeout after #{@timeout} seconds. Consider using streaming for long responses."
      end

      def handle_general_error(error)
        log_error(__method__, error)

        if error.message.include?("Rate limit") || error.message.include?("429")
          raise "Grok rate limit exceeded. Please wait and try again."
        elsif error.message.include?("Invalid API key") || error.message.include?("401")
          raise "Invalid Grok API key. Please check your configuration."
        elsif error.message.include?("Model not found") || error.message.include?("404")
          raise "Model '#{@model}' not available. Please use a valid model."
        else
          raise "Grok API error: #{error.message}"
        end
      end

      def log_request(messages)
        log_info(__method__, "=" * 50)
        log_info(__method__, "Grok API Request")
        log_info(__method__, "Model: #{@model}")
        log_info(__method__, "Timeout: #{@timeout}s")
        log_info(__method__, "Messages count: #{messages.size}")
        log_debug(__method__, "First message: #{messages.first.inspect}") if messages.any?
      end
    end
  end
end
