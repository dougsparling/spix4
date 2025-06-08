begin
  require 'pry'
rescue StandardError
  puts "Ignoring missing 'pry' gem"
end

require './scene'
require './render'
require './foes'
require './roll'
require './items'
require './combat'

require './spix4'

# detect irb/require and don't jump into game
return unless $PROGRAM_NAME == __FILE__

window = if ENV['WINDOW']&.downcase == 'plain'
           PlainWindow.new
         else
           require './curses'
           CursesWindow.new
         end

# boolean:true int:42 string:whatever => [true, 42, "whatever"]
scene_params = *(ARGV[1..] || []).map do |param|
  ptype, pvalue = param.split(':')
  case ptype
  when 'boolean'
    pvalue = pvalue.downcase == 'true'
  when 'int'
    pvalue = pvalue.to_i
  end
  pvalue
end

scenes = SceneOwner.new(window)
scenes.proceed_to ARGV.first&.to_sym || :title, *scene_params
scenes.main_loop
