require 'sinatra'
require 'sinatra/config_file'
require 'better_errors'
require 'dotenv/load'
require 'net/imap'
require 'mail'
require 'time'
require 'faker'
require 'geocoder'
require 'hashids'
require 'securerandom'
require 'connection_pool'
require 'digest'

configure :development do
  use BetterErrors::Middleware
  BetterErrors.application_root = __dir__
end

configure do
  MAIL_DOMAIN = ENV['MAIL_DOMAIN'] || 'example.com'
  MAIL_SERVER = ENV['MAIL_SERVER'] || 'localhost'
  MAIL_PORT = ENV['MAIL_PORT']&.to_i || 993
  MAIL_USE_SSL = ENV['MAIL_USE_SSL']&.downcase != 'false' # default to true
  MAIL_USERNAME = ENV['MAIL_USERNAME']
  MAIL_PASSWORD = ENV['MAIL_PASSWORD']
  LOG_FILE = ENV['LOG_FILE'] || 'history.log'
  LOG_SIZE = ENV['LOG_SIZE']&.to_i || 15
  INBOX_SIZE = ENV['INBOX_SIZE']&.to_i || 15
  DATETIME_FORMAT = '%e %b %Y at %H:%M %Z'
  EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  SALT = SecureRandom.hex
  
  # Validate required configuration
  unless MAIL_USERNAME && MAIL_PASSWORD
    puts "ERROR: MAIL_USERNAME and MAIL_PASSWORD environment variables are required"
    exit 1
  end
  
  puts "Connecting to IMAP server: #{MAIL_SERVER}:#{MAIL_PORT} (SSL: #{MAIL_USE_SSL})"
  
  # IMAP connection pool for better performance
  begin
    IMAP_POOL = ConnectionPool.new(size: 5, timeout: 5) do
      create_imap_connection
    end
    puts "IMAP connection pool initialized successfully"
  rescue StandardError => e
    puts "ERROR: Failed to initialize IMAP connection pool: #{e.message}"
    puts "Supported authentication mechanisms: #{get_imap_capabilities}"
    exit 1
  end
end

set :public_folder, 'public'

get '/robots.txt' do
  status 200
  body "User-agent: *\nDisallow: /"
end

get '/' do
  erb :home
end

get '/inbox' do
  redirect params[:q] ? '/inbox/' + params[:q] : '/'
end

get '/inbox/:q' do
  emails = []
  mailbox = params[:q] + '@' + MAIL_DOMAIN
  
  if EMAIL_REGEX.match(mailbox)
    begin
      IMAP_POOL.with do |imap|
        search_results = imap.search(['TO', mailbox])
        search_results.each do |uid|
          envelope = imap.fetch(uid, 'ENVELOPE')[0].attr['ENVELOPE']
          emails << { envelope: envelope, uid: uid }
        end
      end
      log(mailbox, request.ip, request.user_agent)
      
      # Sort by date (newest first) and limit
      emails.sort! { |a, b| (b[:envelope].date || '') <=> (a[:envelope].date || '') }
      emails = emails.first(INBOX_SIZE.to_i)
      
      erb :inbox, locals: {
        mailbox: mailbox,
        emails: emails
      }
    rescue StandardError => e
      puts "IMAP error: #{e.message}"
      erb :error
    end
  else
    erb :error, locals: {
      msg: 'The server could not process your request. Can you please make sure to enter a valid email address?'
    }
  end
end

get '/email/:uid' do
  begin
    uid = decrypt(params[:uid]).to_i
    IMAP_POOL.with do |imap|
      email = imap.fetch(uid, ['ENVELOPE', 'RFC822'])[0]
      mail = Mail.read_from_string(email.attr['RFC822'])
      erb :email, locals: { mail: mail }
    end
  rescue StandardError => e
    puts "Email fetch error: #{e.message}"
    erb :error
  end
end

get '/preview/:uid' do
  begin
    uid = decrypt(params[:uid]).to_i
    IMAP_POOL.with do |imap|
      email = imap.fetch(uid, ['ENVELOPE', 'RFC822'])[0]
      mail = Mail.read_from_string(email.attr['RFC822'])
      preview = mail.decoded.nil? ? (mail.html_part.nil? ? mail.text_part.decoded : mail.html_part.decoded) : mail.decoded
      erb :preview, layout: false, locals: { preview: preview }
    end
  rescue StandardError => e
    puts "Preview fetch error: #{e.message}"
    erb :error, layout: false
  end
end

get '/log' do
  history = `tail -n #{LOG_SIZE} #{LOG_FILE}`.split("\n").map { |l| l.split(' - ') }
  
  # Batch geocoding to improve performance
  ips_to_geolocate = history.map { |l| l[2] }.uniq
  geocoded_cache = {}
  
  ips_to_geolocate.each do |ip|
    geocoded_cache[ip] = geolocate(ip)
  end
  
  history.each { |l| l << geocoded_cache[l[2]] }
  
  erb :log, locals: {
    history: history.reverse
  }
end

get '/random/:type' do
  case params[:type]
  when 'md5'
    r = Faker::Crypto.md5
  when 'sha256'
    r = Faker::Crypto.sha256
  when 'number'
    r = Faker::Number.number(digits: 10)
  when 'ipv4'
    r = Faker::Internet.public_ip_v4_address
  when 'droid'
    r = Faker::Movies::StarWars.droid
  when 'planet'
    r = Faker::Movies::HitchhikersGuideToTheGalaxy.planet
  when 'philosopher'
    r = Faker::GreekPhilosophers.name
  else
    r = Faker::Internet.user_name
  end
  redirect '/inbox?q=' + r.to_s.gsub(' ', '').downcase
end

get '/*' do
  redirect '/'
end

error 500 do
  erb :error, locals: {
    msg: env['sinatra.error'].message
  }
end

public

def qp(str)
  return '' if str.nil? || str.empty?
  # See also: https://www.rubydoc.info/github/mikel/mail/Mail%2FEncodings.unquote_and_convert_to
  Mail::Encodings.unquote_and_convert_to(str, 'utf-8')
rescue StandardError => e
  puts "Encoding error: #{e.message}"
  str.to_s
end

def digest(str)
  return '' if str.nil?
  Digest::SHA256.hexdigest(str.to_s)[0, 12]
end

def timestamp(str)
  return 'n.a.' if str.nil? || str.empty?
  dt = DateTime.parse(str)
  dt.strftime(DATETIME_FORMAT)
rescue ArgumentError
  'n.a.'
end

def encrypt(str)
  return '' if str.nil?
  h = Hashids.new(SALT)
  h.encode(str.to_i)
end

def decrypt(str)
  return 0 if str.nil? || str.empty?
  h = Hashids.new(SALT)
  result = h.decode(str)
  result.empty? ? 0 : result.first
end

def geolocate(keyword)
  return 'Unknown' if keyword.nil? || keyword.empty?
  
  result = Geocoder.search(keyword)
  return 'Unknown' if result.empty?
  
  country = result.first&.country
  country.nil? ? 'Unknown' : country
rescue StandardError => e
  puts "Geocoding error: #{e.message}"
  'Unknown'
end

private

def create_imap_connection
  imap = Net::IMAP.new(MAIL_SERVER, MAIL_PORT, MAIL_USE_SSL)
  
  # Try different authentication methods in order of preference
  auth_methods = [
    -> { imap.login(MAIL_USERNAME, MAIL_PASSWORD) },
    -> { imap.authenticate('PLAIN', MAIL_USERNAME, MAIL_PASSWORD) },
    -> { imap.authenticate('LOGIN', MAIL_USERNAME, MAIL_PASSWORD) },
    -> { imap.authenticate('CRAM-MD5', MAIL_USERNAME, MAIL_PASSWORD) }
  ]
  
  auth_success = false
  last_error = nil
  
  auth_methods.each do |auth_method|
    begin
      auth_method.call
      auth_success = true
      puts "Authentication successful"
      break
    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
      last_error = e
      puts "Authentication method failed: #{e.message}"
      next
    end
  end
  
  unless auth_success
    imap.disconnect rescue nil
    raise "All authentication methods failed. Last error: #{last_error&.message}"
  end
  
  imap.select('INBOX')
  imap
end

def get_imap_capabilities
  begin
    imap = Net::IMAP.new(MAIL_SERVER, MAIL_PORT, MAIL_USE_SSL)
    capabilities = imap.capability
    imap.disconnect
    capabilities.join(', ')
  rescue StandardError => e
    "Unable to retrieve capabilities: #{e.message}"
  end
end

def log(str, ip, agent)
  return if str.nil? || ip.nil? || agent.nil?
  timestamp = Time.now.getutc
  File.write(LOG_FILE, "#{timestamp} - #{str} - #{ip} - #{agent}\n", mode: 'a')
rescue StandardError => e
  puts "Logging error: #{e.message}"
end
