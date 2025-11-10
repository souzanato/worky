class AiRecord < ApplicationRecord
  include AiModels
  has_many_attached :source_files

  validates :source_type, presence: true, inclusion: { in: %w[text file] }
  validates :ai_action, :ai_model, presence: true
  validates :content, presence: true, if: -> { source_type == "text" }
  validates :source_files, presence: true, if: -> { source_type == "file" }

  # Process record and stream progress updates via SSE
  def process_with_sse(sse, uploaded_files: nil)
    sse.write({ progress: 5, message: "Starting processing..." })

    case source_type
    when "text"
      process_text_source(sse)
    when "file"
      process_multiple_files(sse, uploaded_files: uploaded_files)
    else
      raise "Invalid source type: #{source_type}"
    end

    sse.write({ status: "completed", message: "Processing completed successfully!" }, event: "complete")

  rescue => e
    Rails.logger.error "❌ ERRO FATAL em process_with_sse: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    puts "❌ ERRO FATAL: #{e.message}"
    puts e.backtrace.first(10).join("\n")
    $stdout.flush

    sse.write({ status: "error", message: "Processing failed: #{e.message}" }, event: "error")
  end

  private

  def process_text_source(sse)
    if ai_action == "youtube-transcription"
      yt_videos = []

      sse.write({ progress: 30, message: "Starting YouTube video analysis..." })
      sleep 2
      sse.write({ progress: 55, message: "Loading #{ai_model}..." })
      ai_instance = Class.new.extend(AiModels::ClassMethods).find_ai_model_by_code(self.ai_model)&.klass&.new
      sleep 2
      sse.write({ progress: 75, message: "Processing with #{ai_model}..." })
      result = ai_instance.ask(transcribe_prompt, nil)
      yt_videos << { result: result, status: "success" }
      sse.write({ progress: 90, message: "Finishing up processing..." })
      sleep 3
      sse.write({ progress: 95, message: "Done" })
      sse.write({
        status: "youtube-result",
        data: yt_videos,
        summary: {
          total: 1,
          successful: 1,
          failed: 0
        }
      }, event: "youtube-result")
    end

    if ai_action == "web-scrapping"
      links = self.content.split("\n")
      progress = 30
      if links.any?
        sse.write({ progress: progress, message: "Starting #{links.count} link#{links&.count > 1 ? '(s)' : ''} web scrapping..." })
        progress_step = 65/links.count
        results = []
        links.each_with_index do |link, index|
          begin
            progress = progress + progress_step
            sse.write({ progress: progress, message: "Analysing link #{index + 1} of #{links.count}..." })
            ai_instance = Ai::Model::Vessel.new(link)
            doc_body = ai_instance.ask
            extractor = WebScraper::SimpleContentExtractor.new(doc_body.to_html)
            result = extractor.extract
            results << { url: link, status: "success", text: result[:text] }
          rescue Exception => e
            results << { url: link, status: "error", text: "There as an error with the tlink #{link}" }
          end
        end

        sse.write({ progress: 95, message: "Done" })
        sleep 3

        sse.write({
          status: "web-scrapping-result",
          data: results,
          summary: {
            total: results.count,
            successful: results.count,
            failed: 0
          }
        }, event: "web-scrapping-result")

      else
        sse.write({
          status: "youtube-result",
          data: result,
          summary: {
            total: 1,
            successful: 1,
            failed: 0
          }
        }, event: "youtube-result")
      end
    end
  end

  def transcribe_prompt
    prompt = <<-markdown
You are a transcription AI specialized in extracting and documenting content from YouTube videos.

CRITICAL REQUIREMENT:
- The language of the video is **#{self.language}**.
- You must perform both the transcription and the description **strictly in this language**.
- Do **not** translate or summarize in any other language.

Instructions:
1. Access the following YouTube video: #{self.content}
2. Generate the following two sections, formatted in valid Markdown only:

---

## 🗒️ Video Description
Write a concise yet complete description of what happens in the video, in **#{self.content}**.
Include key topics, speakers, tone, and overall context.
Do not summarize beyond what is visually or audibly present.

---

## 🎧 Full Transcription
Write the **complete** transcription of the spoken audio in **#{self.language}**.
Follow Markdown syntax strictly:
- Separate paragraphs with blank lines.
- Use `**Speaker:**` for identifiable speakers.
- Use inline code formatting for timestamps (e.g., `00:01:25`) if available.
- Do **not** include bullet points, summaries, metadata, or commentary beyond the transcription itself.
- Do not add introductions or closings beyond the two sections above.

---

Output format:
✅ Markdown only — clean, valid, and ready for direct rendering.

Remember:
- Write everything in **#{self.language}**.
- Do not translate, detect, or change the language.
- Do not include explanations, system messages, or additional text.
    markdown

    prompt
  end

  def process_multiple_files(sse, uploaded_files: nil)
    files = uploaded_files.reject { |a| a.blank? } || source_files.attachments
    total = files.size
    raise "No files found" if total.zero?

    if ai_action == "transcription"
      transcriptions = []

      # ⚠️ CAPTURA ERRO NA INICIALIZAÇÃO DO MODELO
      begin
        ai_instance = Class.new.extend(AiModels::ClassMethods).find_ai_model_by_code(self.ai_model)&.klass&.new

        unless ai_instance
          error_msg = "AI model '#{self.ai_model}' not found or could not be initialized"
          Rails.logger.error "❌ #{error_msg}"
          puts "❌ #{error_msg}"
          $stdout.flush
          raise error_msg
        end

        Rails.logger.info "✅ Modelo #{self.ai_model} inicializado com sucesso"
        puts "✅ Modelo #{self.ai_model} inicializado"
        $stdout.flush

      rescue => init_error
        error_msg = "Failed to initialize AI model: #{init_error.message}"
        Rails.logger.error "❌ #{error_msg}"
        Rails.logger.error "Classe: #{init_error.class}"
        Rails.logger.error init_error.backtrace.first(10).join("\n")
        puts "❌ #{error_msg}"
        puts init_error.backtrace.first(5).join("\n")
        $stdout.flush

        sse.write({
          status: "error",
          message: error_msg,
          error_class: init_error.class.name
        }, event: "error")

        raise init_error
      end

      # ⚠️ LOOP COM TRATAMENTO DE ERRO POR ARQUIVO
      files.each_with_index do |file, index|
        filename = file.respond_to?(:original_filename) ? file.original_filename : file.filename.to_s

        begin
          # Log início
          Rails.logger.info "📝 [#{index + 1}/#{total}] Iniciando transcrição: #{filename}"
          puts "📝 [#{index + 1}/#{total}] Transcrevendo: #{filename}"
          $stdout.flush

          # Envia progresso
          sse.write({
            progress: (index.to_f / total * 80 + 10).to_i,
            message: "Transcribing file #{index + 1}/#{total}: #{filename}",
            current_file: index + 1,
            total_files: total
          })

          # Pega o caminho temporário
          temp_path =
            if file.is_a?(ActionDispatch::Http::UploadedFile)
              file.tempfile.path
            else
              file.open(&:path)
            end

          result = ai_instance.transcribe(audio_path: temp_path)

          # Sucesso!
          transcriptions << {
            filename: filename,
            result: result,
            status: "success"
          }

          Rails.logger.info "✅ [#{index + 1}/#{total}] Transcrição concluída: #{filename}"
          puts "✅ [#{index + 1}/#{total}] Concluído: #{filename}"
          $stdout.flush

        rescue => file_error
          # ⚠️ CAPTURA ERRO ESPECÍFICO DO ARQUIVO
          error_message = "Error transcribing '#{filename}': #{file_error.message}"

          Rails.logger.error "❌ [#{index + 1}/#{total}] #{error_message}"
          Rails.logger.error "   Classe do erro: #{file_error.class}"
          Rails.logger.error "   Backtrace:"
          Rails.logger.error file_error.backtrace.first(15).join("\n")

          puts "❌ [#{index + 1}/#{total}] ERRO: #{filename}"
          puts "   Mensagem: #{file_error.message}"
          puts "   Tipo: #{file_error.class}"
          puts "   Backtrace:"
          puts file_error.backtrace.first(10).join("\n")
          $stdout.flush

          # Envia erro via SSE para o frontend
          sse.write({
            status: "file_error",
            message: error_message,
            error_class: file_error.class.name,
            file: filename,
            file_index: index + 1,
            total_files: total,
            backtrace: file_error.backtrace.first(3)
          }, event: "file_error")

          # Adiciona resultado com erro
          transcriptions << {
            filename: filename,
            error: file_error.message,
            error_class: file_error.class.name,
            status: "error"
          }

          # ⚠️ DECISÃO: Continuar ou parar?
          # Opção 1: Continuar com próximos arquivos (recomendado para múltiplos arquivos)
          next

          # Opção 2: Parar tudo no primeiro erro (descomente se preferir)
          # raise file_error
        end
      end

      # Envia todos os resultados (sucessos e erros)
      if transcriptions.any?
        successful = transcriptions.count { |t| t[:status] == "success" }
        failed = transcriptions.count { |t| t[:status] == "error" }

        Rails.logger.info "📊 Resumo: #{successful} sucesso(s), #{failed} erro(s)"
        puts "📊 Resumo: #{successful} sucesso(s), #{failed} erro(s)"
        $stdout.flush

        sse.write({
          status: "transcriptions-result",
          data: transcriptions,
          summary: {
            total: total,
            successful: successful,
            failed: failed
          }
        }, event: "transcriptions-result")
      end
    end
  end
end
