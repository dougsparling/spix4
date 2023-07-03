require 'forwardable'

class SceneOwner
  attr_reader :window, :player

  def initialize(window)
    # TODO: player should be part of larger state maybe?
    @player = Player.new(name: 'Doug', hp: 15, attack: 7, defense: 4, cash: 25)
    @scenes = []
    @window = window
    # @window.refresh
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
    end_scene
    next_scenes.each do |scene|
      proceed_to scene
    end
  end

  def end_scene
    @scenes.pop unless @scenes.empty?
  end
end

class Scene
  extend Forwardable
  attr_accessor :owner

  def_delegators :window, :choice, :dialogue, :say, :choose!, :line, :para, :newline, :pause
  def_delegators :@owner, :proceed_to, :replace_to, :end_scene

  def window
    @owner.window
  end

  def player
    @owner.player
  end

  # only called on the initial entry to a scene, not subsequent re-enters
  def first_enter
    @did_first_on_enter ||= false
    return if @did_first_on_enter

    yield
    @did_first_on_enter = true
  end
end
