class Dice
  def initialize(die, times: 1)
    raise "roll what?! #{times}d#{die}" if die < 1 || times < 1

    @times = times
    @die = die
  end

  def *(other)
    @times = other
    self
  end

  def roll(modifier = 0)
    rolls = []
    @times.times do
      rolls << (1 + rand(@die))
    end
    Roll.new(rolls, modifier, self)
  end

  def to_s
    if @times == 1
      "d#{@die}"
    else
      "#{@times}d#{@die}"
    end
  end
end

class Roll
  attr_reader :rolls, :modifier, :dice

  def initialize(rolls, modifier, dice)
    @rolls = rolls
    @modifier = modifier
    @dice = dice
  end

  def total
    @rolls.reduce(&:+) + modifier
  end

  def to_s
    if modifier == 0
      "#{dice} = #{rolls.join('+')}"
    else
      "#{dice}+#{modifier} = #{rolls.join('+')}+#{modifier}"
    end
  end
end

# TODO: support for dice modifiers might be nice, that can be added to roll modifiers
def d(spec)
  if spec.is_a?(Integer)
    Dice.new(spec)
  else
    raise "weird spec: #{spec}" unless spec =~ /\d+?d\d+/

    times, die = spec.split('d').map(&:to_i)
    times = 1 if times < 1 # d4.split gives "", "4" and "".to_i == 0
    Dice.new(die, times:)
  end
end
