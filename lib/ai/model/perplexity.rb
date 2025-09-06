# lib/ai/model/perplexity.rb
require "httparty"
require "json"

module Ai
  module Model
    class Perplexity
      include HTTParty

      base_uri "https://api.perplexity.ai"
      default_timeout 300
      format :json
      debug_output $stdout if defined?(Rails) && Rails.env.development?

      def initialize(api_key: Settings.reload!.apis.perplexity.api_key,
                     model: "sonar-pro",
                     temperature: 0.7,
                     max_tokens: 16384,
                     append_references: true) # 👈 novo
        @api_key = api_key
        @model = model
        @temperature = temperature
        @max_tokens = max_tokens
        @append_references = append_references

        raise "Perplexity API key is missing" if @api_key.nil? || @api_key.empty?

        @default_options = {
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{@api_key}",
            "Accept" => "application/json"
          },
          timeout: 300,
          verify: true
        }
      end

      # ---------- PÚBLICOS ----------

      # Single-turn (com suporte a batches)
      def ask(prompt, system_message: nil, max_batch_attempts: 5)
        messages = build_messages(prompt, system_message)

        # 1ª chamada
        response = post_chat(messages: messages, stream: false)
        parsed = parse_response(response)

        full_text = parsed[:text]
        all_citations = parsed[:citations] # 👈 coleta inicial
        batch_count = 1

        gpt5 = Ai::Model::Gpt5.new
        response_divided_in_batches = gpt5.has_batches?(full_text)

        while response_divided_in_batches && batch_count < max_batch_attempts
          log_info("Detectado batch #{batch_count}, continuando...")

          continuation_messages = build_continuation_messages(messages, full_text)

          begin
            response = post_chat(messages: continuation_messages, stream: false)
            continuation_parsed = parse_response(response)

            new_content = continuation_parsed[:text]
            full_text += new_content

            # 👇 junta citações (dedup por URL, mantendo ordem)
            all_citations = merge_citations(all_citations, continuation_parsed[:citations])

            batch_count += 1
            response_divided_in_batches = gpt5.has_batches?(full_text)
            sleep(0.5)
          rescue => e
            log_error("Erro ao buscar batch #{batch_count}: #{e.message}")
            break
          end
        end

        if batch_count >= max_batch_attempts
          log_error("Atingido limite máximo de batches (#{max_batch_attempts})")
        end

        # 👇 Anexa referências se habilitado
        if @append_references && all_citations.any?
          full_text = append_references_section(full_text, all_citations)
        end

        log_info("Resposta completa recebida em #{batch_count} batch(es)")

        {
          text: full_text,
          usage: parsed[:usage],
          batch_count: batch_count,
          citations: all_citations
        }
      end

      # Streaming (coleta search_results e envia refs no final)
      def ask_stream(prompt, system_message: nil, &block)
        messages = build_messages(prompt, system_message)
        collected_citations = []

        post_chat_stream(messages: messages) do |event|
          # event => { done:, content:, full_response: } (e possivelmente :raw para JSON bruto)
          if event[:done]
            if @append_references && collected_citations.any?
              refs = build_references(event[:content], collected_citations)
              # emite bloco final com referências
              yield({ done: false, content: "\n\n#{refs}", full_response: event[:full_response].to_s + "\n\n#{refs}" }) if block_given?
            end
            yield(event) if block_given? # done:true
          else
            # tenta extrair citações quando o SSE vier com json completo (alguns envios incluem search_results)
            if event[:raw].is_a?(Hash) && event[:raw]["search_results"].is_a?(Array)
              collected_citations = merge_citations(collected_citations, normalize_search_results(event[:raw]["search_results"]))
            end
            yield(event) if block_given?
          end
        end
      end

      def ask_with_context(messages)
        response = post_chat(messages: messages, stream: false)
        parsed = parse_response(response)
        parsed[:text] = append_references_section(parsed[:text], parsed[:citations]) if @append_references && parsed[:citations].any?
        parsed
      end

      def ask_with_context_stream(messages, &block)
        collected_citations = []
        post_chat_stream(messages: messages) do |event|
          if event[:done]
            if @append_references && collected_citations.any?
              refs = build_references(event[:content], collected_citations)
              yield({ done: false, content: "\n\n#{refs}", full_response: event[:full_response].to_s + "\n\n#{refs}" }) if block_given?
            end
            yield(event) if block_given?
          else
            if event[:raw].is_a?(Hash) && event[:raw]["search_results"].is_a?(Array)
              collected_citations = merge_citations(collected_citations, normalize_search_results(event[:raw]["search_results"]))
            end
            yield(event) if block_given?
          end
        end
      end

      private

      attr_reader :api_key, :model, :temperature, :max_tokens, :default_options

      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", content: system_message } if system_message
        msgs << { role: "user", content: prompt }
        msgs
      end

      def build_continuation_messages(original_messages, partial_response)
        continuation_messages = original_messages.dup
        continuation_messages << { role: "assistant", content: partial_response }
        continuation_messages << {
          role: "user",
          content: "Continue your previous response. Please complete the remaining content. Respond strictly in English."
        }
        continuation_messages
      end

      # ---------- HTTP ----------

      def post_chat(messages:, stream: false, retries: 3)
        payload = {
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          messages: messages,
          stream: stream
        }

        options = @default_options.merge(body: payload.to_json)
        log_request(messages)

        attempt = 0
        begin
          attempt += 1
          response = self.class.post("/chat/completions", options)
          log_response(response)
          handle_response(response)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          if attempt < retries
            wait_time = 2 ** attempt
            log_error("Timeout error (attempt #{attempt}/#{retries}). Retrying in #{wait_time} seconds...")
            sleep(wait_time)
            retry
          else
            raise "Perplexity API Error: Request timeout after #{retries} attempts. The API might be slow or unavailable."
          end
        rescue HTTParty::Error => e
          raise "Perplexity API Error: HTTParty error - #{e.message}"
        rescue => e
          raise "Perplexity API Error: Unexpected error - #{e.class}: #{e.message}"
        end
      end

      # SSE streaming
      def post_chat_stream(messages:, &block)
        require "net/http"
        require "uri"

        uri = URI.parse("#{self.class.base_uri}/chat/completions")

        payload = {
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          messages: messages,
          stream: true
        }

        log_request(messages)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) do |http|
          request = Net::HTTP::Post.new(uri.path)
          request["Content-Type"] = "application/json"
          request["Authorization"] = "Bearer #{@api_key}"
          request["Accept"] = "text/event-stream"
          request.body = payload.to_json

          http.request(request) do |response|
            if response.code != "200"
              error_body = response.read_body
              raise "Perplexity API Error: #{response.code} - #{error_body}"
            end

            buffer = ""
            full_response = ""

            response.read_body do |chunk|
              buffer += chunk
              while (line_end = buffer.index("\n\n"))
                line = buffer[0..line_end - 1]
                buffer = buffer[line_end + 2..-1]
                next if line.empty?

                if line.start_with?("data: ")
                  data = line[6..-1]
                  if data == "[DONE]"
                    yield({ done: true, content: full_response, full_response: full_response }) if block_given?
                    break
                  end

                  begin
                    parsed = JSON.parse(data)

                    # 1) delta de conteúdo incremental
                    if parsed.dig("choices", 0, "delta", "content")
                      content = parsed["choices"][0]["delta"]["content"]
                      full_response += content
                      yield({ done: false, content: content, full_response: full_response, raw: parsed }) if block_given?
                    else
                      # 2) alguns servidores enviam "content" completo no chunk
                      if parsed.dig("choices", 0, "message", "content")
                        content = parsed["choices"][0]["message"]["content"]
                        full_response = content # substitui pelo completo
                        yield({ done: false, content: content, full_response: full_response, raw: parsed }) if block_given?
                      else
                        # mesmo sem conteúdo, ainda pode conter search_results
                        yield({ done: false, content: "", full_response: full_response, raw: parsed }) if block_given?
                      end
                    end
                  rescue JSON::ParserError
                    log_error("Failed to parse SSE data: #{data}")
                  end
                end
              end
            end

            { text: full_response, usage: {} }
          end
        end
      rescue => e
        log_error("Stream error: #{e.message}")
        raise "Perplexity API Streaming Error: #{e.message}"
      end

      # ---------- PARSE & CITAÇÕES ----------

      def handle_response(response)
        raise "Perplexity API Error: No response received from server" if response.nil?

        case response.code
        when 200
          raise "Perplexity API Error: Response body is empty or invalid JSON" if response.parsed_response.nil?
          response.parsed_response
        when 401
          raise "Perplexity API Error: Unauthorized - Invalid API key. Please check your API key in Settings."
        when 403
          raise "Perplexity API Error: Forbidden - You don't have access to this model or resource."
        when 429
          raise "Perplexity API Error: Rate limit exceeded. Please wait before making more requests."
        when 500..599
          raise "Perplexity API Error: Server error (#{response.code}) - The Perplexity API is experiencing issues. Please try again later."
        else
          error_message = response.parsed_response&.dig("error", "message") || response.message || "Unknown error"
          raise "Perplexity API Error: #{response.code} - #{error_message}"
        end
      end

      def parse_response(response)
        raise "Error parsing Perplexity response: Response is nil" if response.nil?
        raise "Error parsing Perplexity response: Expected Hash, got #{response.class}" unless response.is_a?(Hash)

        choices = response["choices"]
        raise "Error parsing Perplexity response: Invalid or empty choices array" if !choices.is_a?(Array) || choices.empty?

        content = choices[0]&.dig("message", "content")
        raise "Error parsing Perplexity response: No content in response" if content.nil?

        citations = []
        # 👇 API oficial expõe as fontes em 'search_results'
        if response["search_results"].is_a?(Array)
          citations = normalize_search_results(response["search_results"])
        end

        # fallback: algumas libs colocam em message["citations"]
        if citations.empty? && choices[0]&.dig("message", "citations").is_a?(Array)
          citations = normalize_search_results(choices[0]["message"]["citations"])
        end

        {
          text: content,
          usage: response["usage"] || {},
          citations: citations
        }
      rescue => e
        log_error("Parse error: #{e.message}")
        log_error("Response was: #{response.inspect}")
        raise
      end

      def normalize_search_results(array)
        array.filter_map do |r|
          next unless r.is_a?(Hash)
          url = r["url"] || r["source"] # alguns retornam 'source'
          next if url.nil? || url.empty?
          {
            "title" => r["title"].to_s.strip.empty? ? url : r["title"],
            "url"   => url,
            "date"  => r["date"]
          }
        end
      end

      def merge_citations(existing, incoming)
        return existing if incoming.nil? || incoming.empty?
        have = existing.map { |c| c["url"] }.compact.to_set
        merged = existing.dup
        incoming.each { |c| merged << c unless have.include?(c["url"]) }
        merged
      end

      def append_references_section(text, citations)
        refs_block = build_references(text, citations)
        return text if refs_block.nil? || refs_block.empty?
        "#{text}\n\n#{refs_block}"
      end

      def build_references(text, citations)
        return "" if citations.nil? || citations.empty?

        # quais índices foram citados (ex.: [1], [4], ...)
        used_indices = text.to_s.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq.sort
        list =
          if used_indices.any?
            used_indices.filter_map do |i|
              c = citations[i - 1] # 1-based no texto, 0-based no array
              next unless c
              format_ref_line(i, c)
            end
          else
            # se não houver [n] no corpo, lista todas em ordem
            citations.each_with_index.map { |c, idx| format_ref_line(idx + 1, c) }
          end

        return "" if list.empty?
        [
          "---",
          "## References",
          *list
        ].join("\n")
      end

      def format_ref_line(index, c)
        date = c["date"] ? " (#{c["date"]})" : ""
        "[#{index}] #{c["title"]} — #{c["url"]}#{date}"
      end

      # ---------- LOG ----------

      def log_request(messages)
        return unless defined?(Rails)
        Rails.logger.info "=" * 50
        Rails.logger.info "Perplexity API Request:"
        Rails.logger.info "URL: #{self.class.base_uri}/chat/completions"
        Rails.logger.info "Model: #{model}"
        Rails.logger.info "Temperature: #{temperature}"
        Rails.logger.info "Max Tokens: #{max_tokens}"
        Rails.logger.info "Messages count: #{messages.size}"
        Rails.logger.info "First message: #{messages.first.inspect}" if messages.any?
      end

      def log_response(response)
        return unless defined?(Rails)
        Rails.logger.info "Perplexity API Response:"
        Rails.logger.info "Status: #{response.code}"
        Rails.logger.info "Success: #{response.success?}"
        if response.code != 200
          Rails.logger.error "Error response body: #{response.body}"
        else
          Rails.logger.info "Response has choices: #{response.parsed_response&.key?('choices')}"
          Rails.logger.info "Response has search_results: #{response.parsed_response&.key?('search_results')}"
        end
      end

      def log_error(message)
        defined?(Rails) ? Rails.logger.error(message) : puts("ERROR: #{message}")
      end

      def log_info(message)
        defined?(Rails) ? Rails.logger.info(message) : puts("INFO: #{message}")
      end
    end
  end
end
