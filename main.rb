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
    target = nil
    if trained_in?(skill)
      target = self[skill]
    else
      defaulted, default_mod = default_of(skill)
      if defaulted
        recorder[name.capitalize, " untrained in #{skill}, defaults to #{defaulted} + #{default_mod}"]
        target = self[defaulted] + default_mod
        skill = defaulted
      else
        default_target = 10 + default_mod
        recorder[name.capitalize, " #{skill} untrained and has no default, target #{default_target}"]
        target = 7
      end
    end
    
    result = Dice.new(6, times: 3).roll
    recorder[name.capitalize, " rolling #{skill} against #{target} + #{modifier}: ", result]
    [result.total <= target + modifier, result]
  end

  def trained_in?(skill)
    !(self[skill].nil? || self[skill].zero?)
  end

  def default_of(skill)
    case skill
    when :fancy
      [:martial, -3]
    when :unarmed
      [:martial, -2]
    else
      [nil, -3]
    end
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
    hit, martial_roll = skill_check(recorder, weapon_skill, modifier: modifier)

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
skills = %i[martial evasion fancy unarmed]
foe_fields = %i[exp attack_verb weapon weapon_dmg finisher drops level habitat tags] + attrs + skills

Foe = Struct.new('Foe', *foe_fields, keyword_init: true) do
  include Combatant
  attr_reader :max_hp

  def initialize(args)
    super(**args)
    @max_hp = hp
  end

  def weapon_skill
    :martial
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
    return unless weapon.nil? || items.key?(weapon)
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
    raise "removing item we don't have: #{item}" unless @items.key?(item)

    @items[item] -= 1

    return unless @items[item] <= 0

    @items.delete(item)
    return unless @eq_weapon == item

    @eq_weapon = nil
  end

  def dehydrate
    { items: items, eq_weapon: eq_weapon }
  end

  def self.hydrate(hash)
    hash[:eq_weapon] = hash[:eq_weapon]&.to_sym

    invalid = [hash[:eq_weapon], hash[:items].keys].flatten.compact.select { |id| !Items.valid_id?(id) }
    raise "hydration with invalid items: #{invalid}" unless invalid.empty?
    
    Inventory.new(**hash)
  end
end

Player = Struct.new('Player', *player_fields, keyword_init: true) do
  include Combatant
  attr_accessor :inventory

  def initialize(attrs)
    super(**attrs)
    @inventory = Inventory.new
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
    get_weapon&.name || 'fists'
  end

  def weapon_dmg
    get_weapon&.effect_dice || d(4)
  end

  def get_weapon
    return nil if inventory.eq_weapon.nil?
    Items.by_id(inventory.eq_weapon)
  end

  def weapon_skill
    w = get_weapon
    if w.nil?
      :unarmed
    elsif w.tagged?(:fancy)
      :fancy
    else
      :martial
    end
  end

  def dehydrate
    data = to_h
    data[:inventory] = @inventory.dehydrate
    data
  end

  def self.hydrate(hash)
    player_attrs = hash.clone.tap { |it| it.delete(:inventory) }
    player = Player.new(**player_attrs)
    player.inventory = Inventory.hydrate(hash[:inventory])
    player
  end

  def self.fresh_off_the_boat
    player = new(
      name: 'Doug',
      exp: 0,
      level: 1,
      cash: 5,
      hp: 12,
      max_hp: 12,
      martial: 9,
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
      para "You pull #{foe.cash} dollars from #{foe.name}."
      player.cash += foe.cash
      pause
    end

    para "You gain #{foe.exp} experience."
    player.exp += foe.exp
    pause

    return if foe.drops.empty?

    foe.drops.each do |drop|
      item = Items.by_id(drop)
      para "After surveying the carnage, you find an intact #{item.name}: #{item.description}"
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

    choice :f, 'Finished' do
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
      if player.hp > player.max_hp
        para "You enter a restless sleep as the effects of the alcohol progress"
        line 'You awaken with a hangover', color: :secondary
      else
        para 'You enjoy a deep and uninterrupted sleep'
        line 'HP fully recovered!', color: :secondary
      end
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
      recovered = [d("2d4").roll.total, player.max_hp - player.hp].min
      line "Recovered #{recovered} HP!", color: :secondary
      player.hp = player.max_hp
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
      proceed_to :intro
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

class Intro < Scene
  def enter
    first_enter do
      owner.player = Player.fresh_off_the_boat
    end

    para 'Years of hard travel and violence have brought you to the seated blind man before you.'
    para 'He smiles and opens his arms, sensing your approach.'
    dialogue 'Man', 'To whom do I have the pleasure of speaking?'
    name = prompt 'Name'
    owner.player.name = name
    dialogue 'You', "Call me #{name}, if it pleases you."
    dialogue 'Man', "It does. Pleased to meet you, #{name}. Must have been a difficult journey through the wastes to end up here."

    say "I've buried a few people along the way." do
      player.martial += 2 
    end
    say "Danger is easily avoided if one is ready for it." do
      player.evasion += 2 
    end
    say "Taken my fair share of bruises, that's for sure." do
      player.max_hp += 6 
      player.hp += 6 
    end
    choose!

    para "The man ponders what you've said."
    dialogue 'Man', "Suppose you wouldn't be here otherwise. So what can I do for you? Few if any would come all this way if they had a choice."
    dialogue 'You', "I'm seeking any who might hold the secret to the destruction of the Spix."
    dialogue 'Man', "Ahh, there have been a great number before you, and I'm sure there will be a great number after. No matter, I know there is nothing this bitter old man can do to deter you. Rumour has it there is still one who can help --"
    para 'He gestures to a ruined road running north.'
    pause

    dialogue 'Man', "One great city lies in ruin at the end of the road. There are survivors eeking out a living, who will know of one named 'Dylan'. Don't expect them to take kindly to outsiders, #{name}."
    para 'You offer brief thanks to the man, and start walking.'
    pause

    replace_to :intro_town
  end
end

class IntroTown < Scene
  def enter
    para 'You stand on a crumbling highway, having walked for days and finally found civilization. A faded sign shows the former name of this place: Winnipeg.'
    para 'Half an hour of walking beyond the sign reveals little of interest, beyond crumbling buildings that line the horizon and scraps of passed over trash.'
    para 'But, as the blind man had informed you, the telltale signs of residence reveal themselves ahead: smoke from the stacks, the occasional clang of metal on metal.'

    para 'How do you approach?'

    choice 'Casually stroll in and confront your quarry' do
      replace_to :intro_town_casual
    end
    choice 'Sneak into the city and try to find clues' do
      replace_to :intro_town_cautious
    end

    choose!
  end
end

class IntroTownCautious < Scene
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
    bruiser.injure(7)

    replace_to :winnipeg
    proceed_to :tavern, true
    proceed_to :combat, bruiser
  end
end

class IntroTownCasual < Scene
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
  state_variable :found_price_eng, initial: false, shared: true
  state_variable :intro, initial: true

  def enter
    para 'You find yourself inside a former sports bar -- broken televisions and torn pendants hang limply on the walls.'

    if intro
      para 'The regulars turn toward the commotion just to time to see the bruiser hit the ground, and collectivity murmur amongst themselves before turning back to their drinks.'
      para "The bartender's eyes flick between you and the man on the floor a few times."
      dialogue 'Bartender', 'Uhh, can I help you with something?'
    else
      para 'The regulars mostly crowd the bar and barely give notice as you saunter up, resting your arms on the only non-sticky patch of wood.'
      dialogue 'Bartender', 'Aye, what do ye want?'
    end

    say :d, "I'm here to see Dylan" do
      dialogue 'Bartender', "Hmm, don't suppose I could stop you if I tried. He's in the back."
      proceed_to :dylan
      self.intro = false
    end
    drink_dialogue if player.cash >= 5
    
    if !found_price_eng && player.inventory.has?(:octocopter)
      choice :e, "Ask around if anybody is good with electronics." do
        ask_about_electronics
      end
    end

    unless intro
      choice 'Leave' do
        para 'You slap the bar, turn and leave.'
        finish_scene
      end
    end
    choose!
    pause
  end

  def drink_dialogue
    choice :b, "(slide $5 across the bar) I'll have whatever's on tap" do
      player.pay(5)
      dialogue 'Bartender', 'Hah, been awhile since I tapped anything, but let me fix you a drink...'
      case rand(40)
      when 0..34
        para 'He hands you a glass of liquid that you presume must be beer.'
        player.hp += 3
        line '+2 bonus HP.', color: :secondary
      when 35..37
        para 'He serves you a tumbler full of rocks and a clear liquid'
        dialogue 'Bartender', 'You said you wanted it on the rocks, right?'
        player.hp += 2
        line '+4 bonus HP.', color: :secondary
      when 38
        para 'To your surprise, he places an honest to god bottle of unopened craft beer on the bar and slides you a bottle opener. You look up in disbelief, and the bartender winks at you.'
        dialogue 'Bartender', "Rumour has it you're here to kill the Spix, may as well enjoy your last days on earth, eh?"
        player.max_hp += 1
        player.hp += 1
        line 'Max HP up!', color: :secondary
      else
        dialogue 'Bartender', "Friend, I think you've had enough. Go get some air."
        para 'You turn and leave, suddenly realizing he never gave you back your money.'
        finish_scene
      end
    end
  end

  def ask_about_electronics
    para 'You saddle up to the bar and place the octocopter in front of some regulars.'
    drop_topic = false
    while !found_price_eng && !drop_topic
      say :a, "Anybody know how these things work?" do
        dialogue "Drunk", "I might know a guy, for $50 I could introduce you."

        if player.cash < 50
          say :d, "I don't have $50." do
            para "He shrugs and takes another sip from his drink."
            pause
          end
        else
          choice :d, "Slide him $50." do
            player.cash -= 50
            para "His eyes light up for a moment, then he plays it cool and slips the bills into his jacket."
            dialogue "Drunk", "Alright pard'ner, look for a guy named Craig. Bit of a loner, you can find him in the ol' Price Electronics building just north of downtown."
            self.found_price_eng = true
            para "You thank him for his time and stand up, picking up the drone."
            pause
          end
        end

        choice :a, "Give him an ass-whoopin'" do
          para 'You kick him off his stool and square up.'
          proceed_to :combat, :extortionate_drunk
          self.found_price_eng = true
        end
      end

      say :t, "If I find out one of you sumbitches was flying this thing I'll kick your asses into the street." do
        para "The regulars give each other a look and raise their hands in innocence."
      end

      say :d, "Drop the topic." do
        para "You mumble a 'thanks anyway' and stuff the drone back into your pack."
        drop_topic = true
      end
      choose!
    end
  end
end

class Dylan < Scene
  state_variable :intro, initial: true

  def enter
    para "You enter Dylan's room, and you see a man sitting behind a desk -- one who clearly doesn't have as much trouble finding a meal as the other wasters around here."
    para 'He looks up from a notebook, mid-scribble, and sighs.'
    dialogue 'Dylan', "Alright, out with it then. Let's not waste time."
    para 'Several potential questions come to mind...'
    say 'What is it that you do here?' do
      dialogue 'Dylan', "I'm the mayor of this town, or what's left of it."
    end
    if intro
      show_spix_dialogue
    else
      show_regular_dialogue
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
        para 'He stands, stretching, and turns to look out the single, grimy window above his desk.'
        dialogue 'Dylan', "There was a time when things weren't like this, you know..."
        pause

        blank
        para "Your eyes begin wandering the room awkwardly while his self-indulgant monologing rolls on, and after a few minutes, you suddenly realize he has finished by the intense stare he's giving you."
        say "Uh, of course, let's do whatever you just said."
        say 'Sorry, I got distracted for a minute looking at your impressive, uh, dust collection.'
        choose!

        dialogue 'Dylan', "Right... anyway, as I saying, Hammond started this whole mess with his work prototyping the early Spix, and he must have kept detailed notes. Bring them to me, and I'll take it from there. Hammond's lab was supposedly underground in Assiniboine forest, though it's overrun with raiders and other nasties these days."
        dialogue 'Dylan', "Also, as you make progress toward our shared goals, report back to me periodically and I'll teach you whatever else I can to aid you."
        dialogue 'Dylan', "And finally, I'll let the people here know they can trust you, but cause trouble and you'll be face down on the road you came in on."

        para 'You nod, satisfied both at having finally extracted some useful information and at the chance to start cracking skulls again.'

        self.intro = false
        finish_scene
      end

      choose!
    end
  end

  def show_regular_dialogue
    choice "Deliver a short report on what you've been up to" do
      if player.ready_to_level_up?
        para 'He closes his eyes, nodding as he follows along.'
        dialogue 'Dylan', "You're making good progress here. Let me offer you some advice..."
        choice :l, 'Level up!' do
          proceed_to :level_up
        end
        choice :n, 'Nevermind' do
          # do nothing
        end
      else
        para 'After listening to your brief update, he gives you a disappointed look.'
        dialogue 'Dylan', "I see. Well, keep pressing on and I'm sure something will turn up."
        pause
      end
    end
    say 'Any words of wisdom?' do
      para 'He raises an eyebrow at you, and looks down, resuming his writing.'
      pause
    end

    choice 'Leave' do
      para 'You excuse yourself and leave Dylan in peace.'
      finish_scene
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
  state_variable :found_price_eng, initial: false, shared: true

  def enter
    para 'You stand at the crossroads of the shanty town, sizing up the weathered population for any that might help you.'

    choice :f, 'Go to the forest' do
      proceed_to :assiniboine_forest
    end
    if found_price_eng
      choice :p, 'Go to Price Electronics' do
        proceed_to :price_electronics
      end 
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

    line "Level: #{player.level} ~ Exp: #{player.exp} / #{player.next_level_exp}"

    para "Cash: $#{player.cash}"

    %i[martial evasion fancy unarmed].each do |skill|
      if player.trained_in?(skill)
        line "#{skill.to_s.capitalize} skill: #{player[skill]}"
      else
        defaulted, default_mod = player.default_of(:fancy)
        current = player[defaulted] + default_mod
        line "#{skill.to_s.capitalize} skill: untrained (defaulting at #{current})"
      end
    end
    newline
    line "Weapon: #{player.weapon} ~ Armour: None"
    newline
    choice :w, 'Equip weapon' do
      blank
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
    
    if player.trained_in?(:fancy)
      choice :f, "Train with fancy weapon skill (#{player.fancy} -> #{player.fancy + 1})" do
        player.fancy += 1
      end
    elsif !player.inventory.by_tag(:fancy).empty?
      defaulted, default_mod = player.default_of(:fancy)
      current = player[defaulted] + default_mod
      choice :f, "Train with fancy weapon skill (#{current} -> 7)" do
        player.fancy = 7
      end
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
  state_variable :antagonize, initial: 0

  def enter
    if antagonize < 0
      para "The cook lays broken by the grill."

      if antagonize == -1
        choice :s, "Steal whatever food was already prepped." do
          player.inventory.add(:hamburger, d(4).roll.total)
          player.inventory.add(:slurpee, d(4).roll.total)
          para "You throw your open pack onto the back of the cook, and steal everything on the order counter. At this point you hear murmurs from a forming crowd, so you make a hasty exit."
          pause
          self.antagonize = -2
          finish_scene
        end
      end
    else
      first_enter do
        para "You approach a building with a long corregated steel awning. Numbers that you presume once described the shop's operating hours read '7-11'."
        para "Underneath the awning, a weathered man works a fowl-smelling grill. Tapping his spatula against the surface a few times, he turns to face you."
      end
      
      dialogue 'Cook', "Yeah, what'll it be?"

      say "Is this safe to eat?!" do
        para 'He smiles broadly and leans across the counter toward you.'
        dialogue 'Cook', "Listen punk, you don't want to get on my bad side. I'm gonna ignore that and ask again since I assume you wouldn't be here unless you're hungry: what'll you have?"
        self.antagonize += 1
        pause
      end
  
      if antagonize > 3
        say "Are there no other customers here because they've all died?" do
          para "The cook, finally reaching the limit of verbal abuse he's willing to tolerate, slams the spatula onto the counter."
          dialogue 'Cook', "You motherfucker, what did I tell you?"
          para 'And with that he effortlessly leaps the counter and swings at you!'
          pause
          proceed_to :combat, :cook
          self.antagonize = -1
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
    para 'He mumbles to himself while you browse his offerings.'
    pause
    finish_scene
    proceed_to :barter, 'Blacksmith', %i[shovel knife wavy_sword]
  end
end

class AssiniboineForest < Scene
  def enter
    first_enter do
      para 'You walk into the forest, and the trees dampen the sunlight and noise.'
      para 'The air smells a little cleaner here than the muggy, piss of a breeze in town.'
    end

    para 'Pressing deeper into the forest, you get the sense danger lurks around every bend in the trail.'

    choice :e, 'Explore' do
      proceed_to :combat, Foes.random_encounter(:forest, level_max: player.level)
    end
    if player.inventory.has?(:scouts_note)
      choice :i, "Investigate the perimeter described in the scout's note" do
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

class PriceElectronics < Scene
  # hidden -> hostile -> confront -> friendly -> dead?
  state_variable :progress, initial: 'hidden'
  state_variable :guards, initial: 3
  state_variable :pizza, initial: true
  state_variable :encyclopedia, initial: true

  def enter
    first_enter do
      para "You find the Price Electronics building roughly where the drunk had said it would be. The massive structure must have once housed hundreds of employees, and is oddly untouched by the decay that grips the rest of the city. Perhaps this 'Craig' you're looking for is maintaining the property."
      pause
      para "You decide to play it safe and approach from the rear, entering through a unlocked loading bay."
      pause
    end if progress == 'hidden'

    case progress
    when 'empty'
      para "This building seems somehow lifeless now that it's sole biological occupant has died."
      if player.inventory.has?(:encyclopedia) && player.inventory.has?(:octocopter)
        choice :w, "Use the workshop" do
          para "With no further leads to persue, you reckon you'll have to use the principles found in the encyclopedia you picked up to understand the octocopter drone."
          pause
          finish_scene
        end
      end
      choice :l, "Leave" do
        finish_scene
      end

      choose!
      return
    when 'confront'
      confront_dialogue
      return
    when 'hostile'
      para "You stand in the loading bay, alert to danger now that you know you've been discovered."
    when 'hidden'
      para "You stand in a vast loading bay, long since stripped of any immediately useful eqipment. Remaining are only drums of curious chemicals, scrap metal and other detritus. Light streams in through the bay windows, and you can see signs for administrative offices, a workshop, and an assembly bay."
    end

    choice :o, "Explore the offices" do
      offices
    end
    choice :w, "Explore the workshop" do
      workshop
    end
    choice :a, "Explore the assembly bay" do
      assembly_bay
    end
    choice :l, "Leave" do
      finish_scene
    end
    choose!
  end

  def offices
    para "You proceed into the administrative area, which are filled with the sort of grey, drab cubes that inexplicably fill most of the abandoned office space you have explored."
    pause
    if pizza
      para "You turn next into a kitchen nook, and a smell lingers in the air. A knot forms in your stomach, both from hunger and tension, as you see a hot, half-eaten pizza on a plate. It seems to have been abandoned in haste."
      
      choice :e, "Eat the pizza" do
        para "You haven't had a proper pizza in years, and you marvel at the good fortune of finding it here."
        player.heal(5)
        self.pizza = false
        line "Recovered 5 HP!", color: :secondary
        pause
        para "While stuffing your face, you apparently failed to notice a machine silently roll into the room, which upon being noticed charges into you at full speed!"
        pause
        self.progress = 'hostile'
        fight_minion
      end
    end

    choice :r, "Continue to search" do
      roll = d(3).roll.total

      if progress != 'hostile' || roll == 3
        if encyclopedia
          para "While searching the cubes, you find a general encyclopedia on the principles of electronics and machinery. You've learned that knowledge is power out in the wastes, and slide it into your pack."
          player.inventory.add(:encyclopedia)
          self.encyclopedia = false
          pause
        else
          para "You conduct another sweep of the cubes, but find nothing."
          pause
        end
      else
        para "A machine suddenly bursts through a cube wall!"
        pause
        fight_minion
      end
    end
    choose!
  end

  def workshop
    para "The workshop has a number of angled tables, full of drafting tools and detailed schematics. You walk through, taking in some of the diagrams and writings. They appear to describe autonomous machines of some sort, but have been revised in pencil after printing, adding weapons and other implements."
    if progress == 'hostile'
      para "As you come around a desk, a robot tackles you!"
      pause
      fight_minion
    elsif encyclopedia
      para "You conduct a thorough search, but little of interest can be found here."
      pause
    else
      para "While shuffling through some blueprints on a desk, you hear a voice cry out from behind you."
      dialogue 'Man', "Hey! You're the jerk who took my favourite encyclopedia!"
      pause
      para "The absurdity of the comment catches you off-guard, and before you can recover, a machine is barreling toward you!"
      pause
      self.progress = 'confront'
      fight_minion
    end
  end

  def assembly_bay
    para "You enter the assembly bay, which is large enough that it must occupy most of the building's interior. Crates and other discarded machinery are stacked haphazardly throughout."
    if progress == 'hostile'
      para "Suddenly, a machine flies from the top of one of the stacks, crashing down beside you!"
      pause
      fight_minion
    elsif
      para "You conduct a thorough search, and eventually find some dangerous looking machines lined up against a wall, hooked up to some kind generator."
      choice :d, "Disconnect the machines" do
        para "Suspecting them to be dangerous, you start unplugging the machines. Suddenly, an alarm starts blaring and one of them springs to life!"
        self.guards -= 1
        self.progress = 'hostile'
        pause
        fight_minion
      end
      choice :l, "Leave them alone" do
        para "You examine but otherwise leave the machines alone."
        pause
      end
      choose!
    end
  end

  def confront_dialogue
    if guards > 0
      para "Your eyes sweep the area for threats after dispatching the last killing machine, and you notice a man skulking in the shadows, light gleaming off a device of some kind."

      say :t, "Let's talk this out like adults, there's no need for violence!" do
        if pizza || guards < 2
          para "The room is dead silent for a moment, and the man straightens."
          dialogue 'Man', "Very well! I'll hear you out. Let's talk in my office."
          pause
          make_peace
        else
          dialogue 'Man', "What?! I refuse to negotiate with pizza-theives!"
          para "The man fiddles with the device and you hear the high pitch droning of more machines on the way."
          pause
          fight_minion
          self.guards -= 1
        end
      end
      choice :a, "Charge at the man" do
        fight_minion
        self.guards -= 1
      end
      choose!
    else
      para "The man panics, his hands rapidly working the device, but no other sounds can be heard."
      pause
      para "You flick stray shreds of metal dust casually from your arm, and walk slowly toward the man for effect."
      pause
      dialogue 'Man', "Now now, let's not be too hasty! After all, you're the one who barged into my home, I can't be faulted for defending myself"
      say :t, "Home... so you must be Craig. Let's call a truce then, I only came here to talk." do
        dialogue 'Craig', "Yes, that's me. I have many questions for you as well, let's talk more in my office."
        pause
        make_peace
      end
      say :w, "The time for talk passed when you sicced those stupid machines on me!" do
        craig = Foes.by_id(:craig)
        craig.drops = :encyclopedia if encyclopedia
        proceed_to :combat, craig
        self.progress = 'empty'
      end
      choose!
    end

    def make_peace
      self.progress = 'friendly'
      replace_to :craigs_office
    end
  end

  def fight_minion
    proceed_to :combat, Foes.random_encounter(:price_electronics, level_max: player.level)
    if progress == 'hostile' && d(3).roll.total == 3
      self.progress = 'confront'
    end
  end
end

class CraigsOffice < Scene
  def enter
    para "You enter into the office. Blah blah."
    pause
    finish_scene
  end
end

class Save < Scene
  def enter
    para 'Within the relative safety of the town, you find a comfortable, quiet place to rest.'
    save_file = File.join(__dir__, 'saves', player.name.downcase)
    File.write(save_file, owner.dehydrate.to_json, mode: 'w')
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
    hash = JSON.parse(contents, symbolize_names: true)
    owner.hydrate(hash)
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
