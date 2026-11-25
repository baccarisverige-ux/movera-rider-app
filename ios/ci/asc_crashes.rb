# Prints TestFlight crash feedback for the app (App Store Connect API, read only). No secrets printed.
require 'spaceship'
require 'net/http'
require 'json'
tok = Spaceship::ConnectAPI::Token.create(key_id: ENV.fetch('ASC_KEY_ID'), issuer_id: ENV.fetch('ASC_ISSUER_ID'), filepath: ENV.fetch('ASC_KEY_PATH'))
def get(tok, path)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP::Get.new(uri); req['Authorization'] = "Bearer #{tok.text}"
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  puts "GET #{path.split('?').first} -> #{res.code}"
  res.code.to_i == 200 ? JSON.parse(res.body) : (puts res.body[0, 600]; nil)
end
app = ENV.fetch('APP_APPLE_ID')
subs = get(tok, "/v1/apps/#{app}/betaFeedbackCrashSubmissions?limit=10")
(subs && subs['data'] || []).each do |s|
  a = s['attributes']
  puts "crash #{s['id']} #{a['createdDate']} build=#{a['buildBundleId']} device=#{a['deviceModel']} os=#{a['osVersion']} comment=#{a['comment']}"
  log = get(tok, "/v1/betaFeedbackCrashSubmissions/#{s['id']}/crashLog")
  if log
    text = log.dig('data', 'attributes', 'logText').to_s
    File.write("crash-#{s['id']}.txt", text)
    puts text.lines.first(140).join
  end
end
