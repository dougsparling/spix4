require './websocket'

# Avoids mysterious failures with Thin involving "Sec-WebSocket-Accept is invalid"
# https://github.com/faye/faye-websocket-ruby?tab=readme-ov-file#running-your-socket-application
Faye::WebSocket.load_adapter('thin')

use WSServer
use Rack::Static, urls: [''], root: 'static', index: 'index.html', cascade: true

run ->(_) { [404, { 'Content-Type' => 'text/plain' }, ['Not Found']] }
