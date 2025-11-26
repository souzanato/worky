module Api::V1::WebScraping
  def page_html(url)
      scraper = WebScraper::Vessel.new(url, timeout: 60)
      scraper.fetch
  end

  def page_text(html)
      nano = Ai::Model::Gpt5Nano.new
      nano.ask(html, nil, system_message: system_prompt)
  end

  def system_prompt
    system_prompt = <<-markdown
      You will receive an HTML document as input.

      Your task is to **extract only the meaningful informational content**, removing everything that is not semantically relevant.

      ### ❌ Ignore and DO NOT include:
      - Navigation bars, menus, sidebars
      - Headers, footers
      - Banners, ads, pop-ups
      - Scripts, styles, tracking elements
      - Social media widgets or icons
      - Layout containers (divs, sections, grids)
      - Repeated boilerplate elements
      - Images used only for decoration
      - Cookie banners or GDPR notices
      - Any content unrelated to the main textual information

      ### ✅ KEEP and return ONLY:
      - The main textual content of the page
      - Titles and subtitles that relate to the core content
      - Articles, blog posts, descriptions, definitions, documentation
      - Meaningful tables or lists (only if they contain relevant data)
      - Important links that contribute to the informational value (optional)

      ### Output format:
      - Return the extracted content **in clean Markdown**
      - Preserve hierarchy with headings when meaningful
      - Remove all HTML tags
      - Rewrite poorly formatted text for clarity when necessary
      - Do NOT invent or hallucinate missing information

      ### Final instructions:
      - If the HTML contains mostly irrelevant content, return only what is meaningful.
      - If no meaningful information exists, respond: “No relevant content found.”

      Now wait for the input HTML.
    markdown

    system_prompt
  end
end
