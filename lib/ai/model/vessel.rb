module Ai
  module Model
    class Vessel
      include Ai::Model::Logging

      attr_accessor :link, :model

      SYSTEM_MESSAGE = ""

      def self.ai_resource_type
        "vessel"
      end

      def self.rag?
        false
      end

      def initialize(link, model: "vessel")
        @link = link
        @model = "vessel"

        log_info(__method__, "WEB SCRAPPING com modelo=#{@model}, timeout=#{@timeout}s")
      end

      def ask(prompt = "")
        content = ""

        scraper = WebScraper::Vessel.new(@link, timeout: 60)
        html = scraper.fetch

        doc_body = Nokogiri::HTML(html).at("body")

        # Remove tags estruturais e não desejadas
        doc_body.css("script, form, textarea, button, header, footer, nav, style").remove

        # Remove comentários
        doc_body.xpath("//comment()").remove

        # Remove <a> sem texto ou com href inválido
        doc_body.css("a").each do |a|
          href = a["href"].to_s.strip
          text = a.text.strip
          if href.empty? || href == "about:blank" || href.start_with?("javascript") || text.empty?
            a.remove
          end
        end

        # Remove imagens base64
        doc_body.css("img").each do |img|
          src = img["src"].to_s
          img.remove if src.start_with?("data:image")
        end

        # Remove elementos vazios
        doc_body.xpath("//*[not(node())]").remove

        doc_body
      end

      def upload_file(file:, purpose: "tool_use")
        # Skipping file uploading...
      end

      def system_message
        # Skipping system message...
      end

      def response_content(response)
        response
      end
    end
  end
end
