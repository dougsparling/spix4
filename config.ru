require './websocket'
require 'thin'
require 'securerandom'

# Avoids mysterious failures with Thin involving "Sec-WebSocket-Accept is invalid"
# https://github.com/faye/faye-websocket-ruby?tab=readme-ov-file#running-your-socket-application
Faye::WebSocket.load_adapter('thin')

use Rack::Session::Cookie, key: 'rack.session', path: '/', expire_after: 2_592_000, secret: 'not_really_secret', httponly: false
use WSServer
use Rack::Static, urls: [''], root: 'static', index: 'index.html', cascade: true

run lambda { |env|
  case env['PATH_INFO']
  when '/new'
    env['rack.session'][:identity] ||= SecureRandom.hex
    [302, { 'Location' => '/' }, []]
  else
    [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
  end
}
