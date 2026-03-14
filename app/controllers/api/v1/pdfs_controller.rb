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

      def render_with_annotations
        zoom = params[:zoom]&.to_f || 2.0
        format = params[:format] || "png"
        show_annotations = boolean_param(params[:show_annotations], default: true)
        show_comment_popups = boolean_param(params[:show_comment_popups], default: true)

        pdf_data = pdf_service.render_with_annotations(
          uploaded_file,
          zoom: zoom,
          format: format,
          output: "pdf",
          show_annotations: show_annotations,
          show_comment_popups: show_comment_popups
        )

        rendered_pdf = RenderedPdf.create!

        rendered_pdf.file.attach(
          io: StringIO.new(pdf_data),
          filename: rendered_pdf_filename,
          content_type: "application/pdf"
        )

        render json: {
          id: rendered_pdf.id,
          url: rails_blob_url(rendered_pdf.file, only_path: false)
        }, status: :created
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/render_annotations_images
      def render_annotations_images
        zoom = params[:zoom]&.to_f || 2.0
        format = params[:format] || "png"
        show_annotations = boolean_param(params[:show_annotations], default: true)
        show_comment_popups = boolean_param(params[:show_comment_popups], default: true)

        zip_data = pdf_service.render_annotations_images(
          uploaded_file,
          zoom: zoom,
          format: format,
          show_annotations: show_annotations,
          show_comment_popups: show_comment_popups
        )

        rendered = RenderedPdf.create!

        rendered.file.attach(
          io: StringIO.new(zip_data),
          filename: rendered_zip_filename,
          content_type: "application/zip"
        )

        render json: {
          id: rendered.id,
          url: rails_blob_url(rendered.file, only_path: false)
        }, status: :created
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

      # POST /api/v1/pdfs/render_pdf_images
      def render_pdf_images
        zoom = params[:zoom]&.to_f || 2.0
        format = params[:format] || "png"

        zip_data = pdf_service.render_pdf_images(
          uploaded_file,
          zoom: zoom,
          format: format
        )

        rendered = RenderedPdf.create!

        rendered.file.attach(
          io: StringIO.new(zip_data),
          filename: rendered_zip_filename,
          content_type: "application/zip"
        )

        render json: {
          id: rendered.id,
          url: rails_blob_url(rendered.file, only_path: false)
        }, status: :created
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/pdfs/split_urls
      def split_urls
        pages_per_chunk = params[:pages_per_chunk]&.to_i || 10
        result = pdf_service.split_urls(uploaded_file, pages_per_chunk: pages_per_chunk)
        render json: result
      rescue PdfService::Error => e
        render json: { error: e.message }, status: :service_unavailable
      end

      private

      def rendered_pdf_filename
        original_name = uploaded_file.original_filename || "arquivo.pdf"
        base_name = File.basename(original_name, ".pdf")
        "#{base_name}-renderizado.pdf"
      end

      def boolean_param(value, default:)
        return default if value.nil?
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def rendered_zip_filename
        original_name = uploaded_file.original_filename || "arquivo.pdf"
        base_name = File.basename(original_name, ".pdf")
        "#{base_name}-imagens.zip"
      end

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