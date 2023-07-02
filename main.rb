require 'curses'

require './scene'
require './render'

class Combatant
  attr_accessor :name, :hp, :atk, :blk, :max_hp

  def initialize(name, hp, atk, blk, max_hp = hp)
    @name = name
    @hp = hp
    @atk = atk
    @blk = blk
    @max_hp = max_hp
  end

  def attack(other)
    dmg = other.blk - rand(atk)
    dmg = 1 if dmg < 1
    other.hp -= dmg
    dmg
  end

  def slain?
    hp <= 0
  end
end

class Player < Combatant
  def initialize
    super('Doug', 15, 4, 4)
  end
end

class Combat < Scene
  attr_reader :foe

  def initialize(foe)
    @foe = foe
  end

  def enter
    para "You have encountered '#{foe.name}'!"
    line "#{player.name}'s HP:    #{player.hp} / #{player.max_hp}", margin: 4
    line "#{foe.name}'s HP:   #{foe.hp} / #{foe.max_hp}", margin: 4
    newline
    para 'Your next action?'
    choice 'Attack!' do
      dmg = player.attack(foe)
      line "You attack, dealing #{dmg} damage!"
    end
    choice 'Run!' do
      line 'You run?'
    end
    choose!

    if foe.slain?
      line "You have defeated #{foe.name}!"
      end_scene
    else
      dmg = foe.attack(player)

      if player.slain?
        line "#{foe.name} delivers a killing blow of #{dmg} damage, and the world begins to darken..."
        proceed_to :game_over
      else
        line "#{foe.name} hits you for #{dmg} damage!"
      end
      pause
    end
  end
end

class Title < Scene
  def enter
    para 'LEGEND OF THE EVIL SPIX IV:', margin: 4
    para 'GHOSTS OF THE WASTES', margin: 8
    pause
    proceed_to :town
  end
end

class Town < Scene
  def enter
    para 'You stand on a crumbling highway, having walked for days and finally found civilization. A faded sign shows the former name of this place: Winnipeg'
    para 'Half an hour of walking reveals little of interest, beyond the crumbling buildings that line the horizon and scraps of passed over trash'
    para 'But, as the last gang of wanderers had informed you, the telltale signs of a shanty-within-the-town reveal themselves ahead: smoke from the stacks, the occasional clang of metal on metal.'

    para 'How do you approach?'

    choice 'Casually stroll in and ask around about your quarry' do
      replace_to :town_casual
    end
    choice 'Take cover and use caution' do
      replace_to :town_cautious
    end

    choose!
  end
end

class TownCautious < Scene
  def enter
    para 'You drop low and skirt the edge of the shanty, pausing frequently to assess whether or not anybody has seen you approach...'
    pause
    para 'You take a winding path through ruined buildings, drawing closer to the center of town...'
    pause
    para 'No signs anybody has seen you yet...'
    pause
    para "Then, by pure luck, you overhear a conversation in what must be a tavern beside you, and somebody uses the name 'Dylan'. You decide to capitalize on surprise while you have it, and crash through the nearest window. Acting on instinct, you strike an absolute beast of a man engaged in conversation with your quarry!"
    pause
    para 'As he recovers from the kick and squares you up, you suspect that was a mistake.'
    pause
    replace_to :winnipeg, :tavern
    proceed_to :combat, Combatant.new('Bruiser', 20, 5, 3, 30)
  end
end

class TownCasual < Scene
  def enter
    bruiser = Combatant.new('Bruiser', 20, 5, 3)
    para 'Completely confident, you walk toward the shanty, drawing more than a few quick glances from folk peeking out behind drawn curtains.'
    pause
    para 'You plant your boots on the porch of what must pass for a tavern in this hovel, grab a shovel leaning against the railing, and cry out, "Dylan! Show yourself!"'
    pause
    para 'After a moment, an absolute beast of a man kicks the door open, and you hop backwards in surprise. You do not recognize the man.'
    pause
    dialogue bruiser.name,
             "Who the hell are you? Eh, won't matter anyway once I'm scraping you off the bottom of me shoe."
    pause
    replace_to :winnipeg, :tavern
    proceed_to :combat, bruiser
  end
end

class GameOver < Scene
  def enter
    para 'You fall to the ground helplessly, and your final thoughts are of the Spix and the doomed people of Winnipeg...'
    pause
    exit
  end
end

class Winnipeg < Scene
end

class Tavern < Scene
end

window = Window.new

scenes = SceneOwner.new(window)
scenes.proceed_to :title
scenes.main_loop
