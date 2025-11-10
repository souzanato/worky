require "nokogiri"
require "uri"

module WebScraper
  class SimpleContentExtractor
    attr_accessor :doc

    def initialize(html)
      @doc = html
    end

    # Retorna:
    # {
    #   text: "TÍTULO\n\nparágrafo...\n\nSUBTÍTULO\n\nparágrafo...\n- item\n- item",
    #   images: ["https://.../img1.jpg", "https://.../img2.png", ...]
    # }
    def extract
      gpt5nano = Ai::Model::Gpt5Nano.new
      result = gpt5nano.ask(self.doc, nil, system_message: system_message)
      result
    end

    private

    def system_message
      prompt = <<-markdown
Você é um conversor especializado de HTML para Markdown. Sua tarefa é converter o código HTML fornecido para formato Markdown seguindo estas regras:

## REGRAS DE CONVERSÃO:
- `<h1>` até `<h6>` → `#` até `######`
- `<p>` → parágrafo com linha em branco
- `<strong>` ou `<b>` → `**texto**`
- `<em>` ou `<i>` → `*texto*`
- `<code>` → `` `código` ``
- `<del>` ou `<s>` → `~~texto~~`
- `<a href="url">texto</a>` → `[texto](url)`
- `<img src="url" alt="alt">` → `![alt](url)`
- `<ul><li>` → `- item`
- `<ol><li>` → `1. item`
- `<blockquote>` → `> texto`
- `<pre><code>` → bloco de código com ```
- `<br>` → dois espaços + nova linha
- `<hr>` → `---`
- Tabelas HTML → tabelas Markdown com pipes |
- Preserve todo o conteúdo textual
- Mantenha hierarquia e estrutura
- Elementos sem equivalente: preserve como HTML inline

## IMPORTANTE:
- Retorne APENAS o Markdown convertido
- Não inclua explicações, comentários ou texto adicional
- Não use blocos de código para envolver o resultado
- Apenas o Markdown puro

## CÓDIGO HTML PARA CONVERTER:
      markdown
      prompt
    end
  end
end
