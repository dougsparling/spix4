require 'csv'

class Foes
  attr_reader :foes

  def initialize(file)
    lines = CSV.read(file)
    keys = lines.first.map(&:to_sym)

    @foes = {}
    lines[1..].each do |line|
      foe_raw = keys.zip(line).to_h
      id = foe_raw[:id]
      foe_raw.delete(:id)

      # some CSV editors write empty strings instead of just omitting the value
      foe_raw.delete_if { |_, value| value.empty? }

      # ugh
      %i[martial evasion hp exp cash dr].each do |key|
        foe_raw[key] = foe_raw[key].to_i
      end
      foe_raw[:weapon_dmg] = d(foe_raw[:weapon_dmg])
      foe_raw[:max_hp] = foe_raw[:max].to_i
      foe_raw[:habitat] = (foe_raw[:habitat] || '').split('|').map(&:to_sym)
      foe_raw[:level] = foe_raw[:level]&.to_i || 0

      foe_raw[:tags] = (foe_raw[:tags] || '').split('|').map(&:to_sym)

      drop_table = (foe_raw[:drops] || '').split('|').map do |drop|
        drop_id, freq = drop.split(':')
        [drop_id.to_sym, freq&.to_f || 1.0]
      end
      foe_raw[:drops] = drop_table.to_h

      @foes[id.to_sym] = foe_raw
    end
  end

  class << self
    def instance
      @instance ||= Foes.new(File.join(__dir__, 'data', 'enemies.csv'))
    end

    def by_id(id)
      raise "must be symbol: #{id}" unless id.is_a? Symbol
      foe_raw = instance.foes[id] or raise "unknown foe: #{id}, loaded: #{instance.foes.keys.sort}"
      Foe.new(**foe_raw)
    end

    def random_encounter(habitat, level_min: 1, level_max: 999)
      level_range = level_min..level_max
      matching = instance.foes.filter do |_, foe_raw|
        foe_raw[:habitat].include?(habitat) && level_range.include?(foe_raw[:level])
      end
      pick = matching.keys.sample
      raise "can't satisfy query" unless pick

      by_id(pick)
    end
  end
end
