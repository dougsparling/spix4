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

class WSWindow < BaseWindow
  def initialize(ws)
    super()
    @ws = ws
  end

  def blank
    # no-op
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
  end

  def line(text, width: 0, margin: 0, color: nil)
    send(:line, { text:, color: })
  end

  def prompt(label = '')
    send(:prompt, { label: })
  end

  def para(text, width: 0, margin: 0)
    send(:line, { text:, color: 'primary' })
  end

  def newline
    # no-op
  end

  def pause
    # no-op
  end

  def send(type, data = {})
    puts "#{type}: #{data}"
    @ws.send({ type:, data: }.to_json)
  end
end

WSServer = lambda do |env|
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    bridge = WSWindow.new(ws)
    scenes = SceneOwner.new(bridge)
    scenes.proceed_to :title

    Thread.new do
      # TODO: kinda need something like a coroutine here to suspend awaiting user input ... ws.on(:message) maybe?
      scenes.loop_once
    end

    ws.on :message do |event|
      # TODO
    end

    ws.on :error do |event|
      p [:close, event.code, event.reason]
    end

    ws.on :close do |event|
      p [:close, event.code, event.reason]
      ws = nil
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
