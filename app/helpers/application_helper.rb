module ApplicationHelper
  def current_date_and_time
    Time.now.strftime("%A, %B %d, %Y, %H:%M")
  end
  def markdown_to_html(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      filter_html: false,
      no_links: false,
      no_images: false
    )

    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true
    )

    raw markdown.render(text)
  end
end
