require 'curses'

Curses.init_screen
Curses.start_color
Curses.noecho

# abstraction over the awfulness that is curses
class Window
  def initialize
    # centered box in terminal, exposing a smaller subwindow that scenes can draw into
    title = '~~~  SPIX IV  ~~~'
    @window = Curses::Window.new(25, 80, (Curses.lines - 25) / 2, (Curses.cols - 80) / 2)
    @window.box
    @window.setpos(0, (@window.maxx - title.size) / 2)
    @window << title
    @window.refresh
    @current = @window.derwin(21, 76, 2, 2)
  end

  def blank
    @current.clear
    @current.setpos(0, 0)
  end

  def refresh
    @current.refresh
  end

  def choice(key_or_text, text_with_key = nil, &block)
    key = key_or_text.to_s[0].downcase
    text = text_with_key || key_or_text

    @choices ||= {}
    raise "key #{key} used twice for choice!" if @choices[key]

    @choices[key] = block
    @current << key.upcase << ') '
    line text, margin: 3
  end

  def dialogue(name, text)
    @current << name << ': '
    line(text, margin: name.size + 2)
  end

  def choose!
    until @choices.empty?
      newline
      @current << @choices.keys.sort.join(', ') << '> '
      c = @current.getch.to_s.downcase
      if @choices.key?(c)
        @choices[c].call
        @choices.clear
      else
        dialog = @current.derwin(3, 25, 2, 2)
        dialog << "INVALID CHOICE: #{c}"
        dialog.box
        dialog.getch
        dialog.close
        @current.redraw
      end
    end
  end

  def line(text, width: @current.maxx, margin: 0)
    words = text.split
    line = ''
    until words.empty?
      word = words.shift
      line += word

      if words.empty? || words.first.size + line.size + margin > width
        @current.setpos(@current.cury, margin)

        # TODO: hack for curses inserting newlines itself, grr
        old_y = @current.cury
        @current << line
        newline if old_y == @current.cury

        break if words.empty?

        line = ''
      else
        line += ' '
        next
      end
    end
  end

  def para(text, width: @current.maxx, margin: 0)
    line(text, width:, margin:)
    newline
  end

  def newline
    @current.setpos(@current.cury + 1, 0)
  end

  # a dramatic pause for effect
  def pause
    @current << '...'
    @current.getch
    @current.deleteln
    @current.setpos(@current.cury, 0)
  end
end
