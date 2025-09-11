require "httparty"
require "json"

module Ai
  module Model
    class Perplexity
      include HTTParty
      include Ai::Model::Logging

      base_uri "https://api.perplexity.ai"
      default_timeout 300
      format :json
      debug_output $stdout if defined?(Rails) && Rails.env.development?

      def initialize(api_key: Settings.reload!.apis.perplexity.api_key,
                     model: "sonar-pro",
                     temperature: 0.7,
                     max_tokens: 16384,
                     append_references: true)
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

        log_info(__method__, "Inicializando Perplexity com modelo=#{@model}, max_tokens=#{@max_tokens}, append_refs=#{@append_references}")
      end

      def ask(prompt, system_message: nil, max_batch_attempts: 5)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Prompt recebido: #{prompt.inspect}")

        response = post_chat(messages: messages, stream: false)
        parsed = parse_response(response)

        full_text = parsed[:text]
        all_citations = parsed[:citations]
        batch_count = 1

        gpt5 = Ai::Model::Gpt5.new
        response_divided_in_batches = gpt5.has_batches?(full_text)

        while response_divided_in_batches && batch_count < max_batch_attempts
          log_warn(__method__, "Detectado batch #{batch_count}, continuando...")

          continuation_messages = build_continuation_messages(messages, full_text)
          begin
            response = post_chat(messages: continuation_messages, stream: false)
            continuation_parsed = parse_response(response)
            new_content = continuation_parsed[:text]
            full_text += new_content
            all_citations = merge_citations(all_citations, continuation_parsed[:citations])

            batch_count += 1
            response_divided_in_batches = gpt5.has_batches?(full_text)
            sleep(0.5)
          rescue => e
            log_error(__method__, e)
            break
          end
        end

        if batch_count >= max_batch_attempts
          log_error(__method__, "Atingido limite máximo de batches (#{max_batch_attempts})")
        end

        if @append_references && all_citations.any?
          full_text = append_references_section(full_text, all_citations)
        end

        log_info(__method__, "Resposta completa recebida em #{batch_count} batch(es)")
        { text: full_text, usage: parsed[:usage], batch_count: batch_count, citations: all_citations }
      end

      def ask_stream(prompt, system_message: nil, &block)
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Iniciando streaming para prompt: #{prompt.inspect}")
        collected_citations = []

        post_chat_stream(messages: messages) do |event|
          if event[:done]
            if @append_references && collected_citations.any?
              refs = build_references(event[:content], collected_citations)
              log_info(__method__, "Referências anexadas ao streaming")
              yield({ done: false, content: "\n\n#{refs}", full_response: event[:full_response].to_s + "\n\n#{refs}" }) if block_given?
            end
            log_info(__method__, "Streaming finalizado")
            yield(event) if block_given?
          else
            if event[:raw].is_a?(Hash) && event[:raw]["search_results"].is_a?(Array)
              collected_citations = merge_citations(collected_citations, normalize_search_results(event[:raw]["search_results"]))
              log_debug(__method__, "Citações coletadas até agora: #{collected_citations.size}")
            end
            yield(event) if block_given?
          end
        end
      end

      def ask_with_context(messages)
        log_debug(__method__, "Pergunta com contexto: #{messages.inspect}")
        response = post_chat(messages: messages, stream: false)
        parsed = parse_response(response)
        parsed[:text] = append_references_section(parsed[:text], parsed[:citations]) if @append_references && parsed[:citations].any?
        parsed
      end

      def ask_with_context_stream(messages, &block)
        log_debug(__method__, "Pergunta com contexto + streaming: #{messages.inspect}")
        collected_citations = []
        post_chat_stream(messages: messages) do |event|
          if event[:done]
            if @append_references && collected_citations.any?
              refs = build_references(event[:content], collected_citations)
              log_info(__method__, "Referências anexadas ao streaming de contexto")
              yield({ done: false, content: "\n\n#{refs}", full_response: event[:full_response].to_s + "\n\n#{refs}" }) if block_given?
            end
            yield(event) if block_given?
          else
            if event[:raw].is_a?(Hash) && event[:raw]["search_results"].is_a?(Array)
              collected_citations = merge_citations(collected_citations, normalize_search_results(event[:raw]["search_results"]))
              log_debug(__method__, "Citações coletadas até agora: #{collected_citations.size}")
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
        log_debug(__method__, "Mensagens construídas: #{msgs.inspect}")
        msgs
      end

      def build_continuation_messages(original_messages, partial_response)
        continuation_messages = original_messages.dup
        continuation_messages << { role: "assistant", content: partial_response }
        continuation_messages << { role: "user", content: "Continue your previous response. Please complete the remaining content. Respond strictly in English." }
        log_debug(__method__, "Mensagens de continuação construídas")
        continuation_messages
      end

      def post_chat(messages:, stream: false, retries: 3)
        payload = { model: model, temperature: temperature, max_tokens: max_tokens, messages: messages, stream: stream }
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
            log_warn(__method__, "Timeout (tentativa #{attempt}/#{retries}), retry em #{wait_time}s")
            sleep(wait_time)
            retry
          else
            log_error(__method__, e)
            raise "Perplexity API Error: Request timeout after #{retries} attempts."
          end
        rescue HTTParty::Error => e
          log_error(__method__, e)
          raise "Perplexity API Error: HTTParty error - #{e.message}"
        rescue => e
          log_error(__method__, e)
          raise "Perplexity API Error: Unexpected error - #{e.class}: #{e.message}"
        end
      end

      def post_chat_stream(messages:, &block)
        require "net/http"
        require "uri"
        uri = URI.parse("#{self.class.base_uri}/chat/completions")

        payload = { model: model, temperature: temperature, max_tokens: max_tokens, messages: messages, stream: true }
        log_request(messages)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) do |http|
          request = Net::HTTP::Post.new(uri.path)
          request["Content-Type"] = "application/json"
          request["Authorization"] = "Bearer #{@api_key}"
          request["Accept"] = "text/event-stream"
          request.body = payload.to_json

          http.request(request) do |response|
            if response.code != "200"
              log_error(__method__, "Erro HTTP: #{response.code} - #{response.body}")
              raise "Perplexity API Error: #{response.code} - #{response.body}"
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
                    log_info(__method__, "Streaming SSE concluído")
                    yield({ done: true, content: full_response, full_response: full_response }) if block_given?
                    break
                  end

                  begin
                    parsed = JSON.parse(data)
                    if parsed.dig("choices", 0, "delta", "content")
                      content = parsed["choices"][0]["delta"]["content"]
                      full_response += content
                      log_debug(__method__, "Chunk SSE recebido: #{content.inspect}")
                      yield({ done: false, content: content, full_response: full_response, raw: parsed }) if block_given?
                    elsif parsed.dig("choices", 0, "message", "content")
                      content = parsed["choices"][0]["message"]["content"]
                      full_response = content
                      log_debug(__method__, "Resposta SSE completa recebida")
                      yield({ done: false, content: content, full_response: full_response, raw: parsed }) if block_given?
                    else
                      yield({ done: false, content: "", full_response: full_response, raw: parsed }) if block_given?
                    end
                  rescue JSON::ParserError
                    log_warn(__method__, "Falha ao parsear SSE: #{data.inspect}")
                  end
                end
              end
            end

            { text: full_response, usage: {} }
          end
        end
      rescue => e
        log_error(__method__, e)
        raise "Perplexity API Streaming Error: #{e.message}"
      end

      def handle_response(response)
        raise "Perplexity API Error: No response" if response.nil?

        case response.code
        when 200
          log_info(__method__, "Resposta HTTP 200 recebida")
          raise "Perplexity API Error: Invalid JSON" if response.parsed_response.nil?
          response.parsed_response
        when 401
          log_error(__method__, "Unauthorized 401")
          raise "Perplexity API Error: Unauthorized - Invalid API key."
        when 403
          raise "Perplexity API Error: Forbidden"
        when 429
          raise "Perplexity API Error: Rate limit exceeded"
        when 500..599
          raise "Perplexity API Error: Server error #{response.code}"
        else
          msg = response.parsed_response&.dig("error", "message") || response.message
          raise "Perplexity API Error: #{response.code} - #{msg}"
        end
      end

      def parse_response(response)
        log_debug(__method__, "Parsing response: #{response.inspect}")

        raise "Error parsing Perplexity response: nil" if response.nil?
        raise "Error parsing Perplexity response: Expected Hash, got #{response.class}" unless response.is_a?(Hash)

        choices = response["choices"]
        raise "Error parsing Perplexity response: Invalid choices" if !choices.is_a?(Array) || choices.empty?

        content = choices[0]&.dig("message", "content")
        raise "Error parsing Perplexity response: No content" if content.nil?

        citations = []
        if response["search_results"].is_a?(Array)
          citations = normalize_search_results(response["search_results"])
        elsif choices[0]&.dig("message", "citations").is_a?(Array)
          citations = normalize_search_results(choices[0]["message"]["citations"])
        end

        log_info(__method__, "Parse concluído, #{citations.size} citações extraídas")
        { text: content, usage: response["usage"] || {}, citations: citations }
      rescue => e
        log_error(__method__, e)
        raise
      end

      def normalize_search_results(array)
        array.filter_map do |r|
          next unless r.is_a?(Hash)
          url = r["url"] || r["source"]
          next if url.nil? || url.empty?
          { "title" => r["title"].to_s.strip.empty? ? url : r["title"], "url" => url, "date" => r["date"] }
        end
      end

      def merge_citations(existing, incoming)
        return existing if incoming.nil? || incoming.empty?
        have = existing.map { |c| c["url"] }.compact.to_set
        merged = existing.dup
        incoming.each { |c| merged << c unless have.include?(c["url"]) }
        log_debug(__method__, "Merge citations: antes=#{existing.size}, depois=#{merged.size}")
        merged
      end

      def append_references_section(text, citations)
        refs_block = build_references(text, citations)
        return text if refs_block.nil? || refs_block.empty?
        "#{text}\n\n#{refs_block}"
      end

      def build_references(text, citations)
        return "" if citations.nil? || citations.empty?
        used_indices = text.to_s.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq.sort
        list =
          if used_indices.any?
            used_indices.filter_map do |i|
              c = citations[i - 1]
              next unless c
              format_ref_line(i, c)
            end
          else
            citations.each_with_index.map { |c, idx| format_ref_line(idx + 1, c) }
          end
        return "" if list.empty?
        [ "---", "## References", *list ].join("\n")
      end

      def format_ref_line(index, c)
        date = c["date"] ? " (#{c["date"]})" : ""
        "[#{index}] #{c["title"]} — #{c["url"]}#{date}"
      end

      def log_request(messages)
        log_info(__method__, "=" * 50)
        log_info(__method__, "Perplexity API Request")
        log_info(__method__, "Model: #{model}")
        log_info(__method__, "Temperature: #{temperature}")
        log_info(__method__, "Max Tokens: #{max_tokens}")
        log_info(__method__, "Messages count: #{messages.size}")
        log_debug(__method__, "First message: #{messages.first.inspect}") if messages.any?
      end

      def log_response(response)
        log_info(__method__, "Perplexity API Response: HTTP #{response.code}, success=#{response.success?}")
        if response.code != 200
          log_error(__method__, "Error response body: #{response.body}")
        else
          log_debug(__method__, "Tem choices? #{response.parsed_response&.key?('choices')}, tem search_results? #{response.parsed_response&.key?('search_results')}")
        end
      end
    end
  end
end
