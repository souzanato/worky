# config/initializers/openai.rb
OpenAI.configure do |config|
  config.access_token = Settings.reload!.apis.openai.access_token
  config.admin_token = Settings.reload!.apis.openai.admin_token
  config.organization_id = Settings.reload!.apis.openai.organization_id
  config.log_errors = true # Highly recommended in development, so you can see what errors OpenAI is returning. Not recommended in production because it could leak private data to your logs.
end
