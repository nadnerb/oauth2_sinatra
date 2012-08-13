require 'rubygems'
require 'sinatra'
require 'oauth2'
require 'json'
require 'rest-client'
require 'octokit'
require 'yajl'

def oauth_domain
  'https://github.com'
end

def ssl_options
  ca_file = "/usr/lib/ssl/certs/ca-certificates.crt"
  if File.exists?(ca_file)
    { :ca_file => ca_file }
  else
    { :ca_file => ''}
  end
end

def client
  @client_id = '30ecd9aece981943e2c0'
  @secret = 'dc6de65c500db6d64a66de52b9dbc3611f744077'
  @client ||= OAuth2::Client.new(@client_id, @secret,
                                 :ssl           => ssl_options,
                                 :site          => oauth_domain,
                                 :token_url     => '/login/oauth/access_token',
                                 :authorize_url => '/login/oauth/authorize')
end

def api_for(code)
  client.auth_code.get_token(code, :redirect_uri => callback_url)
end

def state
  @state ||= Digest::SHA1.hexdigest(rand(36**8).to_s(36))
end

def repos(token)
  @user_info ||= RestClient.get("https://api.github.com/user/repos", :params => {:access_token => token})
end

def user_info_for(token)
  @user_info ||= RestClient.get("https://api.github.com/user", :params => {:access_token => token})
end

def scopes
  ['repo']
end

def authorize_url
  client.auth_code.authorize_url(
    :state        => state,
    :scope        => scopes,
    :redirect_uri => redirect_uri
  )
end

get "/" do
    %(<p><a href="/auth/github">Try to authorize</a>.</p>)
end

get '/auth/github' do
  url = authorize_url
  puts "Redirecting to URL: #{url.inspect}"
  redirect url
end

get '/repo/:name' do
  Octokit.repo(Octokit::Repository.new(params[:name])).to_json
  #github_request("user/repos")
end

get '/following/' do
  Octokit.following('nadnerb').to_json
end

# If the user authorizes it, this request gets your access token
# and makes a successful api call.
get '/auth/github/callback' do
  puts params[:code]
  begin
    access_token = client.auth_code.get_token(params[:code], :redirect_uri => redirect_uri)
    @token = access_token.token
    user = Yajl.load(user_info_for(@token))
    client = Octokit::Client.new(:login => user['login'], :oauth_token => @token)
    #post("/#{user['login']}/repos", {name: 'fooz'}, @token)
    #post("/user/repos", {name: 'fooz'}, @token)
    client.create('foozie').to_json
  rescue OAuth2::Error => e
    %(<p>Outdated ?code=#{params[:code]}:</p><p>#{$!}</p><p><a href="/auth/github">Retry</a></p>)
  end
end

def redirect_uri(path = '/auth/github/callback', query = nil)
  uri = URI.parse(request.url)
  uri.path  = path
  uri.query = query
  uri.to_s
end

def github_request(path, params = {})
  Yajl.load(github_raw_request(path, params))
end

def github_raw_request(path, params = {})
  headers = {:Authorization => "token #{@token}", :accept => :json}
  RestClient.get("#{oauth_domain}/#{path}", headers.merge(:params => params))
end

# couldn't get this to work
def post(path, params, token = @token)
  #headers = {:Authorization => "token #{token}", :content_type => :json, :accept => :json}
  headers = {:Authorization => "bearer #{token}", :content_type => :json, :accept => :json}
  res = RestClient.post("#{oauth_domain}/#{path}", params.to_json, headers)
  Yajl.load(res)
end
