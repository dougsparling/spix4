require 'faye/websocket'
require 'eventmachine'
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
      @incoming.push(event.data.chomp)
    end

    ws.on :close do |_event|
      # signal client or network initiated close to the server by closing the queue
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
      immediate = @choices.key?(action)[1]
      @choices.clear
      immediate.call
      return
    end

    choices = @choices.map { |key, choice| { key:, text: choice[0] } }

    send(:choices, choices:)

    until @choices.empty?
      c = receive_latest&.downcase

      # escape scene if user has disconnected (closure of queue causes nil to be dequeued)
      raise 'game over' if c.nil?

      unless @choices.key?(c)
        line "invalid selection: #{c}"
        next
      end

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
    EM.next_tick do
      @ws.send({ type:, data: }.to_json)
    end
  end
end

class WSServer
  KEEPALIVE_TIME = 15 # seconds

  def initialize(app)
    @app = app
  end

  def call(env)
    identity = env['rack.session'][:identity]
    player_storage = File.join(__dir__, 'storage', identity)
    return @app.call(env) unless Faye::WebSocket.websocket?(env) && identity

    ws = Faye::WebSocket.new(env, nil, { ping: KEEPALIVE_TIME })
    bridge = WSBridge.new(ws)

    # TODO: to fix the close issue, maybe the solution is to fully
    # integrate the game's event loop with EventMachine and not
    # run anything outside the reactor. But Thread::Queue is the
    # only shared data the thread touches...
    Thread.new do
      scenes = SceneOwner.new(bridge, player_storage)
      scenes.proceed_to :title
      begin
        scenes.loop_once until scenes.game_over? || bridge.closed?
      rescue StandardError => e
        # if disconnection or any other error happens during a scene, escape the loop
        puts "Caught #{e}, exiting game loop"
        puts e.backtrace
      end

      # Immediately close the WebSocket
      EM.next_tick do
        ws.send({ type: 'quit', data: {} }.to_json)
        ws.close
      end
    end

    ws.rack_response
  end
end
