require 'curses'
require 'debug'
require 'json'

require './scene'
require './render'
require './foes'
require './roll'
require './items'

module Combatant
  
  def new_round!
    @can_evade = true
  end

  def can_evade?
    @can_evade
  end

  def forfeit_evade!
    @can_evade = false
  end

  def skill_check(recorder, skill, modifier: 0)
    target = self[skill]
    result = Dice.new(6, times: 3).roll
    recorder[name.capitalize, " rolling #{skill} against #{target} + #{modifier}: ", result]
    [result.total <= target + modifier, result]
  end

  def contest(recorder, other, skill, modifier: 0)
    self_succ, self_result = skill_check(recorder, skill, modifier: modifier)
    return false unless self_succ

    other_succ, other_result = other.skill_check(recorder, skill)
    return true unless other_succ

    # TODO: extract margin of success calc
    self_margin = self[skill] + modifier - self_result.total
    other_margin = other[skill] - other_result.total

    self_win = self_margin > other_margin
    winner = self_win ? name : other.name
    recorder["Contest won by #{winner}"]

    self_win
  end

  def strike(recorder, other, modifier: 0)
    hit, martial_roll = skill_check(recorder, :martial, modifier: modifier)

    return [:miss, martial_roll] unless hit

    if other.can_evade?
      evaded, evade_roll = other.skill_check(recorder, :evasion)
      return [:evade, evade_roll] if evaded
    end

    dmg_roll = weapon_dmg.roll(modifier)
    recorder[name, " rolling damage: ", dmg_roll]
    other.injure(dmg_roll.total)
    [:hit, dmg_roll]
  end

  def injure(dmg)
    self.hp -= dmg
    self.hp = 0 if self.hp.negative?
  end

  def heal(amount)
    self.hp += amount
    return unless hp > max_hp

    self.hp = max_hp
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

attrs = %i[name cash hp max_hp]
skills = %i[martial evasion]
foe_fields = %i[exp attack_verb weapon weapon_dmg finisher drops level habitat tags] + attrs + skills

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

player_fields = %i[exp level] + attrs + skills

class Inventory
  attr_reader :items, :eq_weapon
  include Enumerable
  
  def initialize(items: {}, eq_weapon: nil)
    @items = items
    @eq_weapon = eq_weapon
  end

  def each(&block)
    @items.each do |id, quantity|
      item = Items.by_id(id)
      block.call(id, item, quantity)
    end
  end

  def by_tag(*tags)
    filter do |_, item, _|
      tags.any? do |tag|
        item.tagged?(tag)
      end
    end
  end

  def equip_weapon(weapon)
    return unless items.key?(weapon)
    @eq_weapon = weapon
  end

  def empty?
    @items.empty?
  end

  def has?(item_id)
    raise unless item_id.is_a? Symbol
    raise unless Items.valid_id?(item_id)
    @items.key?(item_id)
  end

  def quantity(item)
    @items[item] || 0
  end

  def add(item, quantity = 1)
    @items[item] ||= 0
    @items[item] += quantity
  end

  def remove(item)
    return unless @items.key?(item)

    @items[item] -= 1

    return unless @items[item] <= 0

    @items.delete(item)
    return unless @eq_weapon == item

    @eq_weapon = nil
  end

  def to_h
    {
      'items': items,
      'eq_weapon': eq_weapon
    }
  end
end

Player = Struct.new('Player', *player_fields, keyword_init: true) do
  include Combatant
  attr_reader :inventory

  def initialize(attrs)
    player_attrs = attrs.clone.tap { |it| it.delete('inventory') }
    super(**player_attrs)
    
    # symbolize keys since if loaded from json, might be strings (this is nasty)
    # there's gotta be a better way
    inv_hash = attrs['inventory'] || {}
    inv_hash = Hash[inv_hash.map { |k, v| [k.to_sym, v] }]
    inv_hash[:eq_weapon] = inv_hash['eq_weapon']&.to_sym
    inv_hash = Hash[inv_hash.map { |k, v| [k.to_sym, v] }]
    inv_hash[:items] = Hash[(inv_hash[:items] || {}).map { |k, v| [k.to_sym, v] }]

    @inventory = Inventory.new(**inv_hash)
  end

  def pay(amount)
    self.cash -= amount
    return unless cash.negative?

    self.cash = 0
  end

  def next_level_exp
    (level.to_f**1.5).ceil.to_i * 25
  end

  def ready_to_level_up?
    exp >= next_level_exp
  end

  def weapon
    return 'Fists' unless inventory.eq_weapon

    Items.by_id(inventory.eq_weapon).name
  end

  def weapon_dmg
    return d(4) unless inventory.eq_weapon

    Items.by_id(inventory.eq_weapon).effect_dice
  end

  def serialize
    data = to_h
    data['inventory'] = @inventory.to_h
    data.to_json
  end

  def self.fresh_off_the_boat
    player = new(
      name: 'Doug',
      exp: 0,
      level: 1,
      cash: 5,
      hp: 15,
      max_hp: 15,
      martial: 12,
      evasion: 7
    )
    player.inventory.add(:first_aid, 3)
    player
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

    # pre-round tasks
    player.new_round!
    foe.new_round!

    para 'Your next action?'
    choice 'Attack' do
      result, roll = player.strike(recorder, foe)
      case result
      when :hit
        line "You attack, dealing #{roll.total} damage!"
      when :miss
        line 'You miss!'
      when :evade
        line "#{foe_name} evades!"
      end
    end
    choice 'Power Attack' do
      player.forfeit_evade!
      result, roll = player.strike(recorder, foe, modifier: 2)
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

    choice 'Escape' do
      did_run, = player.contest(recorder, foe, :evasion, modifier: 4)

      if did_run && !foe.tagged?(:plot)
        line 'You run in panic stricken fear!'
        pause
        finish_scene
        return
      else
        line "You scramble for an opportunity to escape, but #{@foe.name} gives none."
      end
    end

    choose!

    if foe.slain?
      conclude_combat
      finish_scene
    else
      result, roll = foe.strike(recorder, player)
      case result
      when :hit
        line "#{foe_name} #{foe.attack_verb} with its #{foe.weapon}, dealing #{roll.total} damage!"
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
    if foe.cash.positive?
      para "You pull #{foe.cash} dollars from the corpse of #{foe.name}."
      player.cash += foe.cash
      pause
    end

    para "You gain #{foe.exp} experience."
    player.exp += foe.exp
    pause

    return if foe.drops.empty?

    foe.drops.each do |drop|
      item = Items.by_id(drop)
      para "After surveying the carnage, you also find a #{item.name}: #{item.description}"
      player.inventory.add(drop)
    end
    pause
  end

  def rummage_through_inventory
    idx = 1
    back = false
    newline
    player.inventory.by_tag(:grenade, :heal).each do |item_id, item, quantity|
      choice idx.to_s, "#{item.name} (#{quantity})" do
        if item.tagged?(:heal)
          heal_roll = item.effect_dice.roll
          para "You use the #{item.name} and recover #{heal_roll.total} HP (#{heal_roll})"
          player.heal(heal_roll.total)
          player.inventory.remove(item_id)
        elsif item.tagged?(:grenade)
          dmg_roll = item.effect_dice.roll
          para "You use the #{item.name} and deal #{dmg_roll.total} damage (#{dmg_roll}) damage"
          @foe.injure(dmg_roll.total)
          player.inventory.remove(item_id)
        else
          para "You thrust the #{item.name} into the air... and nothing happens."
        end
      end
      idx += 1
    end
    choice :b, "Don't use any items" do
      back = true
    end
    choose!
    back
  end
end

class Barter < Scene
  def initialize(shopkeep_name, goods)
    @shopkeep_name = shopkeep_name
    @goods = goods
  end

  def enter
    para "Trading with #{@shopkeep_name}. You have $#{player.cash}."

    @goods.each_with_index do |good_id, index|
      item = Items.by_id(good_id)
      choice (index + 1).to_s, "Inspect #{item.name} ($#{item.value})" do
        inspect_good(good_id)
      end
    end

    choice :l, 'Leave' do
      para 'You politely gaze about as if considering a purchase, then leave'
      finish_scene
    end

    choose!
  end

  def inspect_good(good_id)
    item = Items.by_id(good_id)
    tags = item.tags.map(&->(t) { t.to_s.capitalize }).join(', ')
    para "Inspecting '#{item.name}' (#{tags}):"
    para item.description.to_s, margin: 4

    if player.inventory.has?(good_id)
      line "You already own #{player.inventory.quantity(good_id)} of these."
    else
      line "You don't own any of these yet."
    end

    newline

    if item.tagged?(:fancy)
      line 'Skill: fancy weapon'
      line "Damage: #{item.effect_dice}"
    elsif item.tagged?(:weapon)
      line 'Skill: martial'
      line "Damage: #{item.effect_dice}"
    elsif item.tagged?(:grenade)
      line 'Comsumable'
      line "Damage: #{item.effect_dice}"
    elsif item.tagged?(:heal)
      line 'Comsumable'
      line "Heals: #{item.effect_dice}"
    end

    newline

    choice 'Purchase' do
      if player.cash >= item.value
        player.pay(item.value)
        player.inventory.add(good_id)
        line "You fork over $#{item.value} to #{@shopkeep_name}, and he hands you the #{item.name}!"
      else
        line "You can't afford it! Should have invested in Bitcoin, have fun being poor."
      end
      pause
    end
    choice 'Examine something else' do
      # nothing
    end
    choose!
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
      finish_scene
    when 21..30
      para 'You awaken to the sound of brush crunching underfoot. You spring from your tent to confront whatever is out there...'
      pause
      finish_scene
      proceed_to :combat, Foes.random_encounter(:camp, level_max: player.level)
    when 31..38
      para 'However, distant but unnerving noises interrupt your sleep throughout the night.'
      pause
      finish_scene
    else
      para "In the middle of the night, something rouses you from sleep, although there's no noise or shadows playing across the tent. You decide to investigate, and see the clouds have parted to reveal a full moon."
      pause
      finish_scene
    end
  end
end

class Title < Scene
  def enter
    para 'LEGEND OF THE EVIL SPIX IV:', margin: 12
    para 'GHOSTS OF THE WASTES', margin: 16
    5.times { newline }
    line 'Dedicated to the BBS door games of yore,', margin: 4, color: :secondary
    line 'and to friends new and old', margin: 4, color: :secondary
    5.times { newline }
    choice :n, "Start a new game" do
      proceed_to :town
    end
    choice :l, "Load a saved game" do
      proceed_to :load
    end
    choice :q, "Quit" do
      finish_scene
    end
    choose!
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
      finish_scene
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
        player.hp += 3
        line 'Recovered 3 HP.', color: :secondary
      when 31..34
        para 'He serves you a tumbler full of rocks and a clear liquid'
        dialogue 'Bartender', 'You said you wanted it on the rocks, right?'
        player.hp += 2
        line 'Recovered 5 HP.', color: :secondary
      when 35..38
        para 'To your surprise, he places an honest to god bottle of unopened craft beer on the bar and slides you a bottle opener. You look up in disbelief, and the bartender winks at you.'
        dialogue 'Bartender', "Rumour has it you're here to kill the Spix, may as well enjoy your last days on earth, eh?"
        player.max_hp += 1
        line 'Max HP up!', color: :secondary
      else
        dialogue 'Bartender', "Friend, I think you've had enough. Go get some air."
        para 'You turn and leave, suddenly realizing he never gave you back your money.'
        finish_scene
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
      finish_scene
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

        dialogue 'Dylan', "Also, as you make progress toward our shared goals, report back to me periodically and I'll teach you whatever else I can to aid you."

        para 'You nod, satisfied both at having finally extracted some useful information and at the chance to start cracking skulls again.'
        finish_scene
      end

      choose!
    end
  end

  def show_regular_dialogue
    say 'Any words of wisdom?' do
      if player.ready_to_level_up?
        para 'He gives you a critical look.'
        dialogue 'Dylan', "It does seem you're making a name for yourself here. Perhaps you can be taught after all."
        choice :l, 'Level up!' do
          proceed_to :level_up
        end
        choice :n, 'Nevermind' do
          # do nothing
        end
      else
        para 'He raises an eyebrow at you, and looks down, resuming his writing.'
      end
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
    newline
    choice :m, 'View character sheet' do
      proceed_to :character_sheet
    end

    choose!
  end
end

class CharacterSheet < Scene
  def enter
    para "~~~ #{player.name}'s Stats ~~~"

    para "#{player.hp} / #{player.max_hp} HP"

    line "Level: #{player.level}"
    para "Exp: #{player.exp} / #{player.next_level_exp}"

    para "Cash: $#{player.cash}"

    %i[martial evasion].each do |skill|
      line "#{skill.to_s.capitalize} Skill: #{player[skill]}"
    end
    newline
    line "Weapon: #{player.weapon}"
    line 'Armour: None'
    newline
    choice :w, 'Equip weapon' do
      weapons = player.inventory.filter { |_, item| item.tagged?(:weapon) }
      if weapons.empty?
        line "Seems you don't have any implements of violence among your meager posseessions."
        pause
      else
        # TODO: can probably extract a generic inventory picker from this...
        idx = 1
        weapons.each do |item_id, item, _quantity|
          choice idx.to_s, "Equip '#{item.name}'" do
            para "You grip the #{item.name} in your hands and turn it over a few times. Better than nothing, you suppose."
            player.inventory.equip_weapon(item_id)
            pause
          end
          idx += 1
        end
        unless player.inventory.eq_weapon.nil?
          choice :u, 'Remove equipped weapon' do
            player.inventory.equip_weapon(nil)
          end
        end
        choice :n, 'Leave equipment alone for now' do
          # nothing
        end
        choose!
      end
    end
    choice :i, 'Inventory' do
      blank
      para 'You dump your rucksack onto the ground, and take stock of everything inside:'
      line 'Moths fly from the empty sack.' if player.inventory.empty?

      player.inventory.each do |_, item, quantity|
        line "#{quantity} #{item.name}"
      end
      newline
      pause
    end

    choice :d, 'Done' do
      finish_scene
    end

    choose!
  end
end

class LevelUp < Scene
  def enter
    next_level = player.level + 1
    para "Welcome to level #{next_level}!"

    choice :m, "Train martial skill (#{player.martial} -> #{player.martial + 1})" do
      player.martial += 1
    end
    choice :e, "Train evasion skill (#{player.evasion} -> #{player.evasion + 1})" do
      player.evasion += 1
    end
    choice :h, "Train body (#{player.max_hp} -> #{player.max_hp + 3} HP)" do
      player.max_hp += 3
    end

    choose!

    player.level += 1
    player.hp = player.max_hp
    para "Under Dylan's tutilage, you prepare for whatever the wastes will throw at you next."
    pause
    finish_scene
  end
end

class Cooking < Scene
  def initialize
    @antagonize = 1
  end

  def enter
    first_enter do
      para "You approach a building with a long corregated steel awning. Numbers that you presume once described the shop's operating hours read '7-11'."
      para "Underneath the awning, a weathered man works a fowl-smelling grill. Tapping his spatula against the surface a few times, he turns to face you."
    end

    if @antagonize < 0
      para "The cook lays broken by the grill."
    else
      dialogue 'Cook', "Yeah, what'll it be?"

      say "Is this safe to eat?!" do
        para 'He smiles broadly and leans across the counter toward you.'
        dialogue 'Cook', "Listen punk, you don't want to get on my bad side. I'm gonna ignore that and ask again since I assume you wouldn't be here unless you're hungry: what'll you have?"
        @antagonize += 1
        pause
      end
  
      if @antagonize > 3
        say "Are there no other customers here because they've all died?" do
          para "The cook, finally reaching the limit of verbal abuse he's willing to tolerate, slams the spatula onto the counter."
          dialogue 'Cook', "You motherfucker, what did I tell you?"
          para 'And with that he effortlessly leaps the counter and swings at you!'
          pause
          proceed_to :combat, :cook
          @antagonize = -1
        end 
      end

      choice :b, "See what's on the menu" do
        proceed_to :barter, 'Cook', %i[hamburger slurpee]
      end
    end

    choice :l, "Leave" do
      finish_scene
    end

    choose!
  end
end

class Blacksmith < Scene
  def enter
    para 'You approach the source of all the racket around here, and an elderly wisp of a man wearing a faded t-shirt covered in foreign writing hammers relentlessly on a feeble looking knife.'
    dialogue 'Blacksmith', "Greetings weary traveler! Might thy wishest to, uh, partake in mine fine goods around yonder? Or is it 'thou'..."
    para 'He mumbles to himself while you browse his offerings'
    pause
    finish_scene
    proceed_to :barter, 'Blacksmith', %i[shovel knife]
  end
end

class AssiniboineForest < Scene
  def enter
    first_enter do
      para 'You walk into the forest, and the trees dampen the sunlight and noise.'
      para 'The air smells a little cleaner here than the muggy, sand-filled piss of a breeze in town.'
    end

    para 'Pressing deeper into the forest, you get the sense danger lurks around every corner.'

    choice :e, 'Explore' do
      proceed_to :combat, Foes.random_encounter(:forest, level_max: player.level)
    end
    if player.inventory.has?(:scouts_note)
      choice :i, 'Investigate the perimeter described in the note' do
        proceed_to :combat, Foes.random_encounter(:hammond_perimeter, level_max: player.level + 1)
      end
    end
    choice :c, 'Camp' do
      proceed_to :camp
    end
    choice :l, 'Leave' do
      finish_scene
    end
    choose!
  end
end

class Save < Scene
  def enter
    para 'You walk the edge of town until you find a comfortable, quiet place to rest.'
    save_file = File.join(__dir__, 'saves', player.name.downcase)
    File.write(save_file, player.serialize, mode: 'w')
    pause
    finish_scene
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
      choice (idx+1).to_s, name do
        load(save)
      end
    end
    choose!
  end

  def load(file)
    contents = File.read(file)
    res = JSON.parse(contents)
    owner.player = Player.new(**res)
    
    replace_to :winnipeg
  end
end

# detect irb/require and don't jump into game
return unless $PROGRAM_NAME == __FILE__

window = if ENV['window']&.downcase == 'plain'
           PlainWindow.new
         else
           CursesWindow.new
         end

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
