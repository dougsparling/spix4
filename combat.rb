require './scene'
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
    self_succ, self_result = skill_check(recorder, skill, modifier:)
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
    hit, martial_roll = skill_check(recorder, weapon_skill, modifier:)

    return [:miss, martial_roll] unless hit

    if other.can_evade?
      evaded, evade_roll = other.skill_check(recorder, :evasion)
      return [:evade, evade_roll] if evaded
    end

    recorder[other.name.capitalize, " applies damage reduction of #{other.dr}"] if other.dr > 0

    dmg_roll = weapon_dmg.roll(modifier - other.dr)
    recorder[name.capitalize, ' rolling damage: ', dmg_roll]

    other.injure(dmg_roll.total)
    [:hit, dmg_roll]
  end

  def injure(dmg)
    dmg = 0 if dmg < 0
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
$skills = %i[martial evasion fancy unarmed tech]
foe_fields = %i[dr exp attack_verb weapon weapon_dmg finisher drops level habitat tags] + attrs + $skills

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

player_fields = %i[exp level] + attrs + $skills

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
    (level.to_f**1.7).ceil.to_i * 25
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

  def dr
    0 # TODO: armour
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
      player_strike(0)
    end
    choice 'Power Attack' do
      player.forfeit_evade!
      player_strike(2)
    end
    choice 'Inventory' do
      cancel = rummage_through_inventory
      return if cancel
    end
    choice 'Escape' do
      did_run, = player.contest(recorder, foe, :evasion, modifier: 3)

      if did_run && !foe.tagged?(:plot)
        line 'You run in panic stricken fear!'
        pause
        finish_scene [:fled, @foe]
        return
      else
        line "You scramble for an opportunity to escape, but #{@foe.name} gives none."
      end
    end

    choose!

    if foe.slain?
      victory
      finish_scene [:victory, @foe]
    else
      result, roll = foe.strike(recorder, player)
      case result
      when :hit
        if roll.total.positive?
          line "#{foe_name} #{foe.attack_verb} with its #{foe.weapon}, dealing #{roll.total} damage!"
        else
          line "#{foe_name} #{foe.attack_verb}, but the #{foe.weapon} is shrugged off by your armour!"
        end
      when :miss
        line "#{foe_name} #{foe.attack_verb}, but misses!"
      when :evade
        line "#{foe_name} #{foe.attack_verb}, but you narrowly evade!"
      end

      if player.slain?
        totem_id, totem, = player.inventory.by_tag(:totem).sample
        para 'The world begins to darken...'
        if totem
          para "... and the #{totem.name} leaps from your pack, bursting as it absorbs the blow and restores your strength!"
          heal_roll = totem.effect_dice.roll.total
          player.heal(heal_roll)
          player.inventory.remove(totem_id)
        else
          proceed_to :game_over
        end
      end
      pause
    end
  end

  def player_strike(mod)
    result, roll = player.strike(recorder, foe, modifier: mod)
    case result
    when :hit
      if roll.total.positive?
        line "You attack, dealing #{roll.total} damage!"
      else
        line "You hit, but the #{player.weapon} deals no damage!"
      end
    when :miss
      line 'You miss!'
    when :evade
      line "#{foe_name} evades!"
    end
  end

  def victory
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
          skill = $skills.find { |tag| item.tagged?(tag) }

          # succeeds unless skill check required
          success = true
          success, = player.skill_check(recorder, skill) if skill

          if success
            para "You use the #{item.name} and deal #{dmg_roll.total} damage (#{dmg_roll}) damage"
            @foe.injure(dmg_roll.total)
          else
            para "You fumble with the #{item.name} and #{foe.name} avoids the effect."
          end
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
