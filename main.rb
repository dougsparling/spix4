require 'curses'

class SceneOwner
  attr_reader :window, :player

  def initialize(window)
    # TODO: player probably shouldn't be here
    @player = Player.new
    @scenes = []
    @window = window
    @window.refresh
  end

  def main_loop
    until @scenes.empty?
      # loop clearing, resetting cursor and re-drawing the scene
      @window.clear
      @window.setpos(0,0)
      @scenes.last.render
      @window.refresh
    end
  end

  def proceed_to(next_scene, *args)
    # e.g. :next_scene -> NextScene class
    scene_type = Object.const_get(next_scene.to_s.split('_').collect(&:capitalize).join)
    scene = scene_type.new(*args)
    # TODO: kinda nasty
    scene.owner = self
    @scenes.push(scene)  
  end

  def replace_to(*next_scenes)
    end_scene
    for scene in next_scenes
      proceed_to scene
    end
  end

  def end_scene
    @scenes.pop unless @scenes.empty?
  end
end

class Scene
  attr_accessor :owner

  def window
    @owner.window
  end

  def player
    @owner.player
  end

  def choice(text, &block)
    @choices ||= []
    @choices << block
    line "#{@choices.size}) #{text}"
  end

  def dialogue(name, text)
    window << name << ": "
    line(text, margin: name.size + 2)
  end

  def choose!
    while true
      c = window.getch.to_s
      if c =~ /\d/
        ci = c.to_i
        if ci != 0 && ci <= @choices.size
          @choices[ci - 1].call()
          break
        end
      end
          
      dialog = window.derwin(3, 25, 2, 2)
      dialog << "INVALID CHOICE: #{c}"
      dialog.box
      dialog.getch
      dialog.close
      window.redraw
    end
    @choices = nil
  end

  def line(text, width: window.maxx, margin: 0)
    words = text.split /(\W)/
    line = ""
    until words.empty?
      word = words.shift
      line += word

      if words.empty? || words.first.size + line.size + margin > width - 1
        window.setpos(window.cury, margin)
        window << line.rstrip
        newline
        break if words.empty?
        line = ""
      end
    end
  end

  def para(text, width: window.maxx, margin: 0)
    line(text, width: width, margin: margin)
    newline
  end

  def newline
    window.setpos(window.cury + 1, 0)
  end

  # a dramatic pause for effect
  def pause
    window << "..."
    window.getch
    window.deleteln
    window.setpos(window.cury, 0)
  end
end

class Combatant
  attr_accessor :name, :hp, :atk, :blk, :max_hp
  def initialize(name, hp, atk, blk, max_hp = hp)
    @name, @hp, @atk, @blk, @max_hp = name, hp, atk, blk, max_hp
  end

  def attack(other)
    dmg = other.blk - rand(atk)
    dmg = 1 if dmg < 1
    other.hp -= dmg
    return dmg
  end

  def slain?
    hp <= 0
  end
end

class Player < Combatant
  def initialize
    super("Doug", 15, 4, 4)
  end
end

class Combat < Scene
  attr_reader :foe
  def initialize(foe)
    @foe = foe
  end

  def render
    para "You have encountered '#{foe.name}'!"
    line "#{player.name}'s HP:    #{player.hp} / #{player.max_hp}", margin: 4
    line "#{foe.name}'s HP:   #{foe.hp} / #{foe.max_hp}", margin: 4
    newline
    line "Your next action?"
    choice "Attack!" do
      dmg = player.attack(foe)
      line "You attack, dealing #{dmg} damage!"
    end
    choice "Run!" do
      line "You run?"
    end
    choose!

    if foe.slain?
      line "You have defeated #{foe.name}!"
      end_scene
    else
      dmg = foe.attack(player)

      if player.slain?
        line "#{foe.name} strikes back, and the world begins to darken..."
        owner.proceed_to :game_over
      else
        line "#{foe.name} hits you for #{dmg} damage!"
      end
      pause
    end
  end
end

class Title < Scene
  def render
    para "LEGEND OF THE EVIL SPIX IV:", margin: 4
    para "GHOSTS OF THE WASTES", margin: 8
    window.getch
    owner.proceed_to :town
  end
end

class Town < Scene
  def render
    para "You stand on a crumbling highway, having walked for days and finally found civilization. A faded sign shows the former name of this place: Winnipeg" 
    para "Half an hour of walking reveals little of interest, beyond the crumbling buildings that line the horizon and scraps of passed over trash"
    para "But, as the last gang of wanderers had informed you, the telltale signs of a shanty-within-the-town reveal themselves ahead: smoke from the stacks, the occasional clang of metal on metal."
    para "How do you approach?"
    
    choice "Casually stroll in and ask around about your quarry" do
      owner.replace_to :town_casual
    end
    choice "Take cover and use caution" do
      owner.replace_to :town_cautious
    end

    choose!
  end
end

class TownCautious < Scene
  def render
    para "You drop low and skirt the edge of the shanty, pausing frequently to assess whether or not anybody has seen you approach..."
    pause
    para "You take a winding path through ruined buildings, drawing closer to the center of town..."
    pause
    para "No signs anybody has seen you yet..."
    pause
    para "Then, by pure luck, you overhear a conversation in what must be a tavern beside you, and somebody uses the name 'Dylan'. You decide to capitalize on surprise while you have it, and crash through the nearest window. Acting on instinct, you strike an absolute beast of a man engaged in conversation with your quarry!"
    pause
    para "As he recovers from the kick and squares you up, you suspect that was a mistake."
    window.getch
    owner.replace_to :winnipeg, :tavern
    owner.proceed_to :combat, Combatant.new("Bruiser", 20, 5, 3, 30)
  end
end

class TownCasual < Scene
  def render
    para "Completely confident, you walk toward the shanty, drawing more than a few quick glances from folk peeking out behind drawn curtains."
    pause
    para "You plant your boots on the porch of what must pass for a tavern in this hovel, grab a shovel leaning against the railing, and cry out, \"Dylan! Show yourself!\""
    pause
    para "After a moment, an absolute beast of a man kicks the door open, and you hop backwards in surprise. You do not recognize the man."
    pause
    dialogue "Bruiser", "Who the hell are you? Eh, won't matter anyway once I'm scraping you off the bottom of me shoe."
    pause
    owner.replace_to :winnipeg, :tavern
    owner.proceed_to :combat, Combatant.new("Bruiser", 20, 5, 3)
  end
end

class GameOver < Scene
  def render
    para "You fall to the ground helplessly, and your final thoughts are of the Spix and the doomed people of Winnipeg..."
    pause
    exit
  end
end

class Winnipeg < Scene
end

class Tavern < Scene
end

# centered box in terminal
Curses.init_screen()
Curses.start_color()
Curses.noecho()

title = "~~~  SPIX IV  ~~~"
window = Curses::Window.new(25, 80, (Curses.lines - 25) / 2, (Curses.cols - 80) / 2 )
window.box
window.setpos(0, (window.maxx - title.size) / 2)
window << title
window.refresh
scene_window = window.derwin(21, 76, 2, 2)

scenes = SceneOwner.new(scene_window)
scenes.proceed_to :title
scenes.main_loop


