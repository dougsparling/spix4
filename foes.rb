require 'csv'

class Foes
  attr_reader :foes

  def initialize(file)
    lines = CSV.read(file)
    keys = lines.first.map(&:to_sym)

    @foes = {}
    lines[1..].each do |line|
      foe_raw = Hash[keys.zip(line)]
      id = foe_raw[:id]
      foe_raw.delete(:id)

      # ugh
      [:attack, :defense, :hp, :exp, :cash].each do |key|
        foe_raw[key] = foe_raw[key].to_i
      end

      # TODO: unsupported... yet?
      foe_raw.delete(:drops)

      @foes[id.to_sym] = foe_raw
    end
  end

  class << self
    def instance
      @instance ||= Foes.new(File.join(__dir__, "data", "enemies.csv"))
    end

    def by_id(id)
      foe_raw = instance.foes[id] or raise "unknown foe: #{id}"
      Foe.new(**foe_raw)
    end
  end
end