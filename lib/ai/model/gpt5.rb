# lib/ai/model/gpt5.rb
module Ai
  module Model
    class Gpt5
      DEFAULT_TIMEOUT = 300  # 5 minutos
      DEFAULT_MODEL = "gpt-5"  # Modelo atual (GPT-5 ainda não existe)

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
              max_tokens: max_tokens,
              reasoning_effort: "minimal", # mais rápido
              verbosity: "low"            # mais direto
              # temperature: temperature,
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
              max_tokens: max_tokens,
              reasoning_effort: "minimal",
              verbosity: "low"
              # temperature: temperature,
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
              # temperature: temperature,
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
        prompt = <<-markdown
          # TASK
          You are a specialized detector.#{'  '}
          Your task is to analyze the given text and decide if it indicates that the response is split into multiple batches, parts, or continuations.#{'  '}

          # CRITERIA
          - Look for signals such as explicit mentions of *batch*, *part*, *segment*, *continued*, *next section*, or any structured phrasing that implies the output is incomplete and more content will follow.#{'  '}
          - Ignore domain-specific words (e.g., “signals”, “items”, “pages”).#{'  '}
          - Focus only on whether the text suggests continuation in another batch/part.#{'  '}
          - Do not provide explanations.#{'  '}

          # OUTPUT FORMAT
          Respond strictly with one of the following values:#{'  '}
          - `true` → if the text suggests there are additional batches/parts/continuations.#{'  '}
          - `false` → if the text appears to be complete.#{'  '}

          # INPUT
          #{content}
        markdown

        messages = [
          {
            "role": "user",
            "content": prompt
          }
        ]

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
                      response_text: {
                        type: :string,
                        description: "The raw response text from Perplexity or another LLM"
                      }
                    },
                    required: [ "response_text" ]
                  }
                }
              }
            ],
            tool_choice: "required"
          },
        )

        message = response.dig("choices", 0, "message")

        if message["role"] == "assistant" && message["tool_calls"]
          messages << message

          message["tool_calls"].each do |tool_call|
            tool_call_id = tool_call.dig("id")
            function_name = tool_call.dig("function", "name")
            function_args = JSON.parse(tool_call.dig("function", "arguments"), symbolize_names: true)

            function_response =
              case function_name
              when "detect_batches"
                detect_batches(**function_args) # => true ou false (boolean)
              end

            messages << {
              tool_call_id: tool_call_id,
              role: "tool",
              name: function_name,
              content: function_response.to_s   # 👈 garante string "true"/"false"
            }
          end

          second_response = @client.chat(
            parameters: {
              model: "gpt-4o",
              messages: messages
            }
          )

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
