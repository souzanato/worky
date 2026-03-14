# app/services/pdf_service.rb

require "net/http"
require "uri"
require "json"

class PdfService
  class Error < StandardError; end
  class ConnectionError < Error; end
  class RequestError < Error; end

  DEFAULT_BASE_URL = ENV.fetch("PDF_SERVICE_URL", "http://localhost:8000")
  DEFAULT_TIMEOUT = 60

  # Timeouts específicos por operação (em segundos)
  OPERATION_TIMEOUTS = {
    extract_full:              300,
    extract_text:              180,
    extract_images:            180,
    render_page:               120,
    render_page_base64:        120,
    render_with_annotations:   300,
    render_annotations_images: 300,
    render_pdf_images:         300,
    extract_metadata:           60,
    extract_annotations:        60,
    extract_bookmarks:          60,
    extract_links:              60,
    split_urls:                300,
    health_check:               10
  }.freeze

  def initialize(base_url: DEFAULT_BASE_URL, timeout: DEFAULT_TIMEOUT)
    @base_url = base_url
    @timeout = timeout
  end

  # Extrai todos os elementos do PDF
  def extract_full(file, include_image_data: false)
    params = { include_image_data: include_image_data }
    post_file("/extract/full", file, params: params, timeout: OPERATION_TIMEOUTS[:extract_full])
  end

  # Extrai apenas metadados
  def extract_metadata(file)
    post_file("/extract/metadata", file, timeout: OPERATION_TIMEOUTS[:extract_metadata])
  end

  # Extrai texto (todo ou página específica)
  def extract_text(file, page: nil)
    params = page ? { page: page } : {}
    post_file("/extract/text", file, params: params, timeout: OPERATION_TIMEOUTS[:extract_text])
  end

  # Extrai imagens
  def extract_images(file, include_data: false, page: nil)
    params = { include_data: include_data }
    params[:page] = page if page
    post_file("/extract/images", file, params: params, timeout: OPERATION_TIMEOUTS[:extract_images])
  end

  # Extrai anotações e comentários
  def extract_annotations(file)
    post_file("/extract/annotations", file, timeout: OPERATION_TIMEOUTS[:extract_annotations])
  end

  def render_with_annotations(file, zoom: 2.0, format: "png", output: "pdf", show_annotations: true, show_comment_popups: false)
    params = {
      zoom: zoom,
      format: format,
      output: output,
      show_annotations: show_annotations,
      show_comment_popups: show_comment_popups
    }
    post_file("/render/all", file, params: params, parse_json: false, timeout: OPERATION_TIMEOUTS[:render_with_annotations])
  end

  def render_annotations_images(file, zoom: 1.5, format: "jpg", show_annotations: true, show_comment_popups: true)
    params = {
      zoom: zoom,
      format: format,
      output: "zip",
      show_annotations: show_annotations,
      show_comment_popups: show_comment_popups
    }
    post_file("/render/all", file, params: params, parse_json: false, timeout: OPERATION_TIMEOUTS[:render_annotations_images])
  end

  # Extrai marcadores (bookmarks/TOC)
  def extract_bookmarks(file)
    post_file("/extract/bookmarks", file, timeout: OPERATION_TIMEOUTS[:extract_bookmarks])
  end

  # Extrai links
  def extract_links(file)
    post_file("/extract/links", file, timeout: OPERATION_TIMEOUTS[:extract_links])
  end

  # Renderiza página como imagem (retorna bytes)
  def render_page(file, page:, zoom: 2.0, format: "png")
    params = { page: page, zoom: zoom, format: format }
    post_file("/render/page", file, params: params, parse_json: false, timeout: OPERATION_TIMEOUTS[:render_page])
  end

  # Renderiza página em base64
  def render_page_base64(file, page:, zoom: 2.0, format: "png")
    params = { page: page, zoom: zoom, format: format }
    post_file("/render/page/base64", file, params: params, timeout: OPERATION_TIMEOUTS[:render_page_base64])
  end

  def render_pdf_images(file, zoom: 1.5, format: "jpg")
    params = {
      zoom: zoom,
      format: format,
      output: "zip",
      show_annotations: false,
      show_comment_popups: false
    }
    post_file("/render/all", file, params: params, parse_json: false, timeout: OPERATION_TIMEOUTS[:render_pdf_images])
  end

  # Divide o PDF em lotes, salva cada chunk no Active Storage e retorna URLs públicas
  # Retorna: { total_pages, pages_per_chunk, num_chunks, chunks: [...] }
  def split_chunks(file, pages_per_chunk: 10)
    params = { pages_per_chunk: pages_per_chunk }
    post_file("/split/chunks", file, params: params, timeout: OPERATION_TIMEOUTS[:split_urls])
  end

  # Health check
  def health_check
    get("/health", timeout: OPERATION_TIMEOUTS[:health_check])
  end

  def healthy?
    health_check["status"] == "healthy"
  rescue
    false
  end

  private

  def get(path, timeout: @timeout)
    uri = URI.parse("#{@base_url}#{path}")
    http = build_http(uri, timeout: timeout)

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"

    execute_request(http, request)
  end

  def post_file(path, file, params: {}, parse_json: true, timeout: @timeout)
    uri = URI.parse("#{@base_url}#{path}")

    unless params.empty?
      uri.query = URI.encode_www_form(params)
    end

    http = build_http(uri, timeout: timeout)
    file_content, filename = prepare_file(file)

    boundary = "----RubyFormBoundary#{SecureRandom.hex(16)}"
    body = build_multipart_body(file_content, filename, boundary)

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    request.body = body

    execute_request(http, request, parse_json: parse_json)
  end

  def build_http(uri, timeout: @timeout)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = timeout
    http
  end

  def prepare_file(file)
    case file
    when ActionDispatch::Http::UploadedFile
      [file.read, file.original_filename]
    when File
      [file.read, File.basename(file.path)]
    when String
      if File.exist?(file)
        [File.read(file, mode: "rb"), File.basename(file)]
      else
        raise ArgumentError, "Arquivo não encontrado: #{file}"
      end
    else
      raise ArgumentError, "Tipo de arquivo não suportado: #{file.class}"
    end
  end

  def build_multipart_body(file_content, filename, boundary)
    body = ""
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
    body << "Content-Type: application/pdf\r\n"
    body << "\r\n"
    body << file_content
    body << "\r\n"
    body << "--#{boundary}--\r\n"
    body
  end

  def execute_request(http, request, parse_json: true)
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      parse_json ? JSON.parse(response.body) : response.body
    when Net::HTTPBadRequest
      error_detail = begin
        JSON.parse(response.body)["detail"]
      rescue
        response.body
      end
      raise RequestError, "Bad Request: #{error_detail}"
    when Net::HTTPServerError
      raise RequestError, "Server Error: #{response.code} - #{response.message}"
    else
      raise RequestError, "HTTP Error: #{response.code} - #{response.message}"
    end
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
    raise ConnectionError, "Não foi possível conectar ao serviço PDF: #{e.message}"
  end
end