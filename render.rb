require 'curses'
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

# abstraction over the awfulness that is curses
class CursesWindow < BaseWindow
  include Curses
  class << self
    attr_accessor :curses_init_done
  end

  def initialize
    super
    # one-time setup needed before buidling curses windows
    CursesWindow.curses_init_done ||= false
    unless CursesWindow.curses_init_done
      init_screen
      start_color
      noecho

      init_pair(COLOR_BLUE, COLOR_BLUE, COLOR_BLACK)
      init_pair(COLOR_RED, COLOR_RED, COLOR_BLACK)

      CursesWindow.curses_init_done = true
    end

    # centered box in terminal, exposing a smaller subwindow that scenes can draw into
    title = '<~~~  SPIX IV  ~~~>'
    @window = Curses::Window.new(25, 80, (Curses.lines - 25) / 2, (Curses.cols - 80) / 2)
    @window.box
    @window.setpos(0, (@window.maxx - title.size) / 2)
    @window << title
    @window.refresh
    @current = @window.derwin(21, 76, 2, 2)
    @current.scrollok(true)
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
    para(text, margin: name.size + 2)
  end

  def choose!(action = nil)
    until @choices.empty?
      newline
      @current << @choices.keys.sort.join(', ') << '> '
      c = (action || @current.getch).to_s.downcase
      if @choices.key?(c)
        newline
        choice = @choices[c]
        @choices.clear
        choice.call
      else
        # why can't I show a subwindow without it mangling what's underneath...
        # dialog = @current.derwin(3, 25, 2, 2)
        # dialog << "INVALID CHOICE: #{c}"
        # dialog.box
        # dialog.getch
        # dialog.close
        # @current.redraw
        action = nil # failsafe for pre-selected invalid options
        line "Invalid option #{c}"
      end
    end
  end

  def line(text, width: @current.maxx, margin: 0, color: :primary)
    words = text.split
    line = ''
    until words.empty?
      word = words.shift
      line += word

      # TODO: + 1 is a hack but curses is so horrible my god
      if words.empty? || words.first.size + line.size + margin + 1 >= width
        @current.setpos(@current.cury, margin)

        # TODO: hack for curses inserting newlines itself, grr
        old_y = @current.cury

        color_attr = case color
                     when :primary
                       COLOR_BLACK
                     when :secondary
                       COLOR_BLUE
                     else
                       raise "wrong color: #{color}"
                     end

        @current.attron(color_pair(color_attr) | A_NORMAL) do
          @current << line
        end
        newline if old_y == @current.cury

        break if words.empty?

        line = ''
      else
        line += ' '
        next
      end
    end
  end

  def prompt(label = '')
    @current << label << '> '
    str = ''
    echo
    str = @current.getstr while str.empty?
    noecho
    str
  end

  def para(text, width: @current.maxx, margin: 0, color: :primary)
    line(text, width:, margin:, color:)
    newline
  end

  def newline
    # @current.setpos(@current.cury + 1, 0)
    @current << "\n" # or else scrolling doesn't work...
  end

  # a dramatic pause for effect
  def pause
    @current << '...'
    @current.getch
    @current.deleteln
    @current.setpos(@current.cury, 0)
  end
end
