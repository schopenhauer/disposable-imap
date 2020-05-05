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

configure :development do
  use BetterErrors::Middleware
  BetterErrors.application_root = __dir__
end

configure do
  MAIL_DOMAIN = ENV['MAIL_DOMAIN'] || 'example.com'
  MAIL_SERVER = ENV['MAIL_SERVER'] || 'localhost'
  MAIL_PORT = ENV['MAIL_PORT'] || 993
  MAIL_USERNAME = ENV['MAIL_USERNAME']
  MAIL_PASSWORD = ENV['MAIL_PASSWORD']
  LOG_FILE = ENV['LOG_FILE'] || 'history.log'
  LOG_SIZE = ENV['LOG_SIZE'] || 15
  # TODO: AUTO_PURGE = ENV['AUTO_PURGE'] || 30
  INBOX_SIZE = ENV['INBOX_SIZE'] || 15
  DATETIME_FORMAT = '%e %b %Y at %H:%M %Z'
  EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  SALT = SecureRandom.hex
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
  uids = []
  mailbox = params[:q] + '@' + MAIL_DOMAIN
  if !(EMAIL_REGEX.match(mailbox)).nil?
    imap = connect()
    if !imap.nil?
      imap.search(['TO', mailbox]).each do |uid|
        emails << imap.fetch(uid, 'ENVELOPE')[0].attr['ENVELOPE']
        uids << uid
      end
      log(mailbox, request.ip, request.user_agent)
      imap.logout
      imap.disconnect
      erb :inbox, locals: {
        mailbox: mailbox,
        emails: emails,
        uids: uids
      }
    else
      erb :error
    end
  else
    erb :error, locals: {
      msg: 'The server could not process your request. Can you please make sure to enter a valid email address?'
    }
  end
end

get '/email/:uid' do
  imap = connect()
  uid = decrypt(params[:uid]).to_i
  email = imap.fetch(uid, ['ENVELOPE', 'RFC822'])[0]
  mail = Mail.read_from_string(email.attr['RFC822'])
  imap.logout
  imap.disconnect
  erb :email, locals: {
    mail: mail
  }
end

get '/preview/:uid' do
  imap = connect()
  uid = decrypt(params[:uid]).to_i
  email = imap.fetch(uid, ['ENVELOPE', 'RFC822'])[0]
  mail = Mail.read_from_string(email.attr['RFC822'])
  imap.logout
  imap.disconnect
  erb :preview, layout: false, locals: {
    preview: mail.decoded.nil? ? (mail.html_part.nil? ? mail.text_part.decoded : mail.html_part.decoded) : mail.decoded
  }
end

get '/log' do
  history = `tail -n #{LOG_SIZE} #{LOG_FILE}`.split("\n").map { |l| l.split(' - ') }
  history.each { |l| l << geolocate(l[2]) }
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
    r = Faker::Number.number(10)
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
  redirect '/inbox?q=' + r.to_s.gsub(' ', '')
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
  # See also: https://www.rubydoc.info/github/mikel/mail/Mail%2FEncodings.unquote_and_convert_to
  Mail::Encodings.unquote_and_convert_to(str, 'utf-8')
end

def digest(str)
  Digest::SHA256.hexdigest(str)[0, 12]
end

def timestamp(str)
  dt = DateTime.parse(str)
  dt.nil? ? 'n.a.' : dt.strftime(DATETIME_FORMAT)
end

def encrypt(str)
  h = Hashids.new(SALT)
  h.encode(str)
end

def decrypt(str)
  h = Hashids.new(SALT)
  h.decode(str).first
end

def geolocate(keyword)
  result = Geocoder.search(keyword)
  country = result.first.country
  (keyword.nil? || country.nil?) ? 'Unknown' : country
end

private

def log(str, ip, agent)
  timestamp = Time.now.getutc
  File.write(LOG_FILE, "#{timestamp} - #{str} - #{ip} - #{agent}\n", mode: 'a')
end

def connect()
  begin
    imap = Net::IMAP.new(MAIL_SERVER, MAIL_PORT, true)
    imap.authenticate('LOGIN', MAIL_USERNAME, MAIL_PASSWORD)
    imap.select('INBOX')
    imap
  rescue StandardError => e
    puts e.message
    #puts e.backtrace.inspect
  end
end

def partial(template, locals)
  erb(template, layout: false, locals: locals || {})
end
