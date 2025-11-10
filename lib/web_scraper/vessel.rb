# lib/web_scraper/vessel.rb
require "vessel"
require "uri"

module WebScraper
  class Vessel
    attr_reader :url, :timeout

    def initialize(url, timeout: 30)
      @url = url
      @timeout = timeout
    end

    def fetch
      html_result = nil
      target_url = url  # Variável local acessível no bloco
      timeout_value = timeout

      dynamic_cargo = Class.new(::Vessel::Cargo) do
        domain URI.parse(target_url).host
        start_urls target_url
        timeout timeout_value

        define_method(:parse) do
          html_result = page.body
        end
      end

      dynamic_cargo.run
      html_result
    rescue => e
      Rails.logger.error("WebScraper::Vessel error: #{e.message}\n#{e.backtrace.join("\n")}")
      nil
    end
  end
end
