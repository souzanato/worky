# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "base64"

module Ai
  module Model
    # ==========================================================================
    # Ai::Model::GoogleVisionOcr
    #
    # Service object para transcrição de PDFs usando Google Cloud Vision API.
    #
    # Uso:
    #   # Com API Key (modo REST)
    #   service = Ai::Model::GoogleVisionOcr.new(
    #     api_key: "SUA_API_KEY"
    #   )
    #   result = service.call("tmp/artigo-comentado.pdf")
    #   puts result.text
    #   puts result.stats
    #
    #   # Com Service Account + GCS (modo assíncrono para PDFs grandes)
    #   service = Ai::Model::GoogleVisionOcr.new(
    #     mode: :gcs,
    #     bucket: "meu-bucket",
    #     credentials: "path/to/credentials.json"
    #   )
    #   result = service.call("tmp/artigo-comentado.pdf")
    #
    # ==========================================================================
    class GoogleVisionOcr
      class Error < StandardError; end
      class FileNotFoundError < Error; end
      class FileTooLargeError < Error; end
      class ApiError < Error; end
      class ConfigurationError < Error; end

      # Struct para resultado padronizado
      Result = Struct.new(:text, :success?, :stats, :error, keyword_init: true) do
        def to_s
          text.to_s
        end
      end

      MAX_REST_FILE_SIZE_MB = 20
      API_TIMEOUT = 120
      GCS_BATCH_SIZE = 20

      attr_reader :mode, :api_key, :bucket, :credentials

      # @param mode [Symbol] :rest (padrão) ou :gcs
      # @param api_key [String] Google Vision API Key (modo :rest)
      # @param bucket [String] Nome do bucket GCS (modo :gcs)
      # @param credentials [String] Caminho do JSON de credenciais (modo :gcs)
      def initialize(mode: :rest, api_key: nil, bucket: nil, credentials: nil)
        @mode = mode.to_sym
        @api_key = api_key || ENV["GOOGLE_VISION_API_KEY"]
        @bucket = bucket || ENV["GCS_BUCKET"]
        @credentials = credentials || ENV["GOOGLE_APPLICATION_CREDENTIALS"]

        validate_configuration!
      end

      # Executa a transcrição do PDF
      #
      # @param pdf_path [String] Caminho do arquivo PDF
      # @return [Result] Resultado com texto extraído e estatísticas
      def call(pdf_path)
        validate_file!(pdf_path)

        text = case mode
               when :rest then transcribe_via_rest(pdf_path)
               when :gcs  then transcribe_via_gcs(pdf_path)
               end

        build_result(text)
      rescue Error => e
        Result.new(text: nil, success?: false, stats: {}, error: e.message)
      end

      private

      # -----------------------------------------------------------------------
      # Validações
      # -----------------------------------------------------------------------

      def validate_configuration!
        case mode
        when :rest
          raise ConfigurationError, "API Key é obrigatória para o modo REST. " \
            "Defina GOOGLE_VISION_API_KEY ou passe api_key: no inicializador." unless api_key
        when :gcs
          raise ConfigurationError, "Bucket GCS é obrigatório para o modo GCS. " \
            "Defina GCS_BUCKET ou passe bucket: no inicializador." unless bucket
        else
          raise ConfigurationError, "Modo inválido: #{mode}. Use :rest ou :gcs."
        end
      end

      def validate_file!(pdf_path)
        raise FileNotFoundError, "Arquivo não encontrado: #{pdf_path}" unless File.exist?(pdf_path)

        return unless mode == :rest

        size_mb = File.size(pdf_path) / (1024.0 * 1024.0)
        return unless size_mb > MAX_REST_FILE_SIZE_MB

        raise FileTooLargeError, "Arquivo tem #{size_mb.round(1)}MB. " \
          "O modo REST suporta até #{MAX_REST_FILE_SIZE_MB}MB. Use mode: :gcs para arquivos maiores."
      end

      # -----------------------------------------------------------------------
      # Modo REST (API Key, sem dependências extras)
      # -----------------------------------------------------------------------

      def transcribe_via_rest(pdf_path)
        pdf_content = File.binread(pdf_path)
        encoded_pdf = Base64.strict_encode64(pdf_content)

        full_text = +""

        # Sem o parâmetro "pages", a API processa TODAS as páginas do PDF
        # (suporta até 2000 páginas por requisição)
        uri = URI("https://vision.googleapis.com/v1/files:annotate?key=#{api_key}")

        body = {
          requests: [{
            inputConfig: {
              content: encoded_pdf,
              mimeType: "application/pdf"
            },
            features: [{ type: "DOCUMENT_TEXT_DETECTION" }]
          }]
        }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = API_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        unless response.code == "200"
          error_detail = begin
            JSON.parse(response.body)
          rescue StandardError
            response.body
          end
          raise ApiError, "HTTP #{response.code}: #{error_detail}"
        end

        result = JSON.parse(response.body)

        result["responses"]&.each do |file_response|
          file_response["responses"]&.each do |page_response|
            annotation = page_response["fullTextAnnotation"]
            full_text << annotation["text"] << "\n" if annotation
          end
        end

        full_text
      end

      # -----------------------------------------------------------------------
      # Modo GCS (gems oficiais, suporta PDFs grandes)
      # -----------------------------------------------------------------------

      def transcribe_via_gcs(pdf_path)
        require "google/cloud/vision"
        require "google/cloud/storage"

        ENV["GOOGLE_APPLICATION_CREDENTIALS"] = credentials if credentials

        gcs_source = upload_to_gcs(pdf_path)
        output_prefix = "vision_ocr_output/resultado_#{SecureRandom.hex(4)}"

        operation = submit_async_request(gcs_source, output_prefix)
        operation.wait_until_done!

        raise ApiError, "Vision API error: #{operation.error.message}" if operation.error?

        text = collect_results(output_prefix)

        cleanup_gcs(gcs_source, output_prefix)

        text
      end

      def upload_to_gcs(pdf_path)
        gcs_path = "vision_ocr_input/#{File.basename(pdf_path)}_#{SecureRandom.hex(4)}"
        gcs_bucket.create_file(pdf_path, gcs_path)
        gcs_path
      end

      def submit_async_request(gcs_source, output_prefix)
        client = Google::Cloud::Vision.image_annotator

        request = {
          requests: [{
            input_config: {
              gcs_source: { uri: "gs://#{bucket}/#{gcs_source}" },
              mime_type: "application/pdf"
            },
            features: [{ type: :DOCUMENT_TEXT_DETECTION }],
            output_config: {
              gcs_destination: { uri: "gs://#{bucket}/#{output_prefix}" },
              batch_size: GCS_BATCH_SIZE
            }
          }]
        }

        client.async_batch_annotate_files(request)
      end

      def collect_results(output_prefix)
        full_text = +""

        gcs_bucket.files(prefix: output_prefix).each do |file|
          json_content = file.download
          json_content.rewind
          result = JSON.parse(json_content.read)

          result["responses"]&.each do |response|
            annotation = response["fullTextAnnotation"]
            full_text << annotation["text"] if annotation
          end
        end

        full_text
      end

      def cleanup_gcs(gcs_source, output_prefix)
        gcs_bucket.file(gcs_source)&.delete
        gcs_bucket.files(prefix: output_prefix).each(&:delete)
      rescue StandardError => e
        # Não falha se a limpeza der erro, apenas loga
        warn "[GoogleVisionOcr] Aviso ao limpar GCS: #{e.message}"
      end

      def gcs_bucket
        @gcs_bucket ||= Google::Cloud::Storage.new.bucket(bucket)
      end

      # -----------------------------------------------------------------------
      # Resultado
      # -----------------------------------------------------------------------

      def build_result(text)
        if text && !text.strip.empty?
          Result.new(
            text: text.strip,
            success?: true,
            stats: {
              characters: text.length,
              words: text.split.length,
              lines: text.lines.length
            },
            error: nil
          )
        else
          Result.new(
            text: nil,
            success?: false,
            stats: {},
            error: "Nenhum texto extraído. Verifique se o PDF contém texto/imagens legíveis."
          )
        end
      end
    end
  end
end