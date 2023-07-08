require 'curses'

require './scene'
require './render'
require './foes'
require './roll'
require './items'

module Combatant
  def skill_check(skill, recorder)
    target = self[skill]
    result = Dice.new(6, times: 3).roll
    recorder[name.capitalize, " rolling #{skill}: ", result]
    [result.total <= target, result]
  end

  def contest(other, skill, recorder)
    self_succ, self_result = skill_check(skill, recorder)
    return false unless self_succ

    other_succ, other_result = other.skill_check(skill, recorder)
    return true unless other_succ
    
    # TODO: extract margin of success calc
    self_margin = self[skill] - self_result.total
    other_margin = other[skill] - other_result.total

    self_win = self_margin > other_margin
    winner = if self_win then self.name else other.name end
    recorder["Contest won by #{winner}"]

    return self_win
  end

  def strike(other, recorder)
    hit, martial_roll = self.skill_check(:martial, recorder)
    
    return [:miss, martial_roll] unless hit

    evaded, evade_roll = other.skill_check(:evasion, recorder)
    return [:evade, evade_roll] if evaded

    dmg_roll = weapon_dmg.roll
    recorder[name, " rolling #{weapon_dmg} damage: ", dmg_roll]
    other.injure(dmg_roll.total)
    return [:hit, dmg_roll]
  end

  def injure(dmg)
    self.hp -= dmg
    self.hp = 0 if self.hp < 0
  end

  def heal(amount)
    self.hp += amount
    if hp > max_hp
      self.hp = max_hp
    end
  end

  def slain?
    hp <= 0
  end
end

Item = Struct.new('Item', :name, :description, :value, :combat, :effect_dice, :tags, keyword_init: true) do
  def tagged?(tag)
    tags.include?(tag)
  end
end

attrs = [:name, :cash, :hp, :max_hp]
skills = [:martial, :evasion]
foe_fields = [:exp, :attack_verb, :weapon, :weapon_dmg, :finisher, :drops, :tags] + attrs + skills 

Foe = Struct.new('Foe', *foe_fields, keyword_init: true) do
  include Combatant
  attr_reader :max_hp
  
  def initialize(args)
    super(**args)
    @max_hp = hp
  end

  def tagged?(tag)
    tags.include?(tag)
  end
end

player_fields = attrs + skills

class Inventory
  attr_reader :items, :eq_weapon

  def initialize
    @items = {}
    @eq_weapon = nil
  end
  
  def equip_weapon(weapon)
    return unless items.has_key?(weapon)
    @eq_weapon = weapon
  end

  def add(item, quantity = 1)
    @items[item] ||= 0
    @items[item] += quantity
  end

  def remove(item)
    return unless @items.has_key?(item)
    @items[item] -= 1

    if @items[item] <= 0
      @items.delete(item) 
      if @eq_weapon == item
        @eq_weapon = nil
      end
    end
  end
end

Player = Struct.new('Player', *player_fields, keyword_init: true) do
  include Combatant
  attr_reader :inventory

  def initialize(attrs)
    super(**attrs)
    @inventory = Inventory.new
  end

  def pay(amount)
    self.cash -= amount
    if cash.negative?
      self.cash = 0
    end
  end

  def weapon
    return "Fists" unless inventory.eq_weapon
    Items.by_id(inventory.eq_weapon).name
  end

  def weapon_dmg
    return d(4) unless inventory.eq_weapon
    Items.by_id(inventory.eq_weapon).effect_dice
  end

  def self.fresh_off_the_boat
    player = new(
      name: "Doug",
      cash: 25,
      hp: 15,
      max_hp: 15,
      martial: 12,
      evasion: 10
    )
    player.inventory.add(:first_aid, 3)
    return player
  end
end

class Combat < Scene
  attr_reader :foe

  def initialize(foe)
    if foe.is_a? Combatant
      @foe = foe
    elsif foe.is_a? Symbol
      @foe = Foes.by_id(foe)
    else
      raise "what is this: #{foe}"
    end
  end

  def foe_name
    foe.name.capitalize
  end

  def enter
    para "You have encountered '#{foe.name}'!"
    line "#{player.name}'s HP:    #{player.hp} / #{player.max_hp}", margin: 4
    line "#{foe_name}'s HP:   #{foe.hp} / #{foe.max_hp}", margin: 4
    newline
    para 'Your next action?'
    choice 'Attack!' do
      result, roll = player.strike(foe, recorder)
      case result
      when :hit
        line "You attack, dealing #{roll.total} damage!"
      when :miss
        line "You miss!"
      when :evade
        line "#{foe_name} evades!"
      end
    end
    choice 'Inventory' do
      cancel = rummage_through_inventory
      return if cancel
    end

    choice 'Run!' do
      did_run, _ = player.contest(foe, :evasion, recorder)
      
      if did_run && !foe.tagged?(:plot)
        line "You run in panic stricken fear!"
        pause
        end_scene
        return
      else
        line "You scramble for an opportunity to escape, but #{@foe.name} gives none."
      end
    end
    
    choose!

    if foe.slain?
      conclude_combat
      end_scene
    else
      result, roll = foe.strike(player, recorder)
      case result
      when :hit
        line "#{foe_name} #{foe.attack_verb} you with its #{foe.weapon}, dealing #{roll.total} damage!"
      when :miss
        line "#{foe_name} #{foe.attack_verb}, but misses!"
      when :evade
        line "#{foe_name} #{foe.attack_verb}, but you narrowly evade!"
      end
      
      if player.slain?
        para 'The world begins to darken...'
        proceed_to :game_over 
      end
      pause
    end
  end

  def conclude_combat
    newline
    para foe.finisher
    pause
    if foe.cash > 0
      para "You pull #{foe.cash} dollars from the corpse of #{foe.name}."
      player.cash += foe.cash
      pause
    end

    para "You gain #{foe.exp} experience."
    pause

    unless foe.drops.empty?
      foe.drops.each do |drop|
        item = Items.by_id(drop)
        para "You find a '#{item.name}' near the body: #{item.description}"
        player.inventory.add(drop)
      end
      pause
    end
    
  end

  def rummage_through_inventory
    idx = 1
    @back = false
    choice :b, "Go back" do
      @back = true
    end
    player.inventory.items.each do |item_id, quantity|
      item = Items.by_id(item_id)
      choice idx.to_s, "#{item.name} (#{quantity})" do
        if item.tagged?(:heal)
          heal_roll = item.effect_dice.roll
          para "You imbibe the #{item.name} and recover #{heal_roll.total} HP (#{heal_roll})"
          player.heal(heal_roll.total)
          player.inventory.remove(item_id)
        elsif item.tagged?(:grenade)
          dmg_roll = item.effect_dice.roll
          para "You use the #{item.name} and deal #{dmg_roll.total} damage (#{dmg_roll}) damage"
          @foe.injure(dmg_roll.total)
          player.inventory.remove(item_id)
        else
          para "You thrust the #{item}"
        end
      end
      idx += 1
    end
    choose!
    return @back
  end
end

class Camp < Scene
  def enter
    para 'As the daylight wanes, you question the wisdom of making the trek back to town in the dark.'
    para 'After a quick survey, you find a small concealed clearing and set up camp, listening intently for lurking dangers.'
    para 'Eventually your guard slips and you are embraced by sleep...'
    pause

    case rand(40)
    when 1..20
      para 'You enjoy a deep and uninterrupted sleep'
      line 'HP fully recovered!', color: :secondary
      player.hp = player.max_hp
      pause
      end_scene
    when 21..30
      para 'You awaken to the sound of brush crunching underfoot. You spring from your tent to confront whatever is out there...'
      pause
      end_scene
      proceed_to :combat, :raccoons
    when 31..38
      para 'However, distant but unnerving noises interrupt your sleep throughout the night.'
      pause
      end_scene
    else
      para "In the middle of the night, something rouses you from sleep, although there's no noise or shadows playing across the tent. You decide to investigate, and see the clouds have parted to reveal a full moon."
      pause
      end_scene
    end
  end
end

class Title < Scene
  def enter
    para 'LEGEND OF THE EVIL SPIX IV:', margin: 12
    para 'GHOSTS OF THE WASTES', margin: 16
    12.times { newline }
    line 'Dedicated to the BBS door games of yore,', margin: 4, color: :secondary
    line 'and to friends new and old', margin: 4, color: :secondary
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

    bruiser = Foes.by_id(:bruiser)
    bruiser.injure(10)

    replace_to :winnipeg
    proceed_to :tavern, true
    proceed_to :combat, bruiser
  end
end

class TownCasual < Scene
  def enter
    bruiser = Foes.by_id(:bruiser)

    para 'Completely confident, you walk toward the shanty, drawing more than a few quick glances from folk peeking out behind drawn curtains.'
    pause
    para 'You plant your boots on the porch of what must pass for a tavern in this hovel, grab a shovel leaning against the railing, and cry out, "Dylan! Show yourself!"'
    pause
    para 'After a moment, an absolute beast of a man kicks the door open, and you hop backwards in surprise. You do not recognize the man.'
    pause
    dialogue bruiser.name,
             "Who the hell are you? Eh, won't matter anyway once I'm scraping you off the bottom of me shoe."
    pause

    player.inventory.add(:shovel)
    player.inventory.equip_weapon(:shovel)

    replace_to :winnipeg
    proceed_to :tavern, true
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
        player.hp += 1
      when 31..34
        para 'He serves you a tumbler full of rocks and a clear liquid'
        dialogue 'Bartender', 'You said you wanted it on the rocks, right?'
        player.hp += 2
      when 35..38
        para 'To your surprise, he places an honest to god bottle of unopened craft beer on the bar and slides you a bottle opener. You look up in disbelief, and the bartender winks at you.'
        dialogue 'Bartender', "Rumour has it you're here to kill the Spix, may as well enjoy your last days on earth, eh?"
        player.max_hp += 1
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
    choice :c, "See what's cooking" do
      proceed_to :cooking
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
      foes = [:mutated_dog, :elf, :grandpa, :scavenger]
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

# detect irb/require
return unless $0 == __FILE__

window = Window.new

# boolean:true int:42 string:whatever => [true, 42, "whatever"]
scene_params = *(ARGV[1..] || []).map do |param|
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
scenes.proceed_to ARGV.first&.to_sym || :title, *scene_params
scenes.main_loop
