class Title < Scene
  def enter
    para 'LEGEND OF THE EVIL SPIX IV:', margin: 12
    para 'GHOSTS OF THE WASTES', margin: 16
    5.times { newline }
    line 'Dedicated to the BBS door games of yore,', margin: 4, color: :secondary
    line 'and to friends come and gone', margin: 4, color: :secondary
    5.times { newline }
    choice :n, 'Start a new game' do
      proceed_to :intro
    end
    choice :l, 'Load a saved game' do
      proceed_to :load
    end
    choice :q, 'Quit' do
      finish_scene
    end
    choose!
  end
end

class Intro < Scene
  def enter
    first_enter do
      owner.player = Player.fresh_off_the_boat
    end

    para 'Years of hard travel and violence have brought you to the seated blind man before you.'
    para 'He smiles and opens his arms, sensing your approach.'
    dialogue 'Man', 'To whom do I have the pleasure of speaking?'
    name = prompt 'Name'
    owner.player.name = name
    dialogue 'You', "Call me #{name}, if it pleases you."
    dialogue 'Man', "It does. Pleased to meet you, #{name}. Must have been a difficult journey through the wastes to end up here."

    say "I've buried a few people along the way." do
      player.martial += 2
    end
    say 'Danger is easily avoided if one is ready for it.' do
      player.evasion += 2
    end
    say 'Taken my fair share of bruises but always came out on top.' do
      player.max_hp += 6
      player.hp += 6
    end
    choose!

    para "The man ponders what you've said."
    dialogue 'Man', "Suppose you wouldn't be here otherwise. So what can I do for you? None come all this way if they had a choice."
    dialogue 'You', "I'm seeking any who might hold the secret to the destruction of the Spix."
    dialogue 'Man', "Ahh, there have been a great number before you, and I'm sure there will be a great number after. No matter, I know there is nothing this bitter old man can do to deter you. Rumour has it there is still one who can help --"
    para 'He gestures to a ruined road running north.'
    pause

    dialogue 'Man', "One great city lies in ruin at the end of the road. There are survivors eeking out a living, who will know of one named 'Dylan'. Don't expect them to take kindly to outsiders, #{name}."
    para 'You offer brief thanks to the man, and start walking.'
    pause

    replace_to :intro_town
  end
end

class IntroTown < Scene
  def enter
    para 'You stand on a crumbling highway, having walked for days and finally found civilization. A faded sign shows the former name of this place: Winnipeg.'
    para 'Half an hour of walking beyond the sign reveals little of interest, beyond crumbling buildings that line the horizon and scraps of passed over trash.'
    para 'But, as the blind man had informed you, the telltale signs of residence reveal themselves ahead: smoke from the stacks, the occasional metallic clang of industrious folk.'

    para 'How do you approach?'

    choice 'Casually stroll in and confront your quarry' do
      replace_to :intro_town_casual
    end
    choice 'Sneak into the city and try to find clues' do
      replace_to :intro_town_cautious
    end

    choose!
  end
end

class IntroTownCautious < Scene
  def enter
    para 'You drop low and skirt the edge of the shanty, pausing frequently to assess whether or not anybody has seen you approach...'
    pause
    para 'You take a winding path through ruined buildings, drawing closer to the center of town...'
    pause
    para 'No signs anybody has seen you yet...'
    pause
    para "Then, by pure luck, you overhear a conversation in what must be a tavern beside you, and somebody uses the name 'Dylan'. You decide to capitalize on surprise while you have it, and crash through the nearest window. Acting on instinct, you immediately strike the man engaged in conversation before he can react!"
    pause
    para 'As he shrugs off the kick, unfurls to his full height and squares you up, you suspect that was a mistake.'
    pause

    bruiser = Foes.by_id(:bruiser)
    bruiser.injure(7)

    replace_to :winnipeg
    proceed_to :tavern, true
    proceed_to :combat, bruiser
  end
end

class IntroTownCasual < Scene
  def enter
    bruiser = Foes.by_id(:bruiser)

    para 'Completely confident, you walk toward the shanty, drawing more than a few quick glances from folk peeking out behind drawn curtains.'
    pause
    para 'You plant your boots on the porch of what must pass for a tavern in this hovel, grab a shovel leaning against the railing, and cry out, "Dylan! Show yourself!"'
    pause
    para 'After a moment, an absolute beast of a man kicks the door open, and you hop backwards in surprise. You do not recognize the man.'
    pause
    dialogue bruiser.name,
             "Who the hell are you? Eh, won't matter anyway once I'm scraping you off the bottom of me shoe."
    pause

    player.inventory.add(:shovel)
    player.inventory.equip_weapon(:shovel)

    replace_to :winnipeg
    proceed_to :tavern, true
    proceed_to :combat, bruiser
  end
end

class Tavern < Scene
  state_variable :found_price_eng, initial: false, shared: true
  state_variable :intro, initial: true

  def enter
    para 'You find yourself inside a former sports bar -- broken televisions and torn pendants hang limply on the walls.'

    if intro
      para 'The regulars turn toward the commotion just to time to see the bruiser hit the ground, and collectivity murmur amongst themselves before turning back to their drinks.'
      para "The bartender's eyes flick between you and the man on the floor a few times."
      dialogue 'Bartender', 'Uhh, can I help you with something?'
    else
      para 'The regulars mostly crowd the bar and barely give notice as you saunter up, resting your arms on the only non-sticky patch of wood.'
      dialogue 'Bartender', 'Aye, what do ye want?'
    end

    say :d, "I'm here to see Dylan" do
      dialogue 'Bartender', "Hmm, don't suppose I could stop you if I tried. He's in the back."
      proceed_to :dylan
      self.intro = false
    end
    drink_dialogue if player.cash >= 5

    if !found_price_eng && player.inventory.has?(:octocopter)
      choice :e, 'Ask around if anybody is good with electronics.' do
        ask_about_electronics
      end
    end

    unless intro
      choice 'Leave' do
        para 'You drum your fingers idly on the bar, turn and leave.'
        finish_scene
      end
    end
    choose!
    pause
  end

  def drink_dialogue
    choice :b, "(slide $5 across the bar) I'll have whatever's on tap" do
      player.pay(5)
      dialogue 'Bartender', 'He slaps the cash and slides it behind the bar.'
      case rand(40)
      when 0..34
        para 'He hands you a glass of liquid that you presume must be beer.'
        player.hp += 3
        line '+2 bonus HP.', color: :secondary
      when 35..37
        para 'He serves you a tumbler full of rocks and a clear liquid.'
        dialogue 'Bartender', 'You said you wanted it on the rocks, right?'
        player.hp += 2
        line '+4 bonus HP.', color: :secondary
      when 38
        para 'To your surprise, he places an honest to god bottle of unopened craft beer on the bar and slides you a bottle opener. You look up in disbelief, and the bartender winks at you.'
        dialogue 'Bartender', "Rumour has it you're here to kill the Spix, may as well enjoy your last days on earth, eh?"
        player.max_hp += 1
        player.hp += 1
        line 'Max HP up!', color: :secondary
      else
        dialogue 'Bartender', "Friend, I think you've had enough. Go get some air."
        para 'You turn and leave, suddenly realizing he never gave you back your money.'
        finish_scene
      end
    end
  end

  def ask_about_electronics
    para 'You saddle up to the bar and place the octocopter in front of some regulars.'
    drop_topic = false
    while !found_price_eng && !drop_topic
      say :a, 'Anybody know how these things work?' do
        dialogue 'Drunk', 'I might know a guy, for $50 I could introduce you.'

        if player.cash < 50
          say :d, "I don't have $50." do
            para 'He shrugs and takes another sip from his drink.'
            pause
          end
        else
          choice :d, 'Slide him $50.' do
            player.cash -= 50
            para 'His eyes light up for a moment, then he plays it cool and slips the bills into his jacket.'
            dialogue 'Drunk', "Alright pard'ner, look for a guy named Craig. Bit of a loner, you can find him in the ol' Price Electronics building just north of downtown."
            self.found_price_eng = true
            para 'You thank him for his time and stand up, picking up the drone.'
            pause
          end
        end

        choice :a, "Give him an ass-whoopin'" do
          para 'You kick him off his stool and square up.'
          proceed_to :combat, :extortionate_drunk
          self.found_price_eng = true
        end
      end

      say :t, "If I find out one of you sumbitches was flying this thing I'll kick your asses into the street." do
        para 'The regulars give each other a look and raise their hands in innocence.'
      end

      say :d, 'Drop the topic.' do
        para "You mumble a 'thanks anyway' and stuff the drone back into your pack."
        drop_topic = true
      end
      choose!
    end
  end
end

class Dylan < Scene
  state_variable :intro, initial: true
  state_variable :ready_to_go, initial: false

  def enter
    para "You enter Dylan's room, and you see a man sitting behind a desk -- one who clearly doesn't have as much trouble finding a meal as the other wasters around here."
    para 'He looks up from a notebook, mid-scribble, and sighs.'
    dialogue 'Dylan', "Alright, out with it then. Let's not waste time."
    para 'Several potential questions come to mind...'
    say 'What is it that you do here?' do
      dialogue 'Dylan', "I'm the mayor of this town, or what's left of it."
    end
    if intro
      show_spix_dialogue
    else
      show_regular_dialogue
    end
    choose!
    pause
  end

  def show_spix_dialogue
    say 'Can you help me defeat the Spix?' do
      para 'His overworked chair groans loudly has he leans back, and he is suddenly overcome with a look of pain.'
      dialogue 'Dylan', 'I once thought so, perhaps decades ago. Now, I am not so sure.'

      say "I see, I suppose I'll just fuck off back into the wastes then?" do
        para "He shoots you a tentative glance suggesting you're welcome to do so at your leisure."
      end

      say "Hey, I didn't come all this way for nothing. I'm told you're the only man that can stop this damn thing." do
        para 'He stops massaging his forehead for a moment and chuckles.'
        dialogue 'Dylan', "Huh, I'm surprised there are any whispers of my old reputation these days. Well, it's true, there is something I could do."
        pause
        para 'He stands, stretching, and turns to look out the single, grimy window above his desk.'
        dialogue 'Dylan', "There was a time when things weren't like this, you know..."
        pause

        blank
        para "Your eyes begin wandering the room awkwardly while his self-indulgant monologing rolls on, and after a few minutes, you suddenly realize he has finished by the intense stare he's giving you."
        say "Uh, of course, let's do whatever you just said."
        say 'Sorry, I got distracted for a minute looking at your impressive, uh, dust collection.'
        choose!

        dialogue 'Dylan', "Right... anyway, as I saying, Hammond started this whole mess with his work prototyping the early Spix, and he must have kept detailed notes. Bring them to me, and I'll take it from there. Hammond's lab was supposedly underground in Assiniboine forest, though it's overrun with raiders and other nasties these days."
        dialogue 'Dylan', "Also, as you make progress toward our shared goals, report back to me periodically and I'll teach you whatever else I can to aid you."
        dialogue 'Dylan', "And finally, I'll let the people here know they can trust you, but cause trouble and you'll be face down on the road you came in on."

        para 'You nod, satisfied both at having finally extracted some useful information and at the chance to start cracking skulls again.'

        self.intro = false
        finish_scene
      end

      choose!
    end
  end

  def show_regular_dialogue
    choice "Deliver a short report on what you've been up to" do
      if player.ready_to_level_up?
        para 'He closes his eyes, nodding as he follows along.'
        dialogue 'Dylan', "You're making good progress here. Let me offer you some advice..."
        choice :l, 'Level up!' do
          proceed_to :level_up
        end
        choice :n, 'Nevermind' do
          # do nothing
        end
      else
        para 'After listening to your brief update, he gives you a disappointed look.'
        dialogue 'Dylan', "I see. Well, keep pressing on and I'm sure something will turn up."
        pause
      end
    end

    say 'Any words of wisdom?' do
      para 'He raises an eyebrow at you, and looks down, resuming his writing.'
      pause
    end

    if ready_to_go
      say :o, "I'm ready for the trip to Ottawa." do
        dialogue 'Dylan', "Great. The wagon's out back, ready to hit the trail to Oregon."
        dialogue 'You', 'Oregon?'
        dialogue 'Dylan', 'Sorry, Ottawa. Wrong game.'
        para "You only have a beat to ponder what he's talking about before he leads you out into the main room of the tavern. Seems a small crowd has formed."
        dialogue 'Dylan', 'My fellow countrymmen! The time has come for us to embark upon --'
        pause
        blank
        para 'You tune out yet another one of his self-aggrandizing speeches and look out into the crowd, and they seem to be eating it up.'
        para "Soon he's out among people, saying goodbyes and shaking hands. People only give you an occasional glance or a polite nod. You'd think people would be more appreciative of your efforts."
        para 'After doing a few rounds, both through the crowd and at the bar, Dylan is back beside you and notices your expression.'
        pause
        dialogue 'Dylan', "I know what you're thinking. But the truth is folks here don't have much hope, 'specially for so-called heroes. And now, in their eyes, because of you their leader is leaving. Probably never to return. So don't hold it against them."
        para 'He claps your shoulder and leads you out the back door. You ponder the fates of the simple folk in the bar, then turn and leave.'
        transition_to :caravan
      end
    elsif player.inventory.has?(:blueprints)
      say "I've got the blueprints from Hammond's lab." do
        para 'He drops his pen and abruptly stands up.'
        dialogue 'Dylan', "You do? Let's see them."
        para 'You pull out the blueprints and unroll them on his desk. He leans in for a better look.'
        pause
        dialogue 'Dylan', "Hmm. Just as I thought, completely impervious to a conventional attack. Ah, but look here, there's a thermal exhaust port that runs straight to the reactor core!"
        para 'He grins and looks up at you expectantly. When you fail to respond, his grin disappears.'
        dialogue 'Dylan', "Oh come on, that was perfect. Ugh, okay, let's see what else we can find..."
        pause
        para 'He continues to comb over the blueprints, and after a few minutes begins to tap a spot on the page absentmindedly.'
        dialogue 'Dylan', 'I wonder -- seems as through the interior of it is lined with access corridors. Just big enough for maintenance crews to crawl through. Somebody inside them could also deal some real damage. But either way, have to get in somewhere.'
        para 'He traces his finger through the blueprints with one hand, and the other tugs at what little hairs remains on his head.'
        pause
        dialogue 'Dylan', "There is a hatch near the base of its 'spine', but it's just as armoured as the rest of it. There must have been some kind of key to open it. Hmm, maybe there's a note about it, oh!"
        para 'Suddenly his eyes light up and he starts flipping back through pages.'
        dialogue 'Dylan', "There's a part number! And see here, there's a vendor listed. Oh. Oh no."
        pause
        dialogue 'You', 'What?'
        dialogue 'Dylan', 'The vendor was a small outfit in Ottawa.'
        dialogue 'You', 'So?'
        dialogue 'Dylan', "Didn't you get an education out there? Ottawa was the capital. First, it's easily more than two thousand kilometers from here. Second, it was captured by the American military when the fighting started."
        para "He pauses for a moment while you wish he'd hurry up with all this."
        pause
        dialogue 'Dylan', 'It became their forward base during the invasion. They never pulled out.'
        dialogue 'You', 'So that means--'
        dialogue 'Dylan', "That means they're still there, #{player.name}! The goddamn military is still there."
        pause
        dialogue 'You', "I see, so it's months of walking that ends with either my death or a slim chance of finding what I'm looking for."
        dialogue 'Dylan', 'Pretty much.'
        dialogue 'You', "And even if I succeed, the hard part hasn't even started yet."
        dialogue 'Dylan', 'Ah, yup.'
        para 'He forces a laugh and struggles to hold together a smile.'
        pause
        dialogue 'You', "Guess I'll be hitting the road then."
        para 'He grits his teeth and rolls his head, settling his gaze at the ceiling.'
        dialogue 'Dylan', "Ah dammit. This is too important to leave to one person. Give me some time to round up anybody willing to help, and we'll form a caravan. We can cover food, transport, navigation. You can handle security, and of course I'll manage the whole thing."
        dialogue 'You', "That's unexpectedly generous."
        dialogue 'Dylan', "Well, we're just lifting you up to the jaws of the beast, you'll still have to take the leap yourself."
        dialogue 'Dylan', "Anyway, go wrap up any loose ends in town and meet me here when you're done."
        finish_scene
        self.ready_to_go = true
      end
    end

    choice 'Leave' do
      para 'You excuse yourself and leave Dylan in peace.'
      finish_scene
    end
  end
end

class GameOver < Scene
  def enter
    para 'You fall to the ground helplessly, and your final thoughts are of the Spix and the doomed people of Winnipeg...'
    pause
    exit
  end
end

class Winnipeg < Scene
  state_variable :found_price_eng, initial: false, shared: true

  def enter
    para 'You stand at the crossroads of the shanty town, sizing up the weathered population for any that might help you.'

    choice :f, 'Go to the forest' do
      proceed_to :assiniboine_forest
    end
    if found_price_eng
      choice :p, 'Go to Price Electronics' do
        proceed_to :price_electronics
      end
    end
    choice :t, 'Enter the tavern' do
      proceed_to :tavern
    end
    choice :c, "See what's cooking" do
      proceed_to :cooking
    end
    choice :b, 'Visit the blacksmith' do
      proceed_to :blacksmith
    end
    choice :s, 'Find a shanty to curl up and rest in (save)' do
      proceed_to :save, 'Within the relative safety of the town, you find a comfortable, quiet place to rest.'
    end
    newline
    choice :m, 'View character sheet' do
      proceed_to :character_sheet
    end

    choose!
  end
end

class CharacterSheet < Scene
  def enter
    para "~~~ #{player.name}'s Stats ~~~"

    para "#{player.hp} / #{player.max_hp} HP"

    line "Level: #{player.level} ~ Exp: #{player.exp} / #{player.next_level_exp}"

    para "Cash: $#{player.cash}"

    %i[martial evasion fancy unarmed tech].each do |skill|
      if player.trained_in?(skill)
        line "#{skill.to_s.capitalize} skill: #{player[skill]}"
      else
        defaulted, default_mod = player.default_of(skill)
        if defaulted.nil?
          current = 10 + default_mod
          line "#{skill.to_s.capitalize} skill: #{current} (untrained, no default)"
        else
          current = player[defaulted] + default_mod
          line "#{skill.to_s.capitalize} skill: #{current} (untrained, defaulting)"
        end
      end
    end
    newline
    line "Weapon: #{player.weapon} ~ Armour: None"
    newline
    choice :w, 'Equip weapon' do
      blank
      weapons = player.inventory.filter { |_, item| item.tagged?(:weapon) }
      if weapons.empty?
        line "Seems you don't have any implements of violence among your meager posseessions."
        pause
      else
        # TODO: can probably extract a generic inventory picker from this...
        idx = 1
        weapons.each do |item_id, item, _quantity|
          choice idx.to_s, "Equip '#{item.name}'" do
            para "You grip the #{item.name} in your hands and turn it over a few times. Better than nothing, you suppose."
            player.inventory.equip_weapon(item_id)
            pause
          end
          idx += 1
        end
        unless player.inventory.eq_weapon.nil?
          choice :u, 'Remove equipped weapon' do
            player.inventory.equip_weapon(nil)
          end
        end
        choice :n, 'Leave equipment alone for now' do
          # nothing
        end
        choose!
      end
    end
    choice :i, 'Inventory' do
      blank
      para 'You dump your rucksack onto the ground, and take stock of everything inside:'
      line 'Moths fly from the empty sack.' if player.inventory.empty?

      player.inventory.each do |_, item, quantity|
        line "#{quantity} #{item.name}"
      end
      newline
      pause
    end

    choice :d, 'Done' do
      finish_scene
    end

    choose!
  end
end

class LevelUp < Scene
  def enter
    next_level = player.level + 1
    para "Welcome to level #{next_level}!"

    choice :m, "Train martial skill (#{player.martial} -> #{player.martial + 1})" do
      player.martial += 1
    end
    choice :e, "Train evasion skill (#{player.evasion} -> #{player.evasion + 1})" do
      player.evasion += 1
    end
    choice :h, "Train body (#{player.max_hp} -> #{player.max_hp + 3} HP)" do
      player.max_hp += 3
    end

    if player.trained_in?(:fancy)
      choice :f, "Train with fancy weapon skill (#{player.fancy} -> #{player.fancy + 1})" do
        player.fancy += 1
      end
    elsif !player.inventory.by_tag(:fancy).empty?
      defaulted, default_mod = player.default_of(:fancy)
      current = player[defaulted] + default_mod
      choice :f, "Train with fancy weapon skill (#{current} -> 7)" do
        player.fancy = 7
      end
    end

    if player.trained_in?(:tech)
      choice :t, "Train technology skill (#{player.tech} -> #{player.tech + 1})" do
        player.tech += 1
      end
    elsif !player.inventory.by_tag(:tech).empty?
      # TODO: tech doesn't default, really need to factor out skill logic...
      _, default_mod = player.default_of(:tech)
      current = 10 + default_mod
      choice :t, "Train technology skill (#{current} -> 9)" do
        player.tech = 9
      end
    end

    choose!

    player.level += 1
    player.hp = player.max_hp
    para "Under Dylan's tutilage, you prepare for whatever the wastes will throw at you next."
    pause
    finish_scene
  end
end

class Cooking < Scene
  state_variable :antagonize, initial: 0

  def enter
    if antagonize < 0
      para 'The cook lays broken by the grill.'

      if antagonize == -1
        choice :s, 'Steal whatever food was already prepped.' do
          player.inventory.add(:hamburger, d(4).roll.total)
          player.inventory.add(:slurpee, d(4).roll.total)
          para 'You throw your open pack onto the back of the cook, and steal everything on the order counter. At this point you hear murmurs from a forming crowd, so you make a hasty exit.'
          pause
          self.antagonize = -2
          finish_scene
        end
      end
    else
      first_enter do
        para "You approach a building with a long corregated steel awning. Numbers that you presume once described the shop's operating hours read '7-11'."
        para 'Underneath the awning, a weathered man works a fowl-smelling grill. Tapping his spatula against the surface a few times, he turns to face you.'
      end

      dialogue 'Cook', "Yeah, what'll it be?"

      say 'Is this safe to eat?!' do
        para 'He smiles broadly and leans across the counter toward you.'
        dialogue 'Cook', "Listen punk, you don't want to get on my bad side. I'm gonna ignore that and ask again since I assume you wouldn't be here unless you're hungry: what'll you have?"
        self.antagonize += 1
        pause
      end

      if antagonize > 3
        say "Are there no other customers here because they've all died?" do
          para "The cook, finally reaching the limit of verbal abuse he's willing to tolerate, slams the spatula onto the counter."
          dialogue 'Cook', 'You motherfucker, what did I tell you?'
          para 'And with that he effortlessly leaps the counter and swings at you!'
          pause
          proceed_to :combat, :cook
          self.antagonize = -1
        end
      end

      choice :b, "See what's on the menu" do
        proceed_to :barter, 'Cook', %i[hamburger slurpee]
      end
    end

    choice :l, 'Leave' do
      finish_scene
    end

    choose!
  end
end

class Blacksmith < Scene
  def enter
    para 'You approach the source of all the racket around here, and an elderly wisp of a man wearing a faded t-shirt covered in foreign writing hammers relentlessly on a feeble looking knife.'
    dialogue 'Blacksmith', "Greetings weary traveler! Might thy wishest to, uh, partake in mine fine goods around yonder? Or is it 'thou'..."
    para 'He mumbles to himself while you browse his offerings.'
    pause
    finish_scene
    proceed_to :barter, 'Blacksmith', %i[shovel knife wavy_sword]
  end
end

class AssiniboineForest < Scene
  # hidden -> found -> alive | dead
  state_variable :hammond, shared: true, initial: 'hidden'

  def enter
    first_enter do
      para 'You walk into the forest, and the trees dampen the sunlight and noise.'
      para 'The air smells a little cleaner here than the muggy, piss of a breeze in town.'
    end

    para 'Pressing deeper into the forest, you get the sense danger lurks around every bend in the trail.'

    choice :e, 'Explore' do
      proceed_to :combat, Foes.random_encounter(:forest, level_max: player.level)
    end

    if hammond != 'hidden'
      choice :i, 'Head directly to the concealed hatch' do
        proceed_to :hammond_lab
      end
    elsif player.inventory.has?(:receiver)
      choice :i, 'Use the receiver to hone in on the source of the drone signals' do
        proceed_to :hammond_approach
      end
    elsif player.inventory.has?(:scouts_note)
      choice :i, "Investigate the perimeter described in the scout's note" do
        proceed_to :combat, Foes.random_encounter(:hammond_perimeter, level_max: player.level + 1)
      end
    end
    choice :c, 'Camp' do
      proceed_to :camp
    end
    choice :l, 'Leave' do
      finish_scene
    end
    choose!
  end
end

class Camp < Scene
  def enter
    para 'As the daylight wanes, you question the wisdom of making the trek back to town in the dark.'
    para 'After a quick survey, you find a small concealed clearing and set up camp, listening intently for lurking dangers.'
    para 'Eventually your guard slips and you are embraced by sleep...'
    pause

    case rand(40)
    when 1..20
      if player.hp > player.max_hp
        para 'You enter a restless sleep as the effects of the alcohol progress'
        line 'You awaken with a hangover', color: :secondary
      else
        para 'You enjoy a deep and uninterrupted sleep'
        line 'HP fully recovered!', color: :secondary
      end
      player.hp = player.max_hp
      pause
      finish_scene
    when 21..30
      para 'You awaken to the sound of brush crunching underfoot. You spring from your tent to confront whatever is out there...'
      pause
      finish_scene
      proceed_to :combat, Foes.random_encounter(:camp, level_max: player.level)
    when 31..38
      para 'However, distant but unnerving noises interrupt your sleep throughout the night.'
      recovered = [d('2d4').roll.total, player.max_hp - player.hp].min
      line "Recovered #{recovered} HP!", color: :secondary
      player.hp = player.max_hp
      pause
      finish_scene
    else
      para "In the middle of the night, something rouses you from sleep, although there's no noise or shadows playing across the tent. You decide to investigate, and see the clouds have parted to reveal a full moon."
      pause
      finish_scene
    end
  end
end

class HammondApproach < Scene
  state_variable :hammond, shared: true

  def initialize
    @signal_strength = rand(1..10)
  end

  def enter
    first_enter do
      para 'Pulling out the receiver, you check the batteries and click it on. The arm of a tiny meter wavers as you sweep the device through the air. You will have to walk in order to know if the signal is getting weaker or stronger.'
    end

    para "Signal strength: #{@signal_strength}%"

    choice :w, 'Walk toward likely sources of signal' do
      adj = rand(-8..31)
      @signal_strength = (@signal_strength + adj).clamp(0, 100)

      proceed_to :combat, Foes.random_encounter(:hammond_perimeter, level_max: player.level + 2)
    end
    if @signal_strength >= 100
      choice :s, 'Search this area' do
        self.hammond = 'found'
        para 'With the arm of the meter buried, you must be at the source of the signal. You search, and quickly spot a wire leading up a tree, hooked to an antenna. Following the wire down, you brush leaves aside and discover a concealed hatch!'

        choice :e, 'Open and enter the hatch' do
          replace_to :hammond_lab
        end
        choice :m, 'Mark the area on your map and leave' do
          finish_scene
        end
        choose!
      end
    end
    choice :l, 'Abandon progress and leave this area of the forest' do
      finish_scene
    end
    choose!
  end
end

class HammondLab < Scene
  state_variable :hammond, shared: true
  state_variable :sacked, initial: false

  def enter
    first_enter do
      para 'You open the hatch, and pull a flashlight from your pack. Flicking it on and holding it in your teeth, you illuminate a long shaft and begin to descend.'
      pause
      para 'At the bottom of the shaft, you find what seems to be some kind of survivalist bomb shelter.'
      pause
    end

    para 'Crates of valuable equipment lie in various states of pillage, and discarded bottles and empty boxes of food litter the floor.'

    if hammond == 'dead'
      para 'The body of a man lies on the floor.'
    else
      para 'You are overwhelmed by the smell of a blob of a man lying in an office chair, wearing a headset of some kind. His hands are wrapped around a pair of tiny devices, which he waves seemingly at random through the air.'
    end

    if hammond == 'found'
      para "He is so totally engrossed in whatever he's doing that you are able to approach undetected."

      choice :k, 'Attack the man while he is vulnerable' do
        self.hammond = 'dead'
        proceed_to :combat, :hammond
      end

      choice :s, "Get the man's attention" do
        self.hammond = 'alive'
        hammond_intro_dialogue
      end
    end

    if hammond == 'alive'
      dialogue 'Hammond', 'Feel free to let yourself out.'

      choice :a, 'Attack him' do
        self.hammond = 'dead'
        proceed_to :combat, :hammond
      end
    end

    unless sacked
      choice :r, 'Ransack the place' do
        self.sacked = true
        para "Looking for notes that may be of use to Dylan, you roll up several large sheets of blue paper, which you are assume are blueprints. Because, you know, they're blue."
        player.inventory.add(:blueprints)
        para 'You also grab as many unopened boxes of food as will fit in your pack.'
        player.inventory.add(:mre, 5)
        pause
      end
    end

    choice :l, 'Ascend the ladder' do
      para 'You climb back up the ladder'
      pause
      finish_scene
    end

    choose!
  end

  def hammond_intro_dialogue
    para 'You brace yourself for a reaction, and kick the arm of his chair. He jerks backward so hard he is almost dumped onto the ground. He fumbles the headset off and lets out a nasal whine.'
    dialogue 'Hammond', "Wahh, you're the goon that keeps killing all my guards and smashing all my expensive toys!"
    dialogue 'You', 'And you must be Hammond.'
    dialogue 'Hammond', 'Yes, in the flesh.'

    done = false
    until done
      say :w, 'What exactly are you doing here?' do
        dialogue 'Hammond', "Humph, I wouldn't expect a goon like you to understand. Let's just say I'm working to ensure the survival of my little gang here."
        pause
      end
      say :g, 'Who are all those violent thugs outside? You their boss?' do
        dialogue 'Hammond', "That's right. I give them food and equipment, and they run... errands for me."
        pause
      end
      say :d, 'Dylan says you were involved in the early work on the Spix.' do
        dialogue 'Hammond', "Ah ha ha, the old fool still curses my name over that, eh? I won't deny it, I had a hand in the end of the world. Most would have shirked away from such a task, oh morals this, or impossible that. But not us!"

        say :u, 'Us?' do
          dialogue 'Hammond', "Of course there were others! We're out of touch these days, forgot to top up my cell plan before armageddon."
          pause
        end

        say :w, "Well, congratulations on your success. Now I'm going to stop it." do
          dialogue 'Hammond', "Ha, are you now? Ah, now I see, this has nothing to do with me or revenge, or else we wouldn't be having this conversation. You're looking for scraps or clues that might reveal an exploitable weakness."
          para 'Hammond chuckles, tenting his fingers into the semblance of a pack of sausages.'
          pause
          dialogue 'Hammond', "Well, I think you'll find it quite indestructable and your task quite hopeless. But don't let me stop you if you want to commit suicide, easier than having my folks mop you up."

          if sacked
            para 'His eyes wander to a box in the corner of the room.'
            dialogue 'Hammond', "Seems you've already helped yourself to whatever you've wanted. What are you talking to me for?"
          else
            self.sacked = true
            player.inventory.add(:blueprints)
            pause
            para 'You follow his pointing finger to a large box, and rummage through it, pulling out some blue sheets of paper.'
            pause
            dialogue 'Hammond', "Now if you'll excuse me, you're hardly the only threat to be concerned with out here."
          end

          done = true

          para 'He places the headset back over his eyes and resumes whatever he was doing earlier.'
          pause
        end

        choose!
      end

      choose!
    end
  end
end

class PriceElectronics < Scene
  # hidden -> hostile -> confront -> friendly -> dead?
  state_variable :progress, initial: 'hidden'
  state_variable :guards, initial: 3
  state_variable :pizza, initial: true
  state_variable :encyclopedia, initial: true

  def enter
    if progress == 'hidden'
      first_enter do
        para "You find the Price Electronics building roughly where the drunk had said it would be. The massive structure must have once housed hundreds of employees, and is oddly untouched by the decay that grips the rest of the city. Perhaps this 'Craig' you're looking for is maintaining the property."
        pause
        para 'You decide to play it safe and approach from the rear, entering through a unlocked loading bay.'
        pause
      end
    end

    case progress
    when 'empty'
      empty_dialogue
      return
    when 'friendly'
      para 'You enter the Price Electronics building by the front door, and are greeted by a robot that salutes with a blood-soaked bat as you pass. You glance at the machine and try to remember if the blood is yours...'
      pause
      replace_to :craigs_office
      return
    when 'confront'
      confront_dialogue
      return
    when 'hostile'
      para "You stand in the loading bay, alert to danger now that you know you've been discovered."
    when 'hidden'
      para 'You stand in a vast loading bay, long since stripped of any immediately useful eqipment. Remaining are only drums of curious chemicals, scrap metal and other detritus. Light streams in through the bay windows, and you can see signs for administrative offices, a workshop, and an assembly bay.'
    end

    choice :o, 'Explore the offices' do
      offices
    end
    choice :w, 'Explore the workshop' do
      workshop
    end
    choice :a, 'Explore the assembly bay' do
      assembly_bay
    end
    choice :l, 'Leave' do
      finish_scene
    end
    choose!
  end

  def offices
    para 'You proceed into the administrative area, which are filled with the sort of grey, drab cubes that inexplicably fill most of the abandoned office space you have explored.'
    pause
    if pizza
      para 'You turn next into a kitchen nook, and a smell lingers in the air. A knot forms in your stomach, both from hunger and tension, as you see a hot, half-eaten pizza on a plate. It seems to have been abandoned in haste.'

      choice :e, 'Eat the pizza' do
        para "You haven't had a proper pizza in years, and you marvel at the good fortune of finding it here."
        player.heal(5)
        self.pizza = false
        line 'Recovered 5 HP!', color: :secondary
        pause
        para 'While stuffing your face, you apparently failed to notice a machine silently roll into the room, which upon being noticed charges into you at full speed!'
        pause
        self.progress = 'hostile'
        fight_minion
      end
    end

    choice :r, 'Continue to search' do
      roll = d(3).roll.total

      if progress != 'hostile' || roll == 3
        if encyclopedia
          para "While searching the cubes, you find a general encyclopedia on the principles of electronics and machinery. You've learned that knowledge is power out in the wastes, and slide it into your pack."
          player.inventory.add(:encyclopedia)
          self.encyclopedia = false
          pause
        else
          para 'You conduct another sweep of the cubes, but find nothing.'
          pause
        end
      else
        para 'A machine suddenly bursts through a cube wall!'
        pause
        fight_minion
      end
    end
    choose!
  end

  def workshop
    para 'The workshop has a number of angled tables, full of drafting tools and detailed schematics. You walk through, taking in some of the diagrams and writings. They appear to describe autonomous machines of some sort, but have been revised in pencil after printing, adding weapons and other implements.'
    if progress == 'hostile'
      para 'As you come around a desk, a robot tackles you!'
      pause
      fight_minion
    elsif encyclopedia
      para 'You conduct a thorough search, but little of interest can be found here.'
      pause
    else
      para 'While shuffling through some blueprints on a desk, you hear a voice cry out from behind you.'
      dialogue 'Man', "Hey! You're the jerk who took my favourite encyclopedia!"
      pause
      para 'The absurdity of the comment catches you off-guard, and before you can recover, a machine is barreling toward you!'
      pause
      self.progress = 'confront'
      fight_minion
    end
  end

  def assembly_bay
    para "You enter the assembly bay, which is large enough that it must occupy most of the building's interior. Crates and other discarded machinery are stacked haphazardly throughout."
    if progress == 'hostile'
      para 'Suddenly, a machine flies from the top of one of the stacks, crashing down beside you!'
      pause
      fight_minion
    elsif para 'You conduct a thorough search, and eventually find some dangerous looking machines lined up against a wall, hooked up to some kind generator.'
      choice :d, 'Disconnect the machines' do
        para 'Suspecting them to be dangerous, you start unplugging the machines. Suddenly, an alarm starts blaring and one of them springs to life!'
        self.guards -= 1
        self.progress = 'hostile'
        pause
        fight_minion
      end
      choice :l, 'Leave them alone' do
        para 'You examine but otherwise leave the machines alone.'
        pause
      end
      choose!
    end
  end

  def confront_dialogue
    if guards > 0
      para 'Your eyes sweep the area for threats after dispatching the last killing machine, and you notice a man skulking in the shadows, light gleaming off a device of some kind.'

      say :t, "Let's talk this out, there's no need for violence!" do
        if pizza || guards < 2
          para 'The room is dead silent for a moment, and the man straightens.'
          dialogue 'Man', "Very well! I'll hear you out. Let's talk in my office."
          pause
          make_peace
        else
          dialogue 'Man', 'What?! I refuse to negotiate with pizza-theives!'
          para 'The man fiddles with the device and you hear the high pitch droning of more machines on the way.'
          pause
          fight_minion
          self.guards -= 1
        end
      end
      choice :a, 'Charge at the man' do
        fight_minion
        self.guards -= 1
      end
      choose!
    else
      para 'The man panics, his hands rapidly working the device, but no other sounds can be heard.'
      pause
      para 'You flick stray shreds of metal dust casually from your arm, and walk slowly toward him for effect.'
      pause
      dialogue 'Man', "Now now, let's not be too hasty! After all, you're the one who barged into my home, I can't be faulted for defending myself."
      say :t, "Home... so you must be Craig. Let's call a truce then, I only came here to talk." do
        dialogue 'Craig', "Yes, that's me. If you're willing to talk, let's go into my office."
        pause
        make_peace
      end
      say :w, 'The time for talk passed when you sicced those stupid machines on me!' do
        craig = Foes.by_id(:craig)
        craig.drops = :encyclopedia if encyclopedia
        proceed_to :combat, craig
        self.progress = 'empty'
      end
      choose!
    end
  end

  def empty_dialogue
    para "This enormous building seems somehow lifeless now that it's sole biological occupant has died. There is nothing but silence and dust slowly sifting from the ceiling."
    if player.inventory.has?(:encyclopedia) && player.inventory.has?(:octocopter)
      choice :w, 'Use the workshop' do
        para "With no further leads to persue, you reckon you'll have to use the principles found in the encyclopedia you picked up to understand the octocopter drone."
        pause
        para 'You dig up some equipment from the workshop, and start reading about radios, signal analysis, power...'
        pause
        para 'Stumbling upon a means of measuring signal strength, you excitedly clear a desk and start taking apart the drone...'
        pause
        para "You don't notice hours pass, then an entire night, and are suddenly startled as you awaken sometime during the afternoon. You look around nervously but you are still alone."
        pause
        player.inventory.remove(:octocopter)
        success, = player.skill_check(recorder, :tech)
        if success
          para "You've done it! A crude but effective measure of distance to whoever or whatever is controlling the octocopters, and others like it."
          player.inventory.add(:receiver)
        else
          para 'You look down at what you accomplished overnight: not much, aside from destroying the drone.'
        end
        pause
      end
    end
    choice :l, 'Leave' do
      finish_scene
    end

    choose!
  end

  def make_peace
    self.progress = 'friendly'
    replace_to :craigs_office
  end

  def fight_minion
    proceed_to :combat, Foes.random_encounter(:price_electronics, level_max: player.level)
    return unless progress == 'hostile' && d(3).roll.total == 3

    self.progress = 'confront'
  end
end

class CraigsOffice < Scene
  state_variable :intro, initial: true
  state_variable :like, initial: 0
  def enter
    para "You stand inside Craig's small office, which consists of boxes rostling for space with a desk underneath a bunk bed, tucked into a room barely large enough to hold both. Boxes stacked neatly along the walls provide only a narrow path to the chair Craig is sitting in."
    para 'He awkwardly shuffles his glance between his work, you and your weapon and gives you a forced smile.'

    return intro_dialogue if intro

    unless player.inventory.has?(:receiver)
      choice :d, 'Ask about using one of the octocopter drones to find the operator.' do
        dialogue 'Craig', 'Only if you tell him the mighty Craig sent you, mwahahaha!'
        para 'After a beat you realize this was a joke and give a polite chuff in response.'
        if player.inventory.has?(:octocopter)
          para 'You flip open bag while expressing thanks, and pull out an octocopter, dropping it on his desk. Craig winces as the dirty thing lands on a stack of papers, and moves it to an empty surface.'
          pause
          para 'Without delay, he excitedly starts prying, spudging, loosening and unscrewing various parts, mumbling things and laughing to himself about inappropriate use of inverse reactive current and slipshod unilateral phase detractors...'
          pause
          para 'A few key parts are removed and hooked into a web of leads, probes and clips. Drawers are opened, more implements employed, things are soldered, unsoldered, re-soldered, and you roll your head, stiff from watching so intently.'
          pause
          para "Finally, you hadn't even realized he finished as he hands you a device."
          dialogue 'Craig', 'This will show you the signal strength of the transmitter. The closer you are, the stronger the signal. You can figure it out from there.'
          player.inventory.remove(:octocopter)
          player.inventory.add(:receiver)
          para 'You nod thanks and drop the device into your bag.'
          pause
        end
      end
    end

    choice :b, 'Ask about any other equipment he might be willing to part with' do
      proceed_to :barter, 'Craig', %i[first_aid snitch frag]
    end

    choice :l, 'Leave.' do
      para 'You make some small talk and politely excuse yourself.'
      pause
      finish_scene
    end

    choose!
  end

  def intro_dialogue
    say 'Nice place you have here.' do
      dialogue 'Craig', "Thank you. I'm sure yours is just as nice."
      para 'Your mouth is half open as you are about to comment on your present state of homelessness, but think better of it.'
      self.like += 1 if like == 0
      pause
    end
    say "Let's cut to the chase here, I'm told you're the guy if I need to figure out the source of the drones in Assiniboine forest." do
      para 'Craig throws himself forward in the chair and raps his palm across the desk.'
      dialogue 'Craig', "That hack! He has no idea what he's doing! Just the other day I found some of his 'work', one of those drones snooping around in here. Fool couldn't tell a multimeter from an oscilloscope! You can't produce magneto reluctance AND capacitive reactance from modial interactions, it's ..."
      pause
      para "At this point, your eyes glaze over, and for awhile you simply nod at critical moments, breathing deliberately to try and lower your blood pressure. After a minute, you realize he probably isn't going to stop for awhile."

      choice 'Interrupt' do
        para 'You abruptly speak in the middle of a comment on the relaxive motion of conductors and fluxes.'
        dialogue 'You', 'Look, are you going to help me or not?'
        para "Craig pauses, staring at the ceiling, as if he'd just jumped off the train of thought long before reaching the station."
        pause
      end
      choice 'Wait for a natural break in his rant before interjecting' do
        self.like += 3
        para 'You continue to feign interest for what feels like an hour, but is probably only a few more minutes. Finally, Craig reaches for a cup of water and takes a sip.'
        dialogue 'You', 'He sure sounds like a second-rate operator.'
        dialogue 'Craig', "Exactly, that's what I was saying!"
        pause
      end
      if player.trained_in?(:tech)
        say :t, "I've noticed problems with his work as well (tech)" do
          para 'You both converse for awhile on exactly why the unnamed drone operator in question is a know-nothing tool.'
          self.like += 5
        end
      end
      choose!
      para "After a bit more back and forth, like a ship's captain fighting a storm, you take the wheel and steer the conversation slowly toward your needs."
      pause
      self.intro = false
    end
    choose!
  end
end

class Caravan < Scene
  state_variable :kms, initial: 0
  state_variable :food, initial: 28
  state_variable :crew, initial: 4

  def enter
    para 'You walk alongside a small caravan, bound for Ottawa.'
    line "Distance covered: #{kms} / 2068 km"
    line "Food remaining: #{food} days"
    para "Crew: #{crew} people"

    choice :p, 'Press onward' do
      blank
      para 'Dylan agrees, and gives the order to press on. You venture ahead to deal with any threats, and the wagon picks up behind you.'
      pause
      proceed_to :combat, Foes.random_encounter(:ottawa_road, level_min: player.level - 5, level_max: player.level)
      self.kms += d('4d10').roll.total + Dice.new(6, times: crew).roll.total
    end

    choice :t, 'Stop and scavage for supplies' do
      stop_and_scavage
    end

    choice :c, 'Pull off and make camp for the evening' do
      camp
    end

    choice :d, 'Have a chat with Dylan' do
      chat_dylan
    end
    line ''
    choice :s, 'Hop onto the back of the wagon and rest (save)' do
      proceed_to :save, 'You allow yourself a few hours of shuteye while the wagon bobs along.'
    end
    newline
    choice :m, 'View character sheet' do
      proceed_to :character_sheet
    end
    choose!
  end

  def stop_and_scavage
    para 'You spot a promising area to scavage, and signal the caravan to hold while you run over to investigate.'
    pause
    case rand(8)
    when 0
      para "Closing in on what looks like a supply cache, you realize too late that it's a trap!"
      pause
      proceed_to :combat, Foes.random_encounter(:ottawa_road, level_max: player.level + 2)
    when 1
      para "You enter an abandoned roadside station, and discover it hasn't been completely picked over yet."
      para 'You find: '

      something = false
      if rand(5) == 0
        line 'Enough food to feed the crew for a day.'
        self.food += 1
        something = true
      end

      if rand(10) == 0
        line 'A first aid kit.'
        player.inventory.add(:first_aid)
        something = true
      end

      if rand(20) == 0
        line 'A frag grenade.'
        player.inventory.add(:frag)
        something = true
      end

      if rand(50) == 0
        line 'A cache containing a well-maintained rifle and several clean boxes of ammo.'
        player.inventory.add(:rifle)
        something = true
      end

      unless something
        line 'A few dollars.'
        player.cash += 2
      end
      pause
    when 2..3
      para 'You cautiously approach a shanty town, and its inhabitants seem eager to trade.'
      pause
      proceed_to :barter, 'Trader', %i[knife full_syringe road_chow first_aid shovel].sample(3)
    end
  end

  def camp
    para 'You see an area of natural concealment off the road, and signal the caravan to pull over. Dylan and the others jump down and begin pulling supplies from the wagon.'
    para 'After a quick meal, you help clean up and turn in for the night.'
    para 'That night --'
    pause
    # TODO
    para '-- nothing else of consequence happens. HP recovered!'
    player.hp = player.max_hp
    self.food -= 1
    pause
  end

  def chat_dylan
    para 'You walk alongside the wagon, where Dylan is perched up on the seat. He acknowledges you with a nod.'
    choice 'Discuss the progress of the caravan' do
      if player.ready_to_level_up?
        para 'You discuss the challenges encountered and what lies ahead.'
        dialogue 'Dylan', "We've come far, but there is still much you don't know about these roads. I'd be happy to share."
        choice :l, 'Level up!' do
          proceed_to :level_up
        end
        choice :n, 'Nevermind' do
          # do nothing
        end
      else
        para "After a brief update, it becomes apparent there isn't much to discuss."
        pause
      end
    end
    choice :l, 'Make small talk and excuse yourself.' do
      para 'You wander idly through a few different topics, and eventually resume your duty watching the caravan.'
      pause
    end
    choose!
  end
end
