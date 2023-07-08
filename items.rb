require 'csv'

class Items
  attr_reader :items

  def initialize(file)
    lines = CSV.read(file)
    keys = lines.first.map(&:to_sym)

    @items = {}
    lines[1..].each do |line|
      item_raw = Hash[keys.zip(line)]
      id = item_raw[:id]
      item_raw.delete(:id)

      item_raw[:value] = item_raw[:value].to_i
      item_raw[:effect_dice] = d(item_raw[:effect_dice])
      item_raw[:combat] = item_raw[:combat] == 'true'
      item_raw[:tags] = (item_raw[:tags] || "").split("|").map(&:to_sym)

      @items[id.to_sym] = item_raw
    end
  end

  class << self
    def instance
      @instance ||= Items.new(File.join(__dir__, "data", "items.csv"))
    end

    def by_id(id)
      item_raw = instance.items[id] or raise "unknown item: #{id}"
      Item.new(**item_raw)
    end
  end
end