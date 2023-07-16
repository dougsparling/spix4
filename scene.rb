require 'forwardable'

class SceneOwner
  attr_reader :window, :player, :state
  attr_writer :player

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
    { scene_state: @state, player: @player.dehydrate }
  end

  def hydrate(hash)
    @state = hash[:scene_state]
    @player = Player.hydrate(hash[:player])
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

  def store
    state_key = self.class.name.to_sym
    owner.state[state_key] ||= {}
    owner.state[state_key]
  end

  def globals
    state_key = :globals
    owner.state[state_key] ||= {}
    owner.state[state_key]
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

  def Scene.state_variable(name, initial: nil)
    define_method(name) do
      store[name] || initial
    end

    define_method("#{name}=") do |new_val|
      # don't store initial values
      if new_val == initial
        store.delete(name)
      else
        store[name] = new_val
      end
    end
  end
end
