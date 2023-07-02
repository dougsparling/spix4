require 'curses'

require './scene'
require './render'

class Combatant
  attr_accessor :name, :hp, :atk, :blk, :max_hp

  def initialize(name:, hp:, atk:, blk:, max_hp: hp)
    @name = name
    @hp = hp
    @atk = atk
    @blk = blk
    @max_hp = max_hp
  end

  def attack(other)
    dmg = rand(atk) - other.blk
    dmg = 1 if dmg < 1
    other.hp -= dmg
    dmg
  end

  def slain?
    hp <= 0
  end
end

class Player < Combatant
  attr_accessor :cash

  def initialize
    super(name: 'Doug', hp: 15, atk: 7, blk: 4)
    @cash = 25
  end

  def pay(amount)
    @cash -= amount
    return unless @cash.negative?

    @cash = 0
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
      pause
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

class Camp < Scene
  def enter
    para 'As the daylight wanes, you question the wisdom of making the trek back to town in the dark.'
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
    para 'But, as the last gang of wanderers had informed you, the telltale signs of residence reveal themselves ahead: smoke from the stacks, the occasional clang of metal on metal.'

    para 'How do you approach?'

    choice 'Casually stroll in and confront your quarry' do
      replace_to :town_casual
    end
    choice 'Sneak into the city and try to find clues' do
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
    para "Then, by pure luck, you overhear a conversation in what must be a tavern beside you, and somebody uses the name 'Dylan'. You decide to capitalize on surprise while you have it, and crash through the nearest window. Acting on instinct, you immediately strike the man engaged in conversation before he can react!"
    pause
    para 'As he shrugs off the kick, unfurls to his full height and squares you up, you suspect that was a mistake.'
    pause
    replace_to :winnipeg
    proceed_to :tavern, true
    proceed_to :combat, Combatant.new(name: 'Bruiser', hp: 20, atk: 1, blk: 3, max_hp: 30)
  end
end

class TownCasual < Scene
  def enter
    bruiser = Combatant.new(name: 'Bruiser', hp: 30, atk: 1, blk: 3)
    para 'Completely confident, you walk toward the shanty, drawing more than a few quick glances from folk peeking out behind drawn curtains.'
    pause
    para 'You plant your boots on the porch of what must pass for a tavern in this hovel, grab a shovel leaning against the railing, and cry out, "Dylan! Show yourself!"'
    pause
    para 'After a moment, an absolute beast of a man kicks the door open, and you hop backwards in surprise. You do not recognize the man.'
    pause
    dialogue bruiser.name,
             "Who the hell are you? Eh, won't matter anyway once I'm scraping you off the bottom of me shoe."
    pause

    player.atk += 5

    replace_to :winnipeg, :tavern
    proceed_to :combat, bruiser
  end
end

class Tavern < Scene
  def initialize(intro = false)
    @intro = intro
  end

  def enter
    para 'You find yourself inside a former sports bar -- broken televisions and torn pendants hang limply on the walls.'

    if @intro
      para 'The regulars turn toward the commotion just to time to see the bruiser hit the ground, and collectivity murmur amongst themselves before turning back to their drinks.'
      para "The bartender's eyes flick between you and the man on the floor a few times."
      dialogue 'Bartender', 'Uhh, can I help you with something?'
    else
      para 'The regulars mostly crowd the bar and barely give notice as you saunter up, resting your arms on the only non-sticky patch of wood.'
      dialogue 'Bartender', 'Aye, what do ye want?'
    end

    say "I'm here to see Dylan" do
      dialogue 'Bartender', "Hmm, don't suppose I could stop you if I tried. He's in the back."
      proceed_to :dylan, @intro
    end
    drink_dialogue if player.cash >= 5
    choice 'Leave' do
      para 'You slap the bar, turn and leave.'
      end_scene
    end
    choose!
    pause
  end

  def drink_dialogue
    choice :d, "(slide $5 across the bar) I'll have whatever's on tap" do
      player.pay(5)
      dialogue 'Bartender', 'Hah, been awhile since I tapped anything, but let me fix you a drink...'
      case rand(40)
      when 0..30
        para 'He hands you a glass of liquid that you presume must be beer.'
      when 30..33
        para 'He serves you a tumbler full of rocks and a clear liquid'
        dialogue 'Bartender', 'You said you wanted it on the rocks, right?'
      when 34..38
        para 'To your surprise, he places an honest to god bottle of unopened craft beer on the bar and slides you a bottle opener. You look up in disbelief, and the bartender winks at you.'
        dialogue 'Bartender', "Rumour has it you're here to kill the Spix, may as well enjoy your last days on earth, eh?"
      else
        dialogue 'Bartender', "Friend, I think you've had enough. Go get some air."
        para 'You turn and leave, suddenly realizing he never gave you back your money.'
        end_scene
      end
    end
  end
end

class Dylan < Scene
  def initialize(intro)
    @intro = intro
  end

  def enter
    para "You enter Dylan's room, and you see a man sitting behind a desk -- one who clearly doesn't have as much trouble finding a meal as the other wasters around here."
    para 'He looks up from a notebook, mid-scribble, and sighs.'
    dialogue 'Dylan', "Alright, out with it then. Let's not waste time."
    para 'Several potential questions come to mind...'
    say 'What is it that you do here?' do
      dialogue 'Dylan', "I'm the mayor of this town, or what's left of it."
    end
    if @intro
      show_spix_dialogue
    else
      show_regular_dialogue
    end
    choice 'Leave' do
      para 'You excuse yourself and leave Dylan in peace.'
      end_scene
    end
    choose!
    pause
  end

  def show_spix_dialogue
    say 'Can you help me defeat the Spix?' do
      para 'His overworked chair groans loudly has he leans back, and he is suddenly overcome with a look of pain.'
      dialogue 'Dylan', 'I once thought so, perhaps decades ago. Now, I am not so sure.'

      say "I see, I suppose I'll just fuck off back into the wastes then?" do
        para "He shoots you a tentative glance suggesting you're welcome to do so at your leisure."
      end

      say "Hey, I didn't come all this way for nothing. I'm told you're the only man that can stop this damn thing." do
        para 'He stops massaging his forehead for a moment and chuckles.'
        dialogue 'Dylan', "Huh, I'm surprised there are any whispers of my old reputation these days. Well, it's true, there is something I could do."
        pause
        para 'He stands, stretching, and turns to look out the single, grimy window above his desk'
        dialogue 'Dylan', "There was a time when things weren't like this, you know..."
        pause
        para "Your eyes begin wandering the room awkwardly while his self-indulgant monologing rolls on, and after a few minutes, you suddenly realize he's finished by the intense stare he's giving you."

        say "Of course, whatever you need, I'm your guy!"
        say 'Sorry, I got distracted for a minute looking at your impressive, uh, dust collection.'
        choose!

        dialogue 'Dylan', "Right... anyway, as I saying, just bring me the weapon fragments of Hammond's Rifle, and I'll re-assemble it. You'll be on your own after that. Hammond's lab was supposedly underground in a treed park somewhere, I suggest starting at Assiniboine forest, though it's overrun with raiders and other nasties these days."

        para 'You nod, satisfied both at having finally extracted some useful information and at the chance to start cracking skulls again.'
        end_scene
      end

      choose!
    end
  end

  def show_regular_dialogue
    say 'Any words of wisdom?' do
      para 'He raises an eyebrow at you, and looks down, resuming his writing.'
    end
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
  def enter
    para 'You stand at the crossroads of the shanty town, sizing up the weathered population for any that might help you.'

    choice :f, 'Go to the forest' do
      proceed_to :assiniboine_forest
    end
    choice :t, 'Enter the tavern' do
      proceed_to :tavern
    end
    choice :b, 'Visit the blacksmith' do
      proceed_to :blacksmith
    end
    choice :s, 'Find a shanty to curl up and rest in (save)' do
      proceed_to :save
    end

    choose!
  end
end

class AssiniboineForest < Scene
  def enter
    first_enter do
      para 'You walk into the forest, and the trees dampen the sunlight and noise.'
      para 'The air smells a little cleaner here than the muggy, sand-filled piss of a breeze in town.'
    end

    choice :i, 'Investigate' do
      foes = [
        Combatant.new(name: 'mutated dog', hp: 5, atk: 3, blk: 1),
        Combatant.new(name: 'elven boy', hp: 3, atk: 5, blk: 1),
        Combatant.new(name: 'twigged out grandpa', hp: 5, atk: 3, blk: 1),
        Combatant.new(name: 'scavenger', hp: 7, atk: 5, blk: 3)
      ]
      proceed_to :combat, foes[rand(foes.size)]
    end
    choice :c, 'Camp' do
      proceed_to :camp
    end
    choice :l, 'Leave' do
      end_scene
    end
    choose!
  end
end

window = Window.new

# boolean:true int:42 string:whatever => [true, 42, "whatever"]
scene_params = *ARGV[1..].map do |param|
  ptype, pvalue = param.split(':')
  case ptype
  when 'boolean'
    pvalue = pvalue.downcase == 'true'
  when 'int'
    pvalue = pvalue.to_i
  end
  pvalue
end

scenes = SceneOwner.new(window)
scenes.proceed_to ARGV.first.to_sym || :title, *scene_params
scenes.main_loop
