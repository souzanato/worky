Pinecone.configure do |config|
  config.api_key = Settings.reload!.apis.pinecone.api_key
  config.host = Settings.reload!.apis.pinecone.index_name
end
