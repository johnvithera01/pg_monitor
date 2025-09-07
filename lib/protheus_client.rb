# lib/protheus_client.rb
require 'net/http'
require 'uri'
require 'json'
require 'oauth'

class ProtheusClient
  def self.create(base_url:, auth: 'oauth1', **cfg)
    client = new(base_url: base_url, auth: auth)
    
    case auth
    when 'oauth1'
      client.configure_oauth(
        consumer_key: cfg[:consumer_key] || ENV['PROTHEUS_CONSUMER_KEY'],
        consumer_secret: cfg[:consumer_secret] || ENV['PROTHEUS_CONSUMER_SECRET'],
        token: cfg[:token] || ENV['PROTHEUS_TOKEN'],
        token_secret: cfg[:token_secret] || ENV['PROTHEUS_TOKEN_SECRET']
      )
    when 'bearer'
      client.configure_bearer(token: cfg[:bearer_token] || ENV['PROTHEUS_BEARER_TOKEN'])
    else
      raise "Auth desconhecida: #{auth}"
    end
    
    client
  end

  def initialize(base_url:, auth: 'oauth1')
    @base = base_url.to_s.sub(%r{/$}, '')
    @auth = auth
  end

  def configure_oauth(consumer_key:, consumer_secret:, token:, token_secret:)
    @consumer = OAuth::Consumer.new(consumer_key, consumer_secret, site: @base)
    @access = OAuth::AccessToken.new(@consumer, token, token_secret)
  end

  def configure_bearer(token:)
    @bearer = token
  end

  # endpoint: caminho como '/rest/MI/ZZALERTA'
  def create_incident(endpoint, payload)
    post_json(endpoint, payload)
  end

  def update_incident(endpoint, id, payload)
    put_json(File.join(endpoint, id.to_s), payload)
  end

  private

  def post_json(path, obj)
    request_json(:post, path, obj)
  end

  def put_json(path, obj)
    request_json(:put, path, obj)
  end

  def request_json(method, path, obj)
    url = URI.parse(@base + path)

    if @auth == 'oauth1'
      headers = { 'Content-Type' => 'application/json' }
      body = obj.to_json
      return @access.request(method, path, body, headers)
    end

    # Bearer Token
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = (url.scheme == 'https')

    req = (method == :post ? Net::HTTP::Post.new(url) : Net::HTTP::Put.new(url))
    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{@bearer}"
    req.body = obj.to_json

    http.request(req)
  end
end