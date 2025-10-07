class AiRecordsController < ApplicationController
  include ActionController::Live

  def new
    @ai_record = AiRecord.new
  end

  def create
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    @ai_record = AiRecord.new(ai_record_params)
    uploaded_files = params[:ai_record][:source_files] # 👈 pega os arquivos brutos

    sse = SSE.new(response.stream, retry: 300, event: "progress")

    begin
      if @ai_record.valid?
        @ai_record.process_with_sse(sse, uploaded_files: uploaded_files)
      else
        sse.write({ status: "error", message: @ai_record.errors.full_messages.join(", ") }, event: "error")
      end
    rescue => e
      Rails.logger.error "Stream error: #{e.message}"
      sse.write({ status: "error", message: e.message }, event: "error")
    ensure
      sse.close
    end
  end

  private

  def ai_record_params
    params.require(:ai_record).permit(
      :source_type,
      :ai_action,
      :ai_model,
      :content,
      :language,
      source_files: [] # ✅ precisa estar plural e como array
    )
  end
end
