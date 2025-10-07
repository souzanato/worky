require "httparty"
require "json"

module Ai
  module Model
    class Gemini15
      include HTTParty
      include Ai::Model::Logging

      base_uri "https://generativelanguage.googleapis.com/v1beta"
      default_timeout 300
      format :json
      debug_output $stdout if defined?(Rails) && Rails.env.development?

      def initialize(api_key: Settings.reload!.apis.gemini.api_key,
                     model: "gemini-1.5-pro",
                     temperature: 0.7,
                     max_tokens: 8192,
                     append_references: false)
        @api_key = api_key
        @model = model
        @temperature = temperature
        @max_tokens = max_tokens
        @append_references = append_references

        raise "Gemini API key is missing" if @api_key.nil? || @api_key.empty?

        @default_options = {
          headers: {
            "Content-Type" => "application/json",
            "Accept" => "application/json"
          },
          timeout: 300,
          verify: true
        }

        log_info(__method__, "Inicializando Gemini com modelo=#{@model}, max_tokens=#{@max_tokens}")
      end

      def ask(prompt, action, system_message: nil, max_batch_attempts: 10, sse: nil)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Prompt recebido: #{prompt.inspect}")

        response = post_chat(messages: messages, action: action, stream: false)
        parsed = parse_response(response)

        { text: parsed[:text], usage: parsed[:usage], citations: [] }
      end

      def ask_stream(prompt, system_message: nil, &block)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Iniciando streaming para prompt: #{prompt.inspect}")

        post_chat_stream(messages: messages) do |event|
          yield(event) if block_given?
        end
      end

      def ask_with_context(messages)
        log_debug(__method__, "Pergunta com contexto: #{messages.inspect}")
        response = post_chat(messages: messages, stream: false)
        parse_response(response)
      end

      def ask_with_context_stream(messages, &block)
        log_debug(__method__, "Pergunta com contexto + streaming: #{messages.inspect}")
        post_chat_stream(messages: messages) do |event|
          yield(event) if block_given?
        end
      end

      def transcribe(file_path)
        response = self.class.post(
          "/#{@model}:generateContent?key=#{@api_key}",
          headers: { "Content-Type" => "application/json" },
          body: {
            contents: [ {
              role: "user",
              parts: [
                { text: "Transcreva este áudio de forma clara e completa." },
                { inline_data: { mime_type: mime_type_for(file_path), data: Base64.strict_encode64(File.read(file_path)) } }
              ]
            } ]
          }.to_json
        )

        JSON.parse(response.body)
      end

      private

      attr_reader :api_key, :model, :temperature, :max_tokens, :default_options

      def mime_type_for(path)
        ext = File.extname(path).downcase
        case ext
        when ".mp3"  then "audio/mpeg"
        when ".wav"  then "audio/wav"
        when ".m4a"  then "audio/mp4"
        when ".ogg"  then "audio/ogg"
        else "application/octet-stream"
        end
      end

      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", parts: [ { text: system_message } ] } if system_message
        msgs << { role: "user", parts: [ { text: prompt } ] }
        msgs
      end

      def post_chat(messages:, action: nil, stream: false, retries: 3)
        uri = "/models/#{model}:generateContent?key=#{api_key}"
        payload = {
          contents: messages,
          generationConfig: {
            temperature: temperature,
            maxOutputTokens: max_tokens
          }
        }

        options = @default_options.merge(body: payload.to_json)
        log_request(messages)

        attempt = 0
        begin
          attempt += 1
          response = self.class.post(uri, options)
          log_response(response)
          handle_response(response)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          if attempt < retries
            wait_time = 2 ** attempt
            log_warn(__method__, "Timeout (tentativa #{attempt}/#{retries}), retry em #{wait_time}s")
            sleep(wait_time)
            retry
          else
            log_error(__method__, e)
            raise "Gemini API Error: Request timeout after #{retries} attempts."
          end
        rescue HTTParty::Error => e
          log_error(__method__, e)
          raise "Gemini API Error: HTTParty error - #{e.message}"
        rescue => e
          log_error(__method__, e)
          raise "Gemini API Error: Unexpected error - #{e.class}: #{e.message}"
        end
      end

      def post_chat_stream(messages:, &block)
        require "net/http"
        require "uri"
        uri = URI.parse("#{self.class.base_uri}/models/#{model}:streamGenerateContent?key=#{api_key}")

        payload = {
          contents: messages,
          generationConfig: {
            temperature: temperature,
            maxOutputTokens: max_tokens
          }
        }
        log_request(messages)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) do |http|
          request = Net::HTTP::Post.new(uri.request_uri)
          request["Content-Type"] = "application/json"
          request["Accept"] = "text/event-stream"
          request.body = payload.to_json

          http.request(request) do |response|
            if response.code != "200"
              raise "Gemini API Error: #{response.code} - #{response.body}"
            end

            full_response = ""
            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                next if line.strip.empty? || !line.start_with?("data:")

                data = line[5..-1].strip
                next if data == "[DONE]"

                begin
                  parsed = JSON.parse(data)
                  content = parsed.dig("candidates", 0, "content", "parts", 0, "text")
                  if content
                    full_response += content
                    yield({ done: false, content: content, full_response: full_response, raw: parsed }) if block_given?
                  end
                rescue JSON::ParserError
                  log_warn(__method__, "Falha ao parsear SSE: #{data.inspect}")
                end
              end
            end
            yield({ done: true, content: full_response, full_response: full_response }) if block_given?
          end
        end
      rescue => e
        log_error(__method__, e)
        raise "Gemini API Streaming Error: #{e.message}"
      end

      def handle_response(response)
        raise "Gemini API Error: No response" if response.nil?

        case response.code
        when 200
          raise "Gemini API Error: Invalid JSON" if response.parsed_response.nil?
          response.parsed_response
        when 400
          raise "Gemini API Error: Bad request"
        when 401
          raise "Gemini API Error: Unauthorized - Invalid API key"
        when 429
          raise "Gemini API Error: Rate limit exceeded"
        when 500..599
          raise "Gemini API Error: Server error #{response.code}"
        else
          msg = response.parsed_response&.dig("error", "message") || response.message
          raise "Gemini API Error: #{response.code} - #{msg}"
        end
      end

      def parse_response(response)
        log_debug(__method__, "Parsing response: #{response.inspect}")
        raise "Error parsing Gemini response: nil" if response.nil?

        candidates = response["candidates"]
        raise "Error parsing Gemini response: Invalid candidates" if !candidates.is_a?(Array) || candidates.empty?

        content = candidates[0].dig("content", "parts", 0, "text")
        raise "Error parsing Gemini response: No content" if content.nil?

        { text: content, usage: response["usageMetadata"] || {} }
      end

      def log_request(messages)
        log_info(__method__, "=" * 50)
        log_info(__method__, "Gemini API Request")
        log_info(__method__, "Model: #{model}")
        log_info(__method__, "Temperature: #{temperature}")
        log_info(__method__, "Max Tokens: #{max_tokens}")
        log_info(__method__, "Messages count: #{messages.size}")
      end

      def log_response(response)
        log_info(__method__, "Gemini API Response: HTTP #{response.code}, success=#{response.success?}")
        if response.code != 200
          log_warn(__method__, "Error response body: #{response.body}")
        else
          log_debug(__method__, "Resposta recebida com sucesso")
        end
      end
    end
  end
end
