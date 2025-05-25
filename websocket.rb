require 'faye/websocket'
require 'thin'
require 'json'

require './scene'
require './render'
require './foes'
require './roll'
require './items'
require './combat'

require './spix4'

# Class that bridges the window API expected by the game with a websocket
class WSBridge < BaseWindow
  def initialize(ws)
    super()
    @ws = ws
    @incoming = Thread::Queue.new

    ws.on :message do |event|
      puts "received #{event.data}"
      @incoming.push(event.data.chomp)
    end

    # ws.on :error do |_event|
    #   @incoming.close
    # end

    ws.on :close do |_event|
      puts 'incoming closed'
      @incoming.close
    end
  end

  def closed?
    @incoming.closed?
  end

  def blank
    send(:blank)
  end

  def refresh
    # no-op
  end

  def choice(key_or_text, text_with_key = nil, &block)
    key = key_or_text.to_s[0].downcase
    text = text_with_key || key_or_text

    @choices ||= {}
    raise "key #{key} used twice for choice!" if @choices[key]

    @choices[key] = [text, block]
  end

  def dialogue(name, text)
    send(:dialogue, { name:, text: })
  end

  def choose!(action = nil)
    # special case for immediate actions
    unless action.nil?
      immediate = @choices.key?(c)[1]
      @choices.clear
      immediate.call
      return
    end

    choices = @choices.map { |key, choice| { key:, text: choice[0] } }

    send(:choices, choices:)

    until @choices.empty?
      c = receive_latest.downcase
      next unless @choices.key?(c)

      choice = @choices[c][1]
      @choices.clear
      choice.call
    end
  end

  def line(text, width: 0, margin: 0, color: nil)
    send(:line, { text:, color: })
  end

  def prompt(label = '')
    send(:prompt, { label: })
    receive_latest
  end

  def para(text, width: 0, margin: 0)
    send(:line, { text:, color: 'primary' })
  end

  def newline
    # no-op
  end

  def pause
    send(:pause)
  end

  def receive_latest
    @incoming.clear
    @incoming.pop
  end

  def send(type, data = {})
    @ws.send({ type:, data: }.to_json)
  end
end

WSServer = lambda do |env|
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    bridge = WSBridge.new(ws)
    scenes = SceneOwner.new(bridge)
    scenes.proceed_to :title

    Thread.new do
      scenes.loop_once until scenes.game_over? || bridge.closed?
      # TODO: not closing...
      ws.close
    end

    # Return async Rack response
    ws.rack_response

  else
    # show something if browser hits this port
    [200, { 'Content-Type' => 'text/plain' }, ['HOW DO YOU KNOW MY LANGUAGE (expected websocket connection, but was a browser)']]
  end
end

# yeehaw
Faye::WebSocket.load_adapter('thin')
Rack::Handler.get('thin').run(WSServer, port: ENV['port'].to_i || 8080)
