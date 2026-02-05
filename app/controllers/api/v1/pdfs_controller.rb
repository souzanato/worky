# app/controllers/api/v1/pdfs_controller.rb

module Api
  module V1
    class PdfsController < ApplicationController
      skip_before_action :verify_authenticity_token

      before_action :validate_file_presence, except: [:health]
      before_action :validate_pdf_file, except: [:health]

      # GET /api/v1/pdfs/health
      def health
        if pdf_service.healthy?
          render json: { status: "healthy", microservice: "connected" }
        else
          render json: { status: "unhealthy", microservice: "disconnected" }, status: :service_unavailable
        end
      end

      # POST /api/v1/pdfs/extract_full
      def extract_full
        include_images = params[:include_image_data] == "true"
        result = pdf_service.extract_full(uploaded_file, include_image_data: include_images)
        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/extract_text
      def extract_text
        page = params[:page]&.to_i
        result = pdf_service.extract_text(uploaded_file, page: page)
        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/extract_images
      def extract_images
        include_data = params[:include_data] == "true"
        page = params[:page]&.to_i
        result = pdf_service.extract_images(uploaded_file, include_data: include_data, page: page)
        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/extract_annotations
      def extract_annotations
        result = pdf_service.extract_annotations(uploaded_file)
        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/extract_bookmarks
      def extract_bookmarks
        result = pdf_service.extract_bookmarks(uploaded_file)
        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/extract_links
      def extract_links
        result = pdf_service.extract_links(uploaded_file)
        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/render_page
      def render_page
        page = params[:page]&.to_i || 1
        zoom = params[:zoom]&.to_f || 2.0
        format = params[:format] || "png"

        image_data = pdf_service.render_page(
          uploaded_file,
          page: page,
          zoom: zoom,
          format: format
        )

        content_type = format == "jpg" ? "image/jpeg" : "image/png"
        send_data image_data, type: content_type, disposition: "inline"
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/render_page_base64
      def render_page_base64
        page = params[:page]&.to_i || 1
        zoom = params[:zoom]&.to_f || 2.0
        format = params[:format] || "png"

        result = pdf_service.render_page_base64(
          uploaded_file,
          page: page,
          zoom: zoom,
          format: format
        )

        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      private

      def pdf_service
        @pdf_service ||= PdfService.new
      end

      def uploaded_file
        params[:file]
      end

      def validate_file_presence
        return if uploaded_file.present?
        render json: { error: "Arquivo PDF é obrigatório" }, status: :bad_request
      end

      def validate_pdf_file
        return if uploaded_file.content_type == "application/pdf"
        return if uploaded_file.original_filename&.downcase&.end_with?(".pdf")
        render json: { error: "Arquivo deve ser um PDF" }, status: :bad_request
      end
    end
  end
end