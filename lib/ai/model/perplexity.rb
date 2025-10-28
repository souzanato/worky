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

      def ask(prompt, action, system_message: nil, max_batch_attempts: 10, sse: nil)  # Aumentado para 10
        messages = build_messages(prompt, system_message)
        log_debug(__method__, "Prompt recebido: #{prompt.inspect}")


        response = post_chat(messages: messages, action: action, stream: false)
        parsed = parse_response(response)
        full_text = parsed[:text]
        all_citations = parsed[:citations]
        batch_count = 1

        sse.write({ progress: 60, message: "PROMPT INICIAL: #{prompt}" }, event: "status") if sse
        sse.write({ progress: 60, message: "RESULT INICIAL: #{full_text} #{all_citations}" }, event: "status") if sse

        # Verificação mais inteligente de continuação
        needs_continuation = should_continue?(full_text)
        log_info(__method__, "Primeira resposta - precisa continuar? #{needs_continuation} (length: #{full_text&.length || 0})")

        progress = 61
        sse.write({ progress: progress, message: "Starting batch processing..." }, event: "status") if sse and needs_continuation
        while needs_continuation && batch_count < max_batch_attempts
          sse.write({ progress: progress, message: "Processing batch #{batch_count + 1}..." }, event: "status") if sse

          log_warn(__method__, "Iniciando batch #{batch_count + 1} de #{max_batch_attempts}")

          continuation_messages = build_continuation_messages(messages, full_text)

          begin
            response = post_chat(messages: continuation_messages, action: action, stream: false)
            continuation_parsed = parse_response(response)
            new_content = continuation_parsed[:text]

            sse.write({ progress: 60, message: "PROMPT #{batch_count}: #{prompt}" }, event: "status") if sse
            sse.write({ progress: 60, message: "RESULT #{batch_count}: #{full_text} #{all_citations}" }, event: "status") if sse

            # Verifica se o novo conteúdo é substancial
            if new_content.strip.length < 100
              log_warn(__method__, "Conteúdo de continuação muito curto (#{new_content.strip.length} chars), parando")
              break
            end

            # Limpa possível duplicação
            new_content = clean_continuation_content(full_text, new_content)

            # Adiciona o novo conteúdo
            full_text += new_content
            all_citations = merge_citations(all_citations, continuation_parsed[:citations])

            batch_count += 1

            # Reavalia se precisa continuar com lógica melhorada
            needs_continuation = should_continue?(new_content) && !response_seems_complete?(full_text)

            log_info(__method__, "Batch #{batch_count} concluído - precisa continuar? #{needs_continuation} (total length: #{full_text&.length || 0})")

            # Para evitar loops infinitos, verifica se houve progresso significativo
            if new_content.strip.length < 200
              log_warn(__method__, "Progresso limitado detectado, verificando se deve parar")
              if response_seems_complete?(full_text)
                log_info(__method__, "Resposta parece completa, parando continuação")
                break
              end
            end

            sleep(0.5)
            progress = progress + 1
          rescue => e
            log_error(__method__, e)
            break
          end
        end

        if batch_count >= max_batch_attempts
          log_warn(__method__, "Atingido limite máximo de batches (#{max_batch_attempts})")
            sse.write({ progress: progress, message: "Reached maximum batch limit (#{max_batch_attempts})" }, event: "status") if sse
          log_info(__method__, "Análise final: #{analyze_completion_status(full_text)}")
        else
            sse.write({ progress: progress, message: "Batches completed naturally in #{batch_count} attempts" }, event: "status") if sse
          log_info(__method__, "Batches concluídos naturalmente em #{batch_count} tentativas")
        end

        if @append_references && all_citations.any?
          full_text = append_references_section(full_text, all_citations)
        end

        log_info(__method__, "Resposta final: #{batch_count} batch(es), #{full_text&.length || 0} caracteres")
        { text: full_text, usage: parsed[:usage], batch_count: batch_count, citations: all_citations }
      end

      def batch_prompt
        prompt = <<-markdown

          ---

          ## Response Management

          **IMPORTANT - Batch Continuation Protocol**: Due to the comprehensive nature of this analysis, if you need to continue:
          - End ONLY with: **"Continue in next batch..."** (exact text)
          - Do NOT add this phrase unless you actually need to continue
          - Do NOT use phrases like "Continue if further..." or "May continue..."
          - If analysis is complete, end naturally without continuation phrases
        markdown

        prompt
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

      # NOVA LÓGICA UNIFICADA DE CONTINUAÇÃO
      def should_continue?(content)
        return false if content.nil? || content.strip.empty?

        text = content.downcase.strip

        log_debug(__method__, "Analisando continuação para: '#{content.slice(-150..-1)}'")

        # Padrões que indicam continuação REAL - PRIMEIRO E MAIS IMPORTANTE
        true_continuation_patterns = [
          /continue\s+in\s+next\s+batch\.{3}$/i,  # Exato do prompt
          /continue\s+in\s+next\s+batch\.{0,3}$/i  # Com ou sem pontos
        ]

        # Verifica continuação verdadeira PRIMEIRO
        has_true_continuation = true_continuation_patterns.any? { |pattern| text.match?(pattern) }

        # Se tem continuação explícita, deve continuar sempre
        if has_true_continuation
          log_debug(__method__, "✅ Continuação explícita detectada - deve continuar")
          return true
        end

        # Padrões que são FALSOS POSITIVOS
        false_positive_patterns = [
          /continue\s+if\s+further/i,
          /continue\s+if\s+additional/i,
          /continue\s+if\s+needed/i,
          /continue\s+if\s+required/i,
          /may\s+continue/i,
          /can\s+continue/i,
          /should\s+continue/i,
          /to\s+continue/i
        ]

        # Verifica falsos positivos
        is_false_positive = false_positive_patterns.any? { |pattern| text.match?(pattern) }

        if is_false_positive
          log_debug(__method__, "❌ Falso positivo detectado - não é continuação real")
          return false
        end

        # Verifica truncamento suspeito (texto longo sem final adequado)
        appears_truncated = content.length > 3000 &&
                           !text.match?(/\.\s*$|!\s*$|\?\s*$|---\s*$|\*\*\s*$/) &&
                           !text.match?(/references\s*$/i) &&
                           !text.match?(/sources\s*$/i)

        result = appears_truncated

        log_debug(__method__, "🔍 Análise: true_continuation=#{has_true_continuation}, truncated=#{appears_truncated}, false_positive=#{is_false_positive} → #{result}")

        result
      end

      def response_seems_complete?(content)
        return false if content.nil? || content.strip.empty?

        text = content.downcase.strip

        # PRIMEIRO: Se tem "Continue in next batch...", NÃO está completo
        continuation_indicators = [
          /continue\s+in\s+next\s+batch/i
        ]

        has_continuation_request = continuation_indicators.any? { |pattern| text.match?(pattern) }

        if has_continuation_request
          log_debug(__method__, "🔄 Texto tem pedido de continuação - NÃO está completo")
          return false
        end

        # Só depois verifica outros indicadores de completude
        strong_completion_indicators = [
          # Termina com seção completa de referências (não no meio)
          /---\s*##\s*references.*$/mi,
          /bibliography\s*$/i,
          /conclusion\s*$/i,
          # Análise explicitamente finalizada
          /analysis\s+complete/i,
          /study\s+concluded/i,
          /assessment\s+finished/i,
          /evaluation\s+concluded/i,
          /research\s+complete/i
        ]

        # Verifica se tem PESTLE completo E sem pedido de continuação
        has_all_pestle_sections = text.include?("political") && text.include?("economic") &&
                                 text.include?("social") && text.include?("technological") &&
                                 text.include?("legal") && text.include?("environmental")

        has_many_items = text.scan(/[peslte]\d+/i).length >= 20  # Aumentei o limite

        has_strong_indicator = strong_completion_indicators.any? { |pattern| content.match?(pattern) }

        # Só considera completo se tem indicadores FORTES
        result = has_strong_indicator || (has_all_pestle_sections && has_many_items && content.length > 8000)

        log_debug(__method__, "📋 Completude: strong=#{has_strong_indicator}, all_pestle=#{has_all_pestle_sections}, many_items=#{has_many_items}, continuation=#{has_continuation_request} → #{result}")

        result
      end

      def analyze_completion_status(content)
        return "Conteúdo vazio" if content.nil? || content.strip.empty?

        analysis = {
          length: content.length,
          has_references: content.downcase.include?("references"),
          pestle_sections: content.downcase.scan(/political|economic|social|technological|legal|environmental/).length,
          numbered_items: content.scan(/[PESLTE]\d+/i).length,
          seems_complete: response_seems_complete?(content)
        }

        "Chars: #{analysis[:length]}, PESTLE seções: #{analysis[:pestle_sections]}, Items numerados: #{analysis[:numbered_items]}, Tem refs: #{analysis[:has_references]}, Completo: #{analysis[:seems_complete]}"
      end

      def clean_continuation_content(previous_text, new_content)
        return new_content if previous_text.nil? || new_content.nil?

        # Remove possível repetição dos últimos caracteres
        [ 100, 50, 25 ].each do |check_length|
          last_chars = previous_text.slice(-check_length..-1)
          if last_chars && new_content.start_with?(last_chars.strip)
            cleaned = new_content[last_chars.strip.length..-1]
            log_debug(__method__, "🧹 Removida repetição de #{check_length} chars")
            return cleaned
          end
        end

        new_content
      end

      def build_messages(prompt, system_message)
        msgs = []
        msgs << { role: "system", content: system_message } if system_message
        msgs << { role: "user", content: prompt + batch_prompt }
        log_debug(__method__, "Mensagens construídas: #{msgs.size} mensagens")
        msgs
      end

      def build_continuation_messages(original_messages, partial_response)
        continuation_messages = original_messages.dup
        continuation_messages << { role: "assistant", content: partial_response }
        continuation_messages << { role: "user", content: "Continue" }
        log_debug(__method__, "Mensagens de continuação construídas: #{continuation_messages.size} mensagens")
        continuation_messages
      end

      def post_chat(messages:, action: nil, stream: false, retries: 3)
        payload = {
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          messages: messages,
          stream: stream,
          return_citations: true
        }

        if action&.ai_action&.custom_attributes&.is_a?(Hash)
          payload.merge!(action.ai_action.custom_attributes)
        end

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
              log_warn(__method__, "Erro HTTP: #{response.code} - #{response.body}")
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
          log_warn(__method__, "Unauthorized 401 - Invalid API key")
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

        if messages.size > 2
          log_debug(__method__, "🔄 Continuação detectada")
        end
      end

      def log_response(response)
        log_info(__method__, "Perplexity API Response: HTTP #{response.code}, success=#{response.success?}")
        if response.code != 200
          log_warn(__method__, "Error response body: #{response.body}")
        else
          log_debug(__method__, "Resposta recebida com sucesso")
        end
      end
    end
  end
end
