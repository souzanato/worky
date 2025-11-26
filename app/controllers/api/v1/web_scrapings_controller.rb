class Api::V1::WebScrapingsController < ApplicationController
  before_action :restrict_access
  before_action :ensure_json_request

  include Api::V1::WebScraping

  def show
    begin
      html = page_html(Base64.strict_decode64(params[:id]))
      result = page_text(html)

      render json: { result: result&.dig(:text) }
    rescue Exception => e
      render json: { result: "ERROR", error: e.to_s }
    end
  end

  def create
  end

  private

  # Garante que somente JSON é aceito
  def ensure_json_request
    unless request.format.json?
      raise "Invalid request: only JSON is accepted."
    end
  end

  private

  def restrict_access
    token = request.headers["Authorization"]
    unless AccessToken.exists?(token: token)
      respond_to do |format|
        format.json { render json: { result: "Invalid Token" }, status: :forbidden }
      end
    end
  end
end
