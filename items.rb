require 'csv'
require './scene'

class Items
  attr_reader :items

  def initialize(file)
    lines = CSV.read(file)
    keys = lines.first.map(&:to_sym)

    @items = {}
    lines[1..].each do |line|
      item_raw = keys.zip(line).to_h
      id = item_raw[:id]
      item_raw.delete(:id)

      # some CSV editors write empty strings in instead of just omitting the value
      item_raw.delete_if { |_, value| value.empty? }

      item_raw[:value] = item_raw[:value].to_i
      item_raw[:effect_dice] = d(item_raw[:effect_dice]) if item_raw[:effect_dice]
      item_raw[:combat] = item_raw[:combat] == 'true'
      item_raw[:tags] = (item_raw[:tags] || '').split('|').map(&:to_sym)

      @items[id.to_sym] = item_raw
    end
  end

  class << self
    def instance
      @instance ||= Items.new(File.join(__dir__, 'data', 'items.csv'))
    end

    def by_id(id)
      raise "not symbol: #{id}" unless id.is_a? Symbol

      item_raw = instance.items[id] or raise "unknown item: #{id}"
      Item.new(**item_raw)
    end

    def valid_id?(id)
      instance.items.key?(id)
    end
  end
end

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
    { items:, eq_weapon: }
  end

  def self.hydrate(hash)
    hash[:eq_weapon] = hash[:eq_weapon]&.to_sym

    invalid = [hash[:eq_weapon], hash[:items].keys].flatten.compact.select { |id| !Items.valid_id?(id) }
    raise "hydration with invalid items: #{invalid}" unless invalid.empty?

    Inventory.new(**hash)
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
