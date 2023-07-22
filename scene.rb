require 'forwardable'

class SceneOwner
  attr_accessor :player
  attr_reader :window, :state

  def initialize(window)
    @scenes = []
    @window = window
    @state = {}
    @player = nil
  end

  def main_loop
    until @scenes.empty?
      # loop clearing, resetting cursor and re-drawing the scene
      @window.blank
      @scenes.last.enter
      @window.refresh
    end
  end

  def proceed_to(next_scene, *args)
    # e.g. :next_scene -> NextScene class
    scene_type = Object.const_get(next_scene.to_s.split('_').collect(&:capitalize).join)
    scene = scene_type.new(*args)
    # TODO: kinda nasty?
    scene.owner = self
    @scenes.push(scene)
  end

  def replace_to(*next_scenes)
    finish_scene
    next_scenes.each do |scene|
      proceed_to scene
    end
  end

  def finish_scene
    @scenes.pop unless @scenes.empty?
  end

  def dehydrate
    { scene_state: @state, player: @player.dehydrate, scenes: @scenes.map(&:scene_name) }
  end

  def hydrate(hash)
    @state = hash[:scene_state]
    @player = Player.hydrate(hash[:player])
    # TODO: doesn't handle scene args, but okay for now
    @scenes = []
    replace_to(*hash[:scenes].map(&:to_sym))
  end
end

class Scene
  extend Forwardable
  attr_accessor :owner

  def_delegators :window, :choice, :dialogue, :say, :choose!, :line, :para, :newline, :pause, :blank, :prompt
  def_delegators :owner, :proceed_to, :replace_to, :finish_scene

  def window
    @owner.window
  end

  def player
    @owner.player
  end

  def record_roll(*args)
    line = ''
    args.each do |arg|
      if arg.is_a?(Roll)
        line << arg.total.to_s
        line << " (#{arg})" if arg.rolls.size > 1 || arg.modifier > 0
      else
        line << arg
      end
    end
    window.line(line, color: :secondary)
  end

  def scene_name
    underscore(self.class.name)
  end

  def recorder
    method(:record_roll)
  end

  # only called on the initial entry to a scene, not subsequent re-enters
  # (until the scene is popped and entered anew)
  def first_enter
    @did_first_on_enter ||= false
    return if @did_first_on_enter

    yield
    @did_first_on_enter = true
  end

  private

  # shamelessly stolen from active_support
  def underscore(camel_cased_word)
    return camel_cased_word unless /[A-Z-]|::/.match?(camel_cased_word)
    word = camel_cased_word.to_s.gsub("::".freeze, "/".freeze)
    word.gsub!(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2'.freeze)
    word.gsub!(/([a-z\d])([A-Z])/, '\1_\2'.freeze)
    word.tr!("-".freeze, "_".freeze)
    word.downcase!
    word
  end

  def self.state_variable(name, initial: nil, shared: false)
    define_method(name) do
      state_key = if shared then :globals else scene_name.to_sym end

      owner.state[state_key] ||= {}
      if owner.state[state_key].key?(name)
        owner.state[state_key][name]
      else
        initial
      end
    end

    define_method("#{name}=") do |new_val|
      state_key = if shared then :globals else scene_name.to_sym end

      # don't store initial values
      owner.state[state_key] ||= {}
      if new_val == initial
        owner.state[state_key].delete(name)
      else
        owner.state[state_key][name] = new_val
      end
    end
  end
end

class Save < Scene
  def initialize(msg)
    @msg = msg
  end
  def enter
    # pop save scene itself before dehydrate
    finish_scene

    para @msg
    save_file = File.join(__dir__, 'saves', player.name.downcase)
    File.write(save_file, owner.dehydrate.to_json, mode: 'w')
    pause
  end
end

class Load < Scene
  def enter
    saves = Dir[File.join(__dir__, 'saves', '**')]
    if saves.empty?
      para 'No saves found!'
      pause
      finish_scene
      return
    end

    para 'Choose a save:'
    saves.each_with_index do |save, idx|
      name = File.basename(save)
      choice (idx + 1).to_s, name do
        load(save)
      end
    end
    choose!
  end

  def load(file)
    contents = File.read(file)
    hash = JSON.parse(contents, symbolize_names: true)
    owner.hydrate(hash)
  end
end