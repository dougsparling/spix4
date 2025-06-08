require 'io/console'

# functionality that doesn't rely on a particular renderer
class BaseWindow
  def say(key_or_text, text_with_key = nil, &block)
    key = key_or_text.to_s[0].downcase
    text = text_with_key || key_or_text
    choice(key, "\"#{text}\"") do
      newline
      dialogue 'You', text
      block&.call
    end
  end
end

# single terminal output that plays nicely with printf and other debugging
class PlainWindow < BaseWindow
  def blank
    # no-op
  end

  def refresh
    # no-op
  end

  def choice(key_or_text, text_with_key = nil, &block)
    key = key_or_text.to_s[0].downcase
    text = text_with_key || key_or_text

    @choices ||= {}
    raise "key #{key} used twice for choice!" if @choices[key]

    @choices[key] = block
    puts "#{key.upcase}) #{text}"
  end

  def dialogue(name, text)
    puts "#{name}: #{text}"
  end

  def choose!(action = nil)
    until @choices.empty?
      newline
      c = (action || $stdin.getch).to_s.downcase

      raise 'weird input, bail!' if c =~ /[^[:print:]]/

      if @choices.key?(c)
        newline
        choice = @choices[c]
        @choices.clear
        choice.call
      elsif c == '10'
        # newline, ignore
      else
        line "Invalid option #{c}"
      end
    end
  end

  def line(text, width: 0, margin: 0, color: nil)
    puts(text)
  end

  def prompt(_label = '')
    @stdout.print("#{prompt}> ")
    @stdout.flush
    $stdin.gets
  end

  def para(text, width: 0, margin: 0)
    line(text)
    newline
  end

  def newline
    puts ''
  end

  def pause
    puts '...'
    $stdin.getch
  end
end