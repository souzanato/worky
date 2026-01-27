# OpenRouter Ruby Client

Cliente Ruby completo para a API do OpenRouter, com suporte a todos os recursos principais da API.

## Instalação

Simplesmente copie o arquivo `openrouter_client.rb` para o seu projeto.

### Dependências

Esta biblioteca usa apenas bibliotecas padrão do Ruby:
- `net/http` - Para requisições HTTP
- `uri` - Para manipulação de URLs
- `json` - Para parsing JSON

## Início Rápido

```ruby
require_relative 'openrouter_client'

# Inicializar o cliente
client = OpenRouterClient.new(
  api_key: 'sua-chave-api-aqui',
  site_url: 'https://seu-site.com',  # Opcional
  site_name: 'Seu App'                # Opcional
)

# Fazer uma requisição simples
response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [
    { role: 'user', content: 'Olá, como você está?' }
  ]
)

puts response[:choices][0][:message][:content]
```

## Recursos

### ✅ Suporte Completo à API

- **Chat Completions** - Requisições padrão e streaming
- **Múltiplos modelos** - Suporte a qualquer modelo do OpenRouter
- **Tool Calling** - Chamada de ferramentas/funções
- **Vision** - Suporte a imagens
- **Response Format** - JSON estruturado
- **Assistant Prefill** - Completar respostas parciais
- **Estatísticas** - Buscar custos e tokens de gerações
- **Model Routing** - Fallback entre múltiplos modelos

### 🚀 Funcionalidades

- Requisições streaming com blocos Ruby
- Helpers para criar mensagens e ferramentas
- Tratamento de erros robusto
- Suporte a todos os parâmetros da API
- Normalização de respostas

## Documentação Completa

### Inicialização

```ruby
client = OpenRouterClient.new(
  api_key: 'sua-chave-api-aqui',     # Obrigatório
  site_url: 'https://seu-site.com',  # Opcional - para rankings
  site_name: 'Seu App'                # Opcional - para rankings
)
```

### Métodos Principais

#### `chat_completion`

Método principal para fazer requisições de chat completions.

**Parâmetros:**

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| `messages` | Array | Array de mensagens (role, content) |
| `prompt` | String | Alternativa a messages para prompt simples |
| `model` | String | ID do modelo (padrão: 'openai/gpt-4o') |
| `stream` | Boolean | Habilitar streaming |
| `max_tokens` | Integer | Número máximo de tokens |
| `temperature` | Float | Temperatura (0-2) |
| `top_p` | Float | Amostragem nucleus (0-1) |
| `top_k` | Integer | Amostragem top-k |
| `frequency_penalty` | Float | Penalidade de frequência (-2 a 2) |
| `presence_penalty` | Float | Penalidade de presença (-2 a 2) |
| `repetition_penalty` | Float | Penalidade de repetição (0-2) |
| `seed` | Integer | Seed para reprodutibilidade |
| `stop` | String/Array | Sequências de parada |
| `response_format` | Hash | `{ type: 'json_object' }` para JSON |
| `tools` | Array | Array de ferramentas |
| `tool_choice` | String/Hash | Controle de chamada de ferramentas |
| `transforms` | Array | Transformações de prompt |
| `models` | Array | Lista de modelos para fallback |
| `route` | String | Estratégia de roteamento ('fallback') |
| `provider` | Hash | Preferências de provedor |
| `user` | String | ID do usuário final |
| `logit_bias` | Hash | Ajuste de probabilidades |
| `top_logprobs` | Integer | Número de logprobs |
| `min_p` | Float | Amostragem min-p (0-1) |
| `top_a` | Float | Amostragem top-a (0-1) |
| `prediction` | Hash | Saída prevista para reduzir latência |
| `debug` | Hash | Opções de debug |

**Exemplos:**

```ruby
# Requisição básica
response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [
    { role: 'user', content: 'Olá!' }
  ]
)

# Com parâmetros avançados
response = client.chat_completion(
  model: 'anthropic/claude-3.5-sonnet',
  messages: [
    { role: 'system', content: 'Você é um assistente prestativo.' },
    { role: 'user', content: 'Me ajude com isso...' }
  ],
  temperature: 0.7,
  max_tokens: 500,
  top_p: 0.9
)

# Streaming
client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [{ role: 'user', content: 'Conte uma história' }],
  stream: true
) do |chunk|
  content = chunk.dig(:choices, 0, :delta, :content)
  print content if content
end
```

#### `get_generation`

Busca informações detalhadas sobre uma geração específica.

```ruby
# Obter ID da geração
response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [{ role: 'user', content: 'Olá' }]
)

generation_id = response[:id]

# Buscar estatísticas
stats = client.get_generation(generation_id)
puts stats[:tokens_prompt]
puts stats[:tokens_completion]
puts stats[:native_tokens_prompt]
puts stats[:native_tokens_completion]
puts stats[:total_cost]
```

#### `list_models`

Lista todos os modelos disponíveis.

```ruby
models = client.list_models

models[:data].each do |model|
  puts "#{model[:id]} - #{model[:name]}"
  puts "  Contexto: #{model[:context_length]} tokens"
  puts "  Preço: $#{model[:pricing][:prompt]} por token"
end
```

### Métodos Helper

#### `OpenRouterClient.create_message`

Cria uma mensagem formatada.

```ruby
message = OpenRouterClient.create_message(
  role: 'user',
  content: 'Olá, mundo!',
  name: 'João'  # Opcional
)
```

#### `OpenRouterClient.create_image_message`

Cria uma mensagem com imagem.

```ruby
# Com texto e imagem
message = OpenRouterClient.create_image_message(
  role: 'user',
  text: 'O que você vê nesta imagem?',
  image_url: 'https://exemplo.com/imagem.jpg',
  detail: 'high'  # 'low', 'high', ou 'auto'
)

# Apenas imagem
message = OpenRouterClient.create_image_message(
  image_url: 'data:image/jpeg;base64,/9j/4AAQSkZJRg...'
)
```

#### `OpenRouterClient.create_tool`

Cria uma ferramenta (tool) para chamada de funções.

```ruby
tool = OpenRouterClient.create_tool(
  name: 'get_weather',
  description: 'Obtém a previsão do tempo',
  parameters: {
    type: 'object',
    properties: {
      location: {
        type: 'string',
        description: 'A cidade e estado'
      },
      unit: {
        type: 'string',
        enum: ['celsius', 'fahrenheit']
      }
    },
    required: ['location']
  }
)

response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [
    { role: 'user', content: 'Qual a temperatura em São Paulo?' }
  ],
  tools: [tool]
)
```

## Exemplos de Uso

### 1. Chat Simples

```ruby
response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [
    { role: 'user', content: 'Explique Ruby em uma frase.' }
  ]
)

puts response[:choices][0][:message][:content]
```

### 2. Conversação Multi-turn

```ruby
messages = [
  { role: 'system', content: 'Você é um tutor de programação.' },
  { role: 'user', content: 'O que são closures?' },
  { role: 'assistant', content: 'Closures são...' },
  { role: 'user', content: 'Pode dar um exemplo em Ruby?' }
]

response = client.chat_completion(
  model: 'anthropic/claude-3.5-sonnet',
  messages: messages
)
```

### 3. JSON Estruturado

```ruby
response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [
    { 
      role: 'user', 
      content: 'Liste 3 frameworks Ruby populares em JSON com nome e descrição' 
    }
  ],
  response_format: { type: 'json_object' }
)

data = JSON.parse(response[:choices][0][:message][:content])
```

### 4. Streaming em Tempo Real

```ruby
print "Resposta: "

client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [
    { role: 'user', content: 'Conte uma piada de programação' }
  ],
  stream: true
) do |chunk|
  if content = chunk.dig(:choices, 0, :delta, :content)
    print content
    $stdout.flush
  end
end

puts "\n"
```

### 5. Análise de Imagem

```ruby
message = OpenRouterClient.create_image_message(
  text: 'Descreva esta imagem em detalhes',
  image_url: 'https://exemplo.com/foto.jpg',
  detail: 'high'
)

response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [message]
)
```

### 6. Tool Calling Completo

```ruby
# Definir ferramentas
tools = [
  OpenRouterClient.create_tool(
    name: 'search_database',
    description: 'Busca informações no banco de dados',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Termo de busca' }
      },
      required: ['query']
    }
  )
]

# Primeira chamada
response = client.chat_completion(
  model: 'openai/gpt-4o',
  messages: [
    { role: 'user', content: 'Busque informações sobre Ruby' }
  ],
  tools: tools
)

# Verificar se houve chamada de ferramenta
if tool_calls = response[:choices][0][:message][:tool_calls]
  tool_call = tool_calls[0]
  
  # Simular execução da ferramenta
  tool_result = { results: ['Ruby é uma linguagem...'] }
  
  # Segunda chamada com resultado
  final_response = client.chat_completion(
    model: 'openai/gpt-4o',
    messages: [
      { role: 'user', content: 'Busque informações sobre Ruby' },
      response[:choices][0][:message],
      {
        role: 'tool',
        tool_call_id: tool_call[:id],
        content: tool_result.to_json
      }
    ],
    tools: tools
  )
end
```

### 7. Fallback Entre Modelos

```ruby
response = client.chat_completion(
  models: [
    'openai/gpt-4o',
    'anthropic/claude-3.5-sonnet',
    'google/gemini-pro'
  ],
  route: 'fallback',
  messages: [
    { role: 'user', content: 'Olá!' }
  ]
)

puts "Modelo usado: #{response[:model]}"
```

### 8. Assistant Prefill

```ruby
response = client.chat_completion(
  model: 'anthropic/claude-3.5-sonnet',
  messages: [
    { role: 'user', content: 'Escreva um poema sobre tecnologia' },
    { role: 'assistant', content: 'No reino digital onde' }
  ]
)
```

## Tratamento de Erros

```ruby
begin
  response = client.chat_completion(
    model: 'modelo-invalido',
    messages: [{ role: 'user', content: 'teste' }]
  )
rescue => e
  puts "Erro: #{e.message}"
  
  # Você pode extrair mais informações do erro se necessário
  if e.message.include?('429')
    puts "Rate limit atingido. Aguarde antes de tentar novamente."
  elsif e.message.include?('401')
    puts "Chave de API inválida."
  end
end
```

## Resposta da API

A resposta segue o formato OpenAI:

```ruby
{
  id: "gen-xxxxxxxxxxxxxx",
  choices: [
    {
      finish_reason: "stop",
      native_finish_reason: "stop",
      message: {
        role: "assistant",
        content: "Olá! Como posso ajudar?"
      }
    }
  ],
  created: 1234567890,
  model: "openai/gpt-4o",
  object: "chat.completion",
  usage: {
    prompt_tokens: 10,
    completion_tokens: 20,
    total_tokens: 30
  }
}
```

### Acessando a Resposta

```ruby
response = client.chat_completion(...)

# Conteúdo da resposta
content = response[:choices][0][:message][:content]

# Tokens usados
total_tokens = response[:usage][:total_tokens]

# ID da geração (para buscar stats depois)
generation_id = response[:id]

# Modelo usado
model_used = response[:model]

# Motivo de término
finish_reason = response[:choices][0][:finish_reason]
```

## Modelos Disponíveis

Alguns modelos populares:

- `openai/gpt-4o` - GPT-4 Omni da OpenAI
- `openai/gpt-4-turbo` - GPT-4 Turbo
- `openai/gpt-3.5-turbo` - GPT-3.5 Turbo
- `anthropic/claude-3.5-sonnet` - Claude 3.5 Sonnet
- `anthropic/claude-3-opus` - Claude 3 Opus
- `google/gemini-pro` - Gemini Pro
- `meta-llama/llama-3.1-405b-instruct` - Llama 3.1 405B

Use `client.list_models` para ver todos os modelos disponíveis.

## Notas Importantes

1. **Tokens**: Os tokens retornados na resposta são normalizados (usando tokenizer GPT-4o). Para contagem nativa, use `get_generation`.

2. **Streaming**: No modo streaming, você receberá um hash `usage` no final com um array `choices` vazio.

3. **Rate Limits**: A API possui rate limits. Implemente retry logic se necessário.

4. **Custos**: Use `get_generation` para obter custos precisos de cada requisição.

5. **Parâmetros**: Parâmetros não suportados pelo modelo escolhido são ignorados automaticamente.

## Contribuindo

Sinta-se livre para melhorar este cliente! Algumas ideias:

- Adicionar retry automático com backoff exponencial
- Cache de respostas
- Logging mais detalhado
- Validação de parâmetros
- Testes unitários

## Licença

Este código é fornecido como está, sem garantias. Use por sua conta e risco.

## Links Úteis

- [Documentação OpenRouter](https://openrouter.ai/docs)
- [Lista de Modelos](https://openrouter.ai/models)
- [API Reference](https://openrouter.ai/docs/api-reference)
- [Pricing](https://openrouter.ai/docs/pricing)

## Suporte

Para questões sobre a API OpenRouter, visite a [documentação oficial](https://openrouter.ai/docs).