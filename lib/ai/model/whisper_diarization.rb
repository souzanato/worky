require "net/http"
require "json"
require "uri"
require "base64"

module Ai
  module Model
    class WhisperDiarization
      include Ai::Model::Logging

      DEFAULT_TIMEOUT = 300
      DEFAULT_MODEL = "thomasmol/whisper-diarization"

      REPLICATE_API_URL = "https://api.replicate.com/v1/predictions"

      def initialize(timeout: DEFAULT_TIMEOUT, model: DEFAULT_MODEL)
        @model = model
        @timeout = timeout
        @api_token = Settings.reload!.apis.replicate.api_token
        @model_version = nil  # Cache da versão

        log_info(__method__, "Inicializando WhisperDiarization com modelo=#{@model}, timeout=#{@timeout}s")
      end

      # Exemplo de uso:
      # Pode enviar áudio como base64 (file_string), URL pública (file_url) ou caminho local (file)
      # Aqui implementamos só base64 e URL pública por simplicidade
      def transcribe(audio_path: nil, audio_url: nil, prompt: nil, num_speakers: nil, language: nil, group_segments: true)
        input_payload = {}

        if audio_url
          input_payload["file_url"] = audio_url
        elsif audio_path
          audio_data = File.binread(audio_path)
          input_payload["file_string"] = Base64.strict_encode64(audio_data)
        else
          raise ArgumentError, "É necessário fornecer audio_url ou audio_path"
        end

        input_payload["prompt"] = prompt if prompt
        input_payload["num_speakers"] = num_speakers if num_speakers
        input_payload["language"] = language if language
        input_payload["group_segments"] = group_segments

        body = {
          version: get_model_version,
          input: input_payload
        }.to_json

        headers = {
          "Authorization" => "Token #{@api_token}",
          "Content-Type" => "application/json"
        }

        uri = URI(REPLICATE_API_URL)

        begin
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = @timeout

          request = Net::HTTP::Post.new(uri.request_uri, headers)
          request.body = body

          log_request(input_payload)

          response = http.request(request)

          log_info(__method__, "Resposta recebida da API Replicate WhisperDiarization com status #{response.code}")

          case response
          when Net::HTTPSuccess
            parse_response(JSON.parse(response.body))
          else
            log_error(__method__, "Erro na resposta da API: #{response.body}")
            raise "Erro na API Replicate: #{response.message}"
          end
        rescue Net::ReadTimeout => e
          log_error(__method__, e)
          handle_timeout_error(e)
        rescue => e
          log_error(__method__, e)
          handle_general_error(e)
        end
      end

      def test_connection
        log_info(__method__, "Testando conexão com API Replicate para modelo #{@model}")
        headers = { "Authorization" => "Token #{@api_token}" }
        uri = URI("https://api.replicate.com/v1/models/#{@model}")

        begin
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
            req = Net::HTTP::Get.new(uri, headers)
            http.request(req)
          end

          log_info(__method__, "Resposta Teste conexão: #{response.code}")

          if response.code.to_i == 200
            { success: true, model: @model }
          else
            { success: false, error: response.body }
          end
        rescue => e
          log_error(__method__, e)
          { success: false, error: e.message }
        end
      end

      private

      def get_model_version
        return @model_version if @model_version

        owner, name = @model.split("/")
        headers = { "Authorization" => "Token #{@api_token}" }
        uri = URI("https://api.replicate.com/v1/models/#{owner}/#{name}")

        log_info(__method__, "Buscando versão mais recente do modelo #{@model}")

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          req = Net::HTTP::Get.new(uri, headers)
          http.request(req)
        end

        if response.code.to_i == 200
          model_data = JSON.parse(response.body)
          @model_version = model_data.dig("latest_version", "id")
          log_info(__method__, "Versão obtida e cacheada: #{@model_version}")
          @model_version
        else
          log_error(__method__, "Erro: #{response.code} - #{response.body}")
          raise "Não foi possível obter a versão do modelo"
        end
      rescue => e
        log_error(__method__, e)
        raise "Erro ao buscar versão: #{e.message}"
      end

      def parse_response(response)
        log_debug(__method__, "Parsing response: #{response.inspect}")

        if response["status"] == "succeeded"
          output = response["output"] || {}
          log_info(__method__, "Transcrição com diarização obtida com sucesso")
          {
            segments: output["segments"],
            num_speakers: output["num_speakers"],
            language: output["language"]
          }
        elsif response["status"] == "processing"
          { status: "processing", id: response["id"] }
        else
          raise "Falha na transcrição: #{response['error'] || 'status desconhecido'}"
        end
      rescue => e
        log_error(__method__, e)
        raise
      end

      def log_request(input_payload)
        log_info(__method__, "=" * 50)
        log_info(__method__, "Replicate API Request para modelo #{@model}")
        log_info(__method__, "Timeout: #{@timeout}s")
        log_debug(__method__, "Payload de entrada: #{input_payload.inspect}")
      end

      def handle_timeout_error(error)
        log_error(__method__, error)
        raise "Replicate API timeout após #{@timeout} segundos."
      end

      def handle_general_error(error)
        log_error(__method__, error)
        raise "Erro na API Replicate: #{error.message}"
      end
    end
  end
end
