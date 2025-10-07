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

  def avatar_names
    [
      { file: "default.jpg", name: "Piuco" },
      { file: "user-1.jpg", name: "Tamandré" },
      { file: "user-2.jpg", name: "Zenzito" },
      { file: "user-3.jpg", name: "Racco" },
      { file: "user-4.jpg", name: "Tatugo" },
      { file: "user-5.jpg", name: "Corujita" },
      { file: "user-6.jpg", name: "Raposvaldo" },
      { file: "user-7.jpg", name: "Lorde Sapo" },
      { file: "user-8.jpg", name: "Manatê" },
      { file: "user-9.jpg", name: "Ursílio" },
      { file: "user-10.jpg", name: "Formiguete" },
      { file: "user-11.jpg", name: "Crocant" },
      { file: "user-12.jpg", name: "Onzara" },
      { file: "user-13.jpg", name: "Elefon" },
      { file: "user-14.jpg", name: "Abelita" },
      { file: "user-15.jpg", name: "Maru" },
      { file: "user-16.jpg", name: "Tartulina" },
      { file: "user-17.jpg", name: "Azulina" },
      { file: "user-18.jpg", name: "Cisnara" },
      { file: "user-19.jpg", name: "Kangura" },
      { file: "user-20.jpg", name: "Giraldina" }
    ]
  end

  def avatar_name(filename)
    avatar_names.find { |a| a[:file] == filename }&.dig(:name)
  end
end
