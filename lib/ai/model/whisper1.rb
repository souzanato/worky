# app/models/ai/model/whisper1.rb
require "openai"

module Ai
  module Model
    class Whisper1
      def initialize(api_key: Settings.reload!.apis.openai.access_token)
        raise "OpenAI API key is missing" if api_key.blank?

        @client = OpenAI::Client.new(access_token: api_key)
      end

      # Transcreve um arquivo de áudio usando Whisper Large V3 Turbo
      #
      # @param file_path [String] caminho do arquivo de áudio local
      # @param language [String] (opcional) idioma esperado ("pt", "en", etc.)
      # @param format [String] (opcional) formato da resposta: "json", "text", "srt", "verbose_json"
      # @return [Hash] resposta da API contendo o texto transcrito
      def transcribe(file_path, language: nil, format: "json")
        raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

        response = @client.audio.transcribe(
          parameters: {
            model: "whisper-1", # Whisper Large V3 Turbo (identificador oficial)
            file: File.open(file_path, "rb"),
            response_format: format
          }.compact
        )

        handle_response(response)
      end

      private

      def handle_response(response)
        if response.is_a?(Hash) && response["text"].present?
          response # formato JSON da API
        elsif response.is_a?(String)
          { "text" => response.strip }
        else
          raise "Whisper API returned unexpected response: #{response.inspect}"
        end
      end
    end
  end
end
