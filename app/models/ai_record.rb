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
    sse.write({ progress: 20, message: "Analyzing text content..." })
    sleep 1
    sse.write({ progress: 60, message: "Performing semantic analysis..." })
    sleep 1
    sse.write({ progress: 90, message: "Finalizing..." })
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

          # ⚠️ AQUI É ONDE O ERRO DO REPLICATE ACONTECE
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
