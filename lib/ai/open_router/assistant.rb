require 'net/http'
require 'uri'
require 'json'
require 'logger'

class Ai::OpenRouter::Assistant
  BASE_URL = Settings.reload!.apis.open_router.endpoint
  
  attr_reader :api_key, :site_url, :site_name, :logger
  
  # Configurações para continuação automática
  MAX_CONTINUATION_ATTEMPTS = 5  # Máximo de tentativas de continuação
  TRUNCATION_INDICATORS = ['length', 'max_tokens'].freeze  # finish_reason que indicam truncamento
  
  def initialize(
    api_key: ENV["OPENROUTER_API_KEY"], 
    site_url: Settings.reload!.apis.open_router.site_url, 
    site_name: Settings.reload!.apis.open_router.site_name,
    logger: nil,
    log_level: Logger::INFO,
    log_file: nil
  )
    @api_key = api_key
    @site_url = site_url
    @site_name = site_name
    @logger = setup_logger(logger, log_level, log_file)
    @log_to_file = !log_file.nil?
    
    log_initialization
  end
  
  # Método principal para fazer requisições de chat completions
  def chat_completion(
    # Array de mensagens no formato [{role: 'user', content: '...'}] - formato chat
    messages: nil,
    
    # String simples de prompt - alternativa a messages para formato texto
    prompt: nil,
    
    # ID do modelo a usar (ex: 'openai/gpt-4o', 'anthropic/claude-3.5-sonnet')
    model: nil,
    
    # Se true, retorna resposta em chunks via streaming (SSE)
    stream: false,
    
    # Limite máximo de tokens na resposta gerada
    max_tokens: nil,
    
    # Controla aleatoriedade (0-2): 0=determinístico, 2=muito criativo
    temperature: nil,
    
    # Amostragem nucleus: considera apenas tokens com probabilidade acumulada até P (0-1)
    top_p: nil,
    
    # Limita escolha aos K tokens mais prováveis (não disponível para OpenAI)
    top_k: nil,
    
    # Penaliza tokens já usados baseado na frequência (-2 a 2)
    frequency_penalty: nil,
    
    # Penaliza tokens já presentes independente da frequência (-2 a 2)
    presence_penalty: nil,
    
    # Penalidade alternativa para repetição (0-2), usado por alguns modelos
    repetition_penalty: nil,
    
    # Seed para reproduzir respostas idênticas (determinismo)
    seed: nil,
    
    # String ou array de strings que param a geração quando encontradas
    stop: nil,
    
    # Força formato de saída: {type: 'json_object'} para JSON estruturado
    response_format: nil,
    
    # Array de ferramentas/funções que o modelo pode chamar
    tools: nil,
    
    # Controla quando usar tools: 'none', 'auto' ou {type: 'function', function: {name: '...'}}
    tool_choice: nil,
    
    # Transformações de prompt aplicadas antes de enviar ao modelo
    transforms: nil,
    
    # Array de modelos para fallback - tenta cada um até obter sucesso
    models: nil,
    
    # Estratégia de roteamento entre modelos: 'fallback'
    route: nil,
    
    # Preferências de provedor/provider para controlar qual usar
    provider: nil,
    
    # ID do usuário final - ajuda OpenRouter a detectar/prevenir abuso
    user: nil,
    
    # Ajusta probabilidade de tokens específicos: {token_id: bias_value}
    logit_bias: nil,
    
    # Quantidade de logprobs mais prováveis a retornar por token
    top_logprobs: nil,
    
    # Amostragem min-p: remove tokens com probabilidade < P * prob_max (0-1)
    min_p: nil,
    
    # Amostragem top-a: remove tokens com probabilidade < a * prob_max^2 (0-1)
    top_a: nil,
    
    # Saída prevista para reduzir latência: {type: 'content', content: '...'}
    prediction: nil,
    
    # Opções de debug (streaming): {echo_upstream_body: true} retorna request transformado
    debug: nil,
    
    # Se true, desabilita continuação automática de respostas truncadas
    disable_auto_continuation: false,
    
    # Objeto SSE para enviar feedbacks de progresso ao usuário
    sse: nil,
    
    &block
  )
    request_id = generate_request_id
    start_time = Time.now
    
    begin
      raise ArgumentError, 'Você deve fornecer "messages" ou "prompt"' if messages.nil? && prompt.nil?
      
      # SSE: Iniciando processamento
      sse&.write({ progress: 61, message: "Initializing request to #{model || 'default model'}..." }, event: "status")
      
      log_request_start(request_id, model, messages, prompt, stream)
      
      body = build_request_body(
        messages: messages,
        prompt: prompt,
        model: model,
        stream: stream,
        max_tokens: max_tokens,
        temperature: temperature,
        top_p: top_p,
        top_k: top_k,
        frequency_penalty: frequency_penalty,
        presence_penalty: presence_penalty,
        repetition_penalty: repetition_penalty,
        seed: seed,
        stop: stop,
        response_format: response_format,
        tools: tools,
        tool_choice: tool_choice,
        transforms: transforms,
        models: models,
        route: route,
        provider: provider,
        user: user,
        logit_bias: logit_bias,
        top_logprobs: top_logprobs,
        min_p: min_p,
        top_a: top_a,
        prediction: prediction,
        debug: debug
      )
      
      log_request_body(request_id, body)
      
      # SSE: Enviando requisição
      sse&.write({ progress: 63, message: "Sending request to API..." }, event: "status")
      
      result = if stream
        stream_request(body, request_id, &block)
      else
        if disable_auto_continuation
          standard_request(body, request_id, sse)
        else
          request_with_auto_continuation(body, request_id, sse)
        end
      end
      
      duration = Time.now - start_time
      
      # SSE: Processamento concluído
      sse&.write({ progress: 74, message: "Response received successfully!" }, event: "status")
      
      log_request_success(request_id, result, duration)
      
      result
      
    rescue => e
      duration = Time.now - start_time
      log_request_error(request_id, e, duration)
      
      # SSE: Erro
      sse&.write({ progress: 0, message: "Error: #{e.message}" }, event: "error")
      
      raise
    end
  end
  
  # Buscar informações de uma geração específica
  def get_generation(generation_id)
    request_id = generate_request_id
    start_time = Time.now
    
    begin
      @logger.info "[#{request_id}] Buscando geração: #{generation_id}"
      
      uri = URI("#{BASE_URL}/generation?id=#{generation_id}")
      request = Net::HTTP::Get.new(uri)
      add_headers(request)
      
      response = execute_request(uri, request)
      result = parse_response(response)
      
      duration = Time.now - start_time
      @logger.info "[#{request_id}] Geração obtida com sucesso em #{format_duration(duration)}"
      
      result
      
    rescue => e
      duration = Time.now - start_time
      @logger.error "[#{request_id}] Erro ao buscar geração: #{e.message} (#{format_duration(duration)})"
      raise
    end
  end
  
  # Listar modelos disponíveis
  def self.list_models(api_key: ENV["OPENROUTER_API_KEY"], logger: nil)
    request_id = SecureRandom.hex(8)
    start_time = Time.now
    logger ||= Logger.new(STDOUT)
    
    begin
      logger.info "[#{request_id}] Listando modelos disponíveis"
      
      uri = URI("#{BASE_URL}/models")
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{api_key}"
      request['Content-Type'] = 'application/json'
      
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      
      case response
      when Net::HTTPSuccess
        models = DeepOpenStruct.convert JSON.parse(response.body, symbolize_names: true)[:data]
        duration = Time.now - start_time
        logger.info "[#{request_id}] #{models.size} modelos listados com sucesso (#{(duration * 1000).round(2)}ms)"
        models
      else
        error_data = JSON.parse(response.body) rescue { error: response.body }
        logger.error "[#{request_id}] Erro ao listar modelos: #{response.code} - #{error_data}"
        raise "Erro na API: #{response.code} - #{error_data}"
      end
      
    rescue => e
      duration = Time.now - start_time
      logger.error "[#{request_id}] Exceção ao listar modelos: #{e.class} - #{e.message} (#{(duration * 1000).round(2)}ms)"
      raise
    end
  end
  
  # Helper para criar mensagens facilmente
  def self.create_message(role:, content:, name: nil, tool_call_id: nil)
    message = { role: role, content: content }
    message[:name] = name if name
    message[:tool_call_id] = tool_call_id if tool_call_id
    message
  end
  
  # Helper para criar mensagens com imagens
  def self.create_image_message(role: 'user', text: nil, image_url:, detail: 'auto')
    content = []
    content << { type: 'text', text: text } if text
    content << {
      type: 'image_url',
      image_url: {
        url: image_url,
        detail: detail
      }
    }
    
    { role: role, content: content }
  end
  
  # Helper para criar ferramentas (tools)
  def self.create_tool(name:, description: nil, parameters:)
    {
      type: 'function',
      function: {
        name: name,
        description: description,
        parameters: parameters
      }.compact
    }
  end
  
  private
  
  # ========================================
  # LOGGING METHODS
  # ========================================
  
  def setup_logger(custom_logger, log_level, log_file)
    return custom_logger if custom_logger
    
    logger = if log_file
      Logger.new(log_file, 'daily')
    else
      Logger.new(STDOUT)
    end
    
    logger.level = log_level
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')}] #{severity.ljust(5)} -- #{msg}\n"
    end
    
    logger
  end
  
  def log_initialization
    @logger.info "=" * 80
    @logger.info "OpenRouter Assistant inicializado"
    @logger.info "Base URL: #{BASE_URL}"
    @logger.info "Site URL: #{@site_url}" if @site_url
    @logger.info "Site Name: #{@site_name}" if @site_name
    @logger.info "API Key: #{mask_api_key(@api_key)}"
    @logger.info "Log Mode: #{@log_to_file ? 'Arquivo (conteúdo completo)' : 'STDOUT (conteúdo truncado)'}"
    @logger.info "=" * 80
  end
  
  def log_request_start(request_id, model, messages, prompt, stream)
    @logger.info "┌─ [#{request_id}] Nova requisição"
    @logger.info "│  Modelo: #{model || 'padrão'}"
    @logger.info "│  Tipo: #{stream ? 'Streaming' : 'Standard'}"
    
    if messages
      @logger.info "│  Mensagens: #{messages.size} mensagem(ns)"
      
      if @log_to_file
        # No arquivo: mostra conteúdo completo
        @logger.info "│  Detalhes das mensagens (completo):"
        messages.each_with_index do |msg, idx|
          @logger.info "│    ┌─ Mensagem [#{idx}]"
          @logger.info "│    │  Role: #{msg[:role]}"
          @logger.info "│    │  Content:"
          msg[:content].to_s.split("\n").each do |line|
            @logger.info "│    │    #{line}"
          end
          @logger.info "│    └─"
        end
      else
        # No STDOUT: mostra preview truncado
        @logger.info "│  Preview das mensagens (truncado):"
        messages.each_with_index do |msg, idx|
          content_preview = truncate_content(msg[:content].to_s, 100)
          @logger.info "│    [#{idx}] #{msg[:role]}: #{content_preview}"
        end
      end
      
    elsif prompt
      if @log_to_file
        # No arquivo: mostra prompt completo
        @logger.info "│  Prompt (completo):"
        prompt.to_s.split("\n").each do |line|
          @logger.info "│    #{line}"
        end
      else
        # No STDOUT: mostra preview truncado
        prompt_preview = truncate_content(prompt, 150)
        @logger.info "│  Prompt: #{prompt_preview}"
      end
    end
  end
  
  def log_request_body(request_id, body)
    @logger.debug "│  [#{request_id}] Parâmetros da requisição:"
    body.each do |key, value|
      next if [:messages, :prompt].include?(key)
      @logger.debug "│    #{key}: #{value.inspect}"
    end
  end
  
  def log_request_success(request_id, result, duration)
    @logger.info "└─ [#{request_id}] ✓ Requisição concluída com sucesso"
    @logger.info "   Duração: #{format_duration(duration)}"
    
    if result[:choices]&.first
      choice = result[:choices].first
      content = choice.dig(:message, :content)
      content_length = content&.length || 0
      finish_reason = choice[:finish_reason]
      
      @logger.info "   Resposta: #{content_length} caracteres"
      @logger.info "   Finish Reason: #{finish_reason}"
      
      # Log da resposta
      if content
        if @log_to_file
          # No arquivo: mostra resposta completa
          @logger.info "   Conteúdo da resposta (completo):"
          content.split("\n").each do |line|
            @logger.info "     #{line}"
          end
        else
          # No STDOUT: mostra preview truncado
          response_preview = truncate_content(content, 200)
          @logger.info "   Preview da resposta: #{response_preview}"
        end
      end
    end
    
    if result[:usage]
      @logger.info "   Tokens:"
      @logger.info "     - Prompt: #{result[:usage][:prompt_tokens]}"
      @logger.info "     - Completion: #{result[:usage][:completion_tokens]}"
      @logger.info "     - Total: #{result[:usage][:total_tokens]}"
    end
    
    if result[:continuation_metadata]
      meta = result[:continuation_metadata]
      @logger.info "   Continuação Automática:"
      @logger.info "     - Total de batches: #{meta[:total_batches]}"
      @logger.info "     - Auto continuado: #{meta[:auto_continued] ? 'Sim' : 'Não'}"
    end
    
    @logger.info ""
  end
  
  def log_request_error(request_id, error, duration)
    @logger.error "└─ [#{request_id}] ✗ Erro na requisição"
    @logger.error "   Duração até erro: #{format_duration(duration)}"
    @logger.error "   Tipo: #{error.class}"
    @logger.error "   Mensagem: #{error.message}"
    @logger.error "   Backtrace:"
    error.backtrace.first(5).each do |line|
      @logger.error "     #{line}"
    end
    @logger.error ""
  end
  
  def log_continuation_start(request_id, attempt, total_content_length)
    @logger.info "   [#{request_id}] → Continuação #{attempt}"
    @logger.info "     Conteúdo acumulado: #{total_content_length} caracteres"
  end
  
  def log_continuation_complete(request_id, total_batches, final_length)
    @logger.info "   [#{request_id}] ✓ Continuação completa"
    @logger.info "     Total de batches: #{total_batches}"
    @logger.info "     Tamanho final: #{final_length} caracteres"
  end
  
  def log_continuation_limit_reached(request_id, max_attempts)
    @logger.warn "   [#{request_id}] ⚠ Limite de continuações atingido (#{max_attempts})"
  end
  
  def log_truncation_detected(request_id, finish_reason, has_pattern)
    @logger.info "   [#{request_id}] ⚠ Truncamento detectado"
    @logger.info "     Finish Reason: #{finish_reason}" if finish_reason
    @logger.info "     Padrão de texto: #{has_pattern ? 'Sim' : 'Não'}"
  end
  
  def log_streaming_start(request_id)
    @logger.info "   [#{request_id}] 🔄 Iniciando streaming..."
  end
  
  def log_streaming_chunk(request_id, chunk_index, delta_content)
    return unless @logger.level == Logger::DEBUG
    
    content_preview = truncate_content(delta_content.to_s, 50)
    @logger.debug "   [#{request_id}] Chunk #{chunk_index}: #{content_preview}"
  end
  
  def log_streaming_complete(request_id, total_chunks)
    @logger.info "   [#{request_id}] ✓ Streaming concluído (#{total_chunks} chunks)"
  end
  
  # ========================================
  # HELPER METHODS FOR LOGGING
  # ========================================
  
  def generate_request_id
    SecureRandom.hex(8)
  end
  
  def mask_api_key(key)
    return 'não configurada' unless key
    "#{key[0..7]}...#{key[-4..-1]}"
  end
  
  def truncate_content(text, max_length = 100)
    return '' unless text
    text = text.to_s
    return text if text.length <= max_length
    "#{text[0...max_length]}... (#{text.length} chars total)"
  end
  
  def format_duration(duration)
    if duration < 1
      "#{(duration * 1000).round(2)}ms"
    else
      "#{duration.round(2)}s"
    end
  end
  
  # ========================================
  # CORE METHODS
  # ========================================
  
  def build_request_body(**params)
    body = {}
    
    params.each do |key, value|
      body[key] = value unless value.nil?
    end
    
    body
  end
  
  def add_headers(request)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    request['HTTP-Referer'] = @site_url if @site_url
    request['X-Title'] = @site_name if @site_name
  end
  
  def execute_request(uri, request)
    @logger.debug "Executando requisição HTTP: #{request.method} #{uri}"
    
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  end
  
  def standard_request(body, request_id = nil, sse = nil)
    request_id ||= generate_request_id
    
    uri = URI("#{BASE_URL}/chat/completions")
    request = Net::HTTP::Post.new(uri)
    add_headers(request)
    request.body = body.to_json
    
    @logger.debug "[#{request_id}] Enviando requisição para #{uri}"
    
    # SSE: Aguardando resposta
    sse&.write({ progress: 65, message: "Waiting for model response..." }, event: "status")
    
    response = execute_request(uri, request)
    
    # SSE: Processando resposta
    sse&.write({ progress: 68, message: "Processing response..." }, event: "status")
    
    parse_response(response, request_id)
  end
  
  # Requisição com continuação automática
  def request_with_auto_continuation(body, request_id, sse = nil)
    accumulated_content = []
    current_messages = body[:messages]&.dup || []
    continuation_count = 0
    last_response = nil
    
    # Se usar prompt ao invés de messages, converter para messages
    if body[:prompt] && current_messages.empty?
      current_messages = [{ role: 'user', content: body[:prompt] }]
      body = body.dup
      body.delete(:prompt)
      body[:messages] = current_messages
    end
    
    loop do
      # SSE: Fazendo requisição (batch)
      if continuation_count == 0
        sse&.write({ progress: 65, message: "Requesting response from model..." }, event: "status")
      else
        progress = 66 + (continuation_count * 2) # Incrementa progresso a cada batch
        progress = [progress, 73].min # Limita a 73
        sse&.write({ progress: progress, message: "Continuing generation (batch #{continuation_count + 1})..." }, event: "status")
      end
      
      # Fazer requisição
      response = standard_request(body, request_id, nil) # Não passa SSE para evitar duplicação
      last_response = response
      
      # Verificar se houve erro
      return response if response[:error]
      
      # Extrair o conteúdo da resposta
      choice = response.dig(:choices, 0)
      return response unless choice
      
      content = choice.dig(:message, :content)
      finish_reason = choice[:finish_reason]
      
      # Adicionar conteúdo ao acumulador
      accumulated_content << content if content
      
      # Verificar se precisa continuar
      needs_continuation = response_truncated?(finish_reason, content)
      
      if needs_continuation
        log_truncation_detected(request_id, finish_reason, content_has_truncation_pattern?(content))
        
        # SSE: Truncamento detectado
        sse&.write({ 
          progress: 67 + (continuation_count * 2), 
          message: "Response truncated, requesting continuation..." 
        }, event: "status")
      end
      
      break unless needs_continuation
      
      # Limitar tentativas de continuação
      continuation_count += 1
      if continuation_count >= MAX_CONTINUATION_ATTEMPTS
        log_continuation_limit_reached(request_id, MAX_CONTINUATION_ATTEMPTS)
        
        # SSE: Limite atingido
        sse&.write({ 
          progress: 72, 
          message: "Maximum continuation limit reached, finalizing..." 
        }, event: "status")
        
        break
      end
      
      log_continuation_start(request_id, continuation_count, accumulated_content.join.length)
      
      # Preparar próxima requisição com o histórico atualizado
      current_messages << {
        role: 'assistant',
        content: content
      }
      
      current_messages << {
        role: 'user',
        content: 'Continue de onde parou.'
      }
      
      body = body.dup
      body[:messages] = current_messages
    end
    
    # SSE: Consolidando resposta
    sse&.write({ progress: 73, message: "Consolidating response..." }, event: "status")
    
    # Consolidar resposta final
    final_response = build_consolidated_response(last_response, accumulated_content, continuation_count)
    
    if continuation_count > 0
      log_continuation_complete(request_id, continuation_count + 1, final_response.dig(:choices, 0, :message, :content)&.length || 0)
      
      # SSE: Consolidação completa
      total_chars = final_response.dig(:choices, 0, :message, :content)&.length || 0
      sse&.write({ 
        progress: 74, 
        message: "Response consolidated successfully! (#{continuation_count + 1} batches, #{total_chars} characters)" 
      }, event: "status")
    end
    
    final_response
  end
    
  # Verifica se a resposta foi truncada e precisa continuar
  def response_truncated?(finish_reason, content)
    return false unless finish_reason
    
    # Verifica finish_reason que indicam truncamento
    return true if TRUNCATION_INDICATORS.include?(finish_reason.to_s)
    
    # Verifica padrões de texto que indicam continuação
    content_has_truncation_pattern?(content)
  end
  
  def content_has_truncation_pattern?(content)
    return false unless content
    
    truncation_patterns = [
      /posso continuar/i,
      /devo continuar/i,
      /quer que eu continue/i,
      /continuar gerando/i,
      /continuo\?/i,
      /continue\?/i,
      /\[continua\]/i,
      /\(continua\)/i,
      /\.\.\.$/  # Termina com reticências
    ]
    
    truncation_patterns.any? { |pattern| content.match?(pattern) }
  end
  
  # Constrói a resposta consolidada com todos os batches
  def build_consolidated_response(last_response, accumulated_content, continuation_count)
    consolidated_content = accumulated_content.join("\n\n")
    
    # Limpar padrões de continuação do texto final
    consolidated_content = clean_continuation_patterns(consolidated_content)
    
    # Criar resposta consolidada baseada na última resposta
    consolidated_response = last_response.dup
    
    if consolidated_response[:choices]&.first
      consolidated_response[:choices][0][:message][:content] = consolidated_content
      consolidated_response[:choices][0][:finish_reason] = 'stop'
      
      # Adicionar metadados sobre a continuação
      consolidated_response[:continuation_metadata] = {
        total_batches: continuation_count + 1,
        auto_continued: continuation_count > 0
      }
    end
    
    consolidated_response
  end
  
  # Remove padrões de continuação do texto consolidado
  def clean_continuation_patterns(text)
    return text unless text
    
    patterns_to_remove = [
      /\n*posso continuar.*?\?/i,
      /\n*devo continuar.*?\?/i,
      /\n*quer que eu continue.*?\?/i,
      /\n*continuar gerando.*?\?/i,
      /\n*continuo\?/i,
      /\n*continue\?/i,
      /\n*\[continua\]/i,
      /\n*\(continua\)/i,
      /\n*continue de onde parou\.*/i
    ]
    
    cleaned_text = text.dup
    patterns_to_remove.each do |pattern|
      cleaned_text.gsub!(pattern, '')
    end
    
    # Remover múltiplas quebras de linha consecutivas
    cleaned_text.gsub!(/\n{3,}/, "\n\n")
    
    cleaned_text.strip
  end
  
  def stream_request(body, request_id)
    log_streaming_start(request_id)
    chunk_count = 0
    
    uri = URI("#{BASE_URL}/chat/completions")
    request = Net::HTTP::Post.new(uri)
    add_headers(request)
    request.body = body.to_json
    
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          error_data = JSON.parse(response.body) rescue { error: response.body }
          @logger.error "[#{request_id}] Erro no streaming: #{response.code} - #{error_data}"
          raise "Erro na API: #{response.code} - #{error_data}"
        end
        
        buffer = ''
        response.read_body do |chunk|
          buffer += chunk
          
          # Processar linhas completas
          while (line_end = buffer.index("\n"))
            line = buffer[0...line_end].strip
            buffer = buffer[(line_end + 1)..-1]
            
            next if line.empty? || line.start_with?(':')
            
            if line.start_with?('data: ')
              data = line[6..-1]
              next if data == '[DONE]'
              
              begin
                json_data = JSON.parse(data, symbolize_names: true)
                chunk_count += 1
                
                # Log chunk em modo debug
                delta_content = json_data.dig(:choices, 0, :delta, :content)
                log_streaming_chunk(request_id, chunk_count, delta_content) if delta_content
                
                yield json_data if block_given?
              rescue JSON::ParserError => e
                @logger.warn "[#{request_id}] Erro ao fazer parse do JSON no streaming: #{e.message}"
              end
            end
          end
        end
      end
    end
    
    log_streaming_complete(request_id, chunk_count)
  end
  
  def parse_response(response, request_id = nil)
    case response
    when Net::HTTPSuccess
      JSON.parse(response.body, symbolize_names: true)
    else
      error_data = JSON.parse(response.body) rescue { error: response.body }
      @logger.error "[#{request_id}] Erro ao fazer parse da resposta: #{response.code}" if request_id
      raise "Erro na API: #{response.code} - #{error_data}"
    end
  end
end