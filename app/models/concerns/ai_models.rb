# app/models/concerns/ai_models.rb
module AiModels
  extend ActiveSupport::Concern
  require "ostruct"

  ModelStruct = OpenStruct

  class_methods do
    def ai_models
      [
        ModelStruct.new(name: "Whisper-1",         code: "whisper-1",         klass: Ai::Model::Whisper1),
        ModelStruct.new(name: "Whisper Diarization",         code: "whisper-diarization",         klass: Ai::Model::WhisperDiarization),
        ModelStruct.new(name: "GPT-4o",            code: "gpt-4o",            klass: Ai::Model::Gpt4o),
        ModelStruct.new(name: "GPT-5",             code: "gpt-5",             klass: Ai::Model::Gpt5),
        ModelStruct.new(name: "Web Scrapping",     code: "web-scrapping",     klass: Ai::Model::Vessel),
        ModelStruct.new(name: "Google Vision",     code: "google-vision",     klass: Ai::Model::GoogleVision),
        ModelStruct.new(name: "Perplexity - Sonar Pro", code: "perplexity-sonar",  klass: Ai::Model::Perplexity),
        ModelStruct.new(name: "xAi - Grok",         code: "grok",  klass: Ai::Model::Grok),
        ModelStruct.new(name: "Claude Opus 4",     code: "claude-opus-4-20250514", klass: Ai::Model::Opus4),
        ModelStruct.new(name: "Claude Sonnet 4.5",     code: "claude-sonnet-4-5-20250929", klass: Ai::Model::Sonnet45),
        ModelStruct.new(name: "Gemini 1.5",     code: "gemini-1.5-pro", klass: Ai::Model::Gemini15),
        ModelStruct.new(name: "Gemini 2.5",     code: "gemini-2.5-pro", klass: Ai::Model::Gemini25)
      ]
    end

    # facilita pegar por código direto
    def find_ai_model_by_code(code)
      ai_models.find { |m| m.code == code.to_s }
    end

    def ai_model?(code)
      ai_models.any? { |m| m.code == code.to_s }
    end
  end
end
