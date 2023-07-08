class Dice
  def initialize(die, times: 1)
    raise "roll what?! #{times}d#{die}" if die < 1 || times < 1
    @times = times
    @die = die
  end

  def *(times)
    @times = times
    return self
  end

  def roll
    rolls = []
    @times.times do
      rolls << 1 + rand(@die)
    end
    return Roll.new(rolls)
  end
end

class Roll
  def initialize(rolls)
    @rolls = rolls
  end

  def total
    @rolls.reduce(&:+)
  end
end

def d(spec)
  if spec.is_a?(Integer)
    Dice.new(spec)
  else
    raise "weird spec: #{spec}" unless spec =~ /\d+?d\d+/
    times, die = spec.split("d").map(&:to_i)
    times = 1 if times < 1 # d4.split gives "", "4" and "".to_i == 0
    Dice.new(die, times: times)
  end
end