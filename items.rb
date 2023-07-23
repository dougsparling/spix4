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

      # some CSV editors write empty strings instead of just omitting the value
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

  def drain(item)
    amount = quantity(item)
    remove(item, quantity: amount)
    amount
  end

  def quantity(item)
    @items[item] || 0
  end

  def add(item, quantity = 1)
    @items[item] ||= 0
    @items[item] += quantity
  end

  def remove(item, quantity: 1)
    return unless quantity > 0
    raise "removing #{quantity} #{item} that we don't have" unless has?(item) && quantity(item) >= quantity

    @items[item] -= quantity

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
  def initialize(shopkeep_name, goods, accepts = [])
    @shopkeep_name = shopkeep_name
    @goods = goods
    @accepts = accepts
    @selling = false
  end

  def enter
    activity = @selling ? 'Selling to' : 'Buying from'
    para "#{activity} #{@shopkeep_name}. You have $#{player.cash}."

    if @selling
      choice :b, 'Buy' do
        @selling = false
      end
      index = 1
      player.inventory.by_tag(*@accepts).each do |item_id, item, quantity|
        next if item.tagged?(:plot)

        sells_for = [item.value / 4, 1].max
        choice index.to_s, "Sell #{item.name} for $#{sells_for} (#{quantity})" do
          player.inventory.remove(item_id)
          player.cash += sells_for
        end
        index += 1
      end
    else
      unless @accepts.empty?
        choice :s, 'Sell' do
          @selling = true
        end
      end

      @goods.each_with_index do |good_id, index|
        item = Items.by_id(good_id)
        choice (index + 1).to_s, "Inspect #{item.name} ($#{item.value})" do
          inspect_good(good_id)
        end
      end
    end

    choice :f, 'Finished' do
      finish_scene
    end

    choose!
  end

  def inspect_good(good_id)
    item = Items.by_id(good_id)
    para "Inspecting '#{item.name}':"
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
