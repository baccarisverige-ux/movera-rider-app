# Prints TestFlight tester feedback (screenshot + crash submissions) for the given apps and saves the
# screenshots (App Store Connect API, read only). Ruby stdlib only. Never prints a secret or a tester e-mail.
# Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_IDS ("name=appleId,..."), DAYS, OUT_DIR.
require 'openssl'
require 'net/http'
require 'json'
require 'base64'
require 'time'
require 'fileutils'

def b64u(s) = Base64.urlsafe_encode64(s, padding: false)

def token
  key = OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_PATH')))
  head = { alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }
  now = Time.now.to_i
  body = { iss: ENV.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 1100, aud: 'appstoreconnect-v1' }
  input = "#{b64u(head.to_json)}.#{b64u(body.to_json)}"
  der = OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest.new('SHA256'), input))
  raw = der.value.map { |i| i.value.to_s(2).rjust(32, "\x00")[-32, 32] }.join
  "#{input}.#{b64u(raw)}"
end

TOKEN = token
EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/

def get(url)
  uri = URI(url.start_with?('http') ? url : "https://api.appstoreconnect.apple.com#{url}")
  req = Net::HTTP::Get.new(uri); req['Authorization'] = "Bearer #{TOKEN}"
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  return JSON.parse(res.body) if res.code.to_i == 200
  puts "  GET #{uri.path} -> #{res.code} (#{res.code.to_i == 404 ? 'endpoint or app not found; skipped' : res.body.to_s.gsub(EMAIL, '[email]')[0, 300]})"
  nil
end

def clean(s) = s.to_s.gsub(EMAIL, '[email]').gsub(/\s+/, ' ').strip

def download(url, path)
  uri = URI(url)
  res = Net::HTTP.get_response(uri)
  res.code.to_i == 200 ? (File.binwrite(path, res.body); true) : false
rescue StandardError
  false
end

days = Integer(ENV.fetch('DAYS', '7'))
cutoff = Time.now.utc - days * 86_400
out = ENV.fetch('OUT_DIR', 'testflight-feedback')
FileUtils.mkdir_p(out)
puts "TestFlight feedback since #{cutoff.iso8601} (#{days} days)"

ENV.fetch('APP_IDS').split(',').each do |pair|
  name, app = pair.split('=', 2)
  %w[betaFeedbackScreenshotSubmissions betaFeedbackCrashSubmissions].each do |kind|
    puts "\n== #{name} (#{app}) #{kind} =="
    url = "/v1/apps/#{app}/#{kind}?limit=50&sort=-createdDate&include=build&fields[builds]=version"
    count = 0
    while url
      page = get(url) or break
      builds = (page['included'] || []).select { |i| i['type'] == 'builds' }.to_h { |b| [b['id'], b.dig('attributes', 'version')] }
      stop = false
      (page['data'] || []).each do |s|
        a = s['attributes'] || {}
        created = Time.parse(a['createdDate'].to_s) rescue nil
        (stop = true; break) if created && created < cutoff
        count += 1
        build = builds[s.dig('relationships', 'build', 'data', 'id')] || '?'
        puts "- #{a['createdDate']} build=#{build} device=#{a['deviceModel']} os=#{a['osVersion']} id=#{s['id']}"
        puts "  comment: #{clean(a['comment']).then { |c| c.empty? ? '(none)' : c }}"
        (a['screenshots'] || []).each_with_index do |shot, i|
          file = File.join(out, "#{name}-#{s['id']}-#{i + 1}.png")
          puts "  screenshot: #{download(shot['url'].to_s, file) ? File.basename(file) : 'download failed'}"
        end
      end
      url = stop ? nil : page.dig('links', 'next')
    end
    puts "  (#{count} items)"
  end
end
