# lib/ai/model/grok.rb
require "net/http"
require "uri"
require "json"

module Ai
  module Model
    class Grok
      DEFAULT_TIMEOUT = 300  # 5 minutos
      DEFAULT_MODEL = "grok-4"  # Modelo padrão do Grok
      BASE_URL = "https://api.x.ai"

      def initialize(timeout: DEFAULT_TIMEOUT, model: DEFAULT_MODEL)
        @model = model
        @timeout = timeout
        @api_key = Settings.apis.xai.api_key
        @base_uri = URI(BASE_URL)
      end

      # Pergunta única (sem contexto) - usa streaming por padrão
      def ask(prompt, system_message: nil, temperature: 0.7, max_tokens: nil, stream: true)
        messages = build_messages(prompt, system_message)

        begin
          log_request(messages) if Rails.env.development?

          if stream
            ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens)
          else
            ask_without_stream(messages, temperature: temperature, max_tokens: max_tokens)
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Pergunta com contexto (sessão) - usa streaming por padrão
      def ask_with_context(messages, temperature: 0.7, max_tokens: nil, stream: true)
        begin
          log_request(messages) if Rails.env.development?

          if stream
            ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens)
          else
            ask_without_stream(messages, temperature: temperature, max_tokens: max_tokens)
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Pergunta com streaming explícito
      def ask_stream(prompt, system_message: nil, temperature: 0.7, max_tokens: nil, &block)
        messages = build_messages(prompt, system_message)

        begin
          log_request(messages) if Rails.env.development?

          ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens, &block)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Pergunta com contexto e streaming explícito
      def ask_with_context_stream(messages, temperature: 0.7, max_tokens: nil, &block)
        begin
          log_request(messages) if Rails.env.development?

          ask_stream_internal(messages, temperature: temperature, max_tokens: max_tokens, &block)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          handle_timeout_error(e)
        rescue => e
          handle_general_error(e)
        end
      end

      # Método para testar a conexão
      def test_connection
        uri = URI("#{BASE_URL}/v1/models")
        http = create_http_client(uri)

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"

        response = http.request(request)

        if response.code == "200"
          data = JSON.parse(response.body)
          { success: true, models: data["data"].map { |m| m["id"] } }
        else
          { success: false, error: "HTTP #{response.code}: #{response.body}" }
        end
      rescue => e
        { success: false, error: e.message }
      end

      # Definição da função que será chamada via tool_call
      def detect_batches(response_text:)
        return false if response_text.nil? || response_text.strip.empty?

        text = response_text.downcase

        patterns = [
          # --- Marcadores fixos do prompt ---
          "[batch end – continue in next batch]", # fim de um batch
          "[batch start]",                        # início de um batch

          # --- Batch markers clássicos ---
          /\bbatch\s*\d+/i,                      # "Batch 1"
          /\[\s*batch\s*\d+.*?\]/i,              # "[Batch 1: ...]"
          /next\s+batch/i,                       # "next batch"
          /the\s+next\s+batch/i,                 # "The next batch"
          /following\s+batch/i,                  # "following batch"
          /further\s+batches/i,                  # "further batches"
          /batch\s*\(\d+\s*[-–]\s*\d+\)/i,       # "batch (26–50)"

          # --- Part markers ---
          /\bpart\s*\d+/i,                       # "Part 1"
          /\bpart\s+\d+\s+of\s+\d+/i,            # "part 1 of 3"
          /next\s+part/i,                        # "next part"
          /following\s+part/i,                   # "following part"
          /\bto\s+be\s+continued\b/i,            # "to be continued"

          # --- Idiomas comuns ---
          /\bpróximo\s+lote\b/i,                 # pt-br
          /\bcontinuación\b/i,                   # es
          /\bà\s+suivre\b/i,                     # fr

          # --- Expressões de continuação ---
          /continue\s+(in|with|to)\s+/i,         # "continue in next..."
          /\bmore\s+to\s+come\b/i,               # "more to come"
          /\bcontinued\b/i,                      # "continued"

          # --- Ranges numéricos ---
          /\(\s*\d+\s*[-–]\s*\d+\s*\)/,          # "(26-50)"
          /\d+\s*[-–]\s*\d+\s*(signals|items|entries|results|pages)?/i,

          # --- Incompletude textual ---
          /\.\.\.$/,                             # termina com "..."
          /the\s+next\s+\w+\s+will\s+follow/i    # "the next batch will follow"
        ]

        patterns.any? do |pattern|
          pattern.is_a?(Regexp) ? text.match?(pattern) : text.include?(pattern)
        end
      end

      def has_batches?(content)
        # Configuração do chat com a function
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
          - `true` → if the text suggests there are additional batches/parts/continuations.#{'  '}
          - `false` → if the text appears to be complete.#{'  '}

          # INPUT
          #{content}
        MARKDOWN

        messages = [
          {
            "role" => "user",
            "content" => prompt
          }
        ]

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
                    response_text: {
                      type: "string",
                      description: "The raw response text from Perplexity or another LLM"
                    }
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
          messages << message

          message["tool_calls"].each do |tool_call|
            tool_call_id = tool_call.dig("id")
            function_name = tool_call.dig("function", "name")
            function_args = JSON.parse(tool_call.dig("function", "arguments"))

            function_response = case function_name
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

          second_payload = {
            model: @model,
            messages: messages
          }

          second_response = make_request("/v1/chat/completions", second_payload)
          second_response.dig("choices", 0, "message", "content") == "true"
        end
      end

      private

      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", content: system_message } if system_message
        msgs << { role: "user", content: prompt }
        msgs
      end

      def ask_without_stream(messages, temperature: 0.7, max_tokens: nil)
        payload = {
          model: @model,
          messages: messages,
          temperature: temperature,
          stream: false
        }
        payload[:max_tokens] = max_tokens if max_tokens

        response = make_request("/v1/chat/completions", payload)
        parse_response(response)
      end

      def ask_stream_internal(messages, temperature: 0.7, max_tokens: nil, &block)
        payload = {
          model: @model,
          messages: messages,
          temperature: temperature,
          stream: true
        }
        payload[:max_tokens] = max_tokens if max_tokens

        full_response = ""

        make_streaming_request("/v1/chat/completions", payload) do |chunk_data|
          if chunk_data["choices"] && chunk_data["choices"][0]
            choice = chunk_data["choices"][0]

            if choice["delta"] && choice["delta"]["content"]
              content = choice["delta"]["content"]
              full_response += content

              if block_given?
                yield({ done: false, content: content, full_response: full_response })
              end
            elsif choice["finish_reason"]
              if block_given?
                yield({ done: true, content: full_response })
              end
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
          JSON.parse(response.body)
        else
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
              # Parse Server-Sent Events format
              chunk.split("\n").each do |line|
                next if line.strip.empty?

                if line.start_with?("data: ")
                  data_content = line[6..-1] # Remove "data: "
                  next if data_content.strip == "[DONE]"

                  begin
                    chunk_data = JSON.parse(data_content)
                    yield(chunk_data) if block_given?
                  rescue JSON::ParserError
                    # Skip invalid JSON chunks
                  end
                end
              end
            end
          else
            raise "HTTP #{response.code}: #{response.body}"
          end
        end
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
        Rails.logger.error "Error parsing Grok response: #{e.message}"
        raise
      end

      def handle_timeout_error(error)
        Rails.logger.error "Grok API timeout after #{@timeout} seconds: #{error.message}"
        raise "Grok API timeout after #{@timeout} seconds. Consider using streaming for long responses."
      end

      def handle_general_error(error)
        Rails.logger.error "Grok API error: #{error.message}"
        Rails.logger.error error.backtrace.join("\n") if Rails.env.development?

        # Tratar erros específicos da API
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
        Rails.logger.info "=" * 50
        Rails.logger.info "Grok API Request:"
        Rails.logger.info "Model: #{@model}"
        Rails.logger.info "Timeout: #{@timeout}s"
        Rails.logger.info "Messages count: #{messages.size}"
        Rails.logger.info "First message: #{messages.first.inspect}" if messages.any?
      end
    end
  end
end
