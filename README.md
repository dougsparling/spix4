# Legend of the Evil Spix 4

## What?

I used to make text-based games with QBASIC when I was a kid, so I thought it might be fun to re-make one using Ruby. This is the fourth in a series of such games.

The game itself is mostly just in-jokes, references and nonsense but tries to be balanced and maybe even fun?

## How?

The game can be run with Ruby and runs in the terminal with the [ncurses](https://en.wikipedia.org/wiki/Ncurses) bindings (ncurses is awful and I would never use it again)

```
bundle install
bundle exec ruby main.rb
```

## Spoilers

The game is broken into three parts: grinding and searching a [ruined, post-apocalyptic city](https://en.wikipedia.org/wiki/Winnipeg) for the origins of the Spix, journeying from there [along a perilous route](https://en.wikipedia.org/wiki/Trans-Canada_Highway), and finally [confronting the great evil in its stronghold](https://en.wikipedia.org/wiki/Ottawa).

As of writing the game is far from done!

## Tech Stuff

This project is comprised of two main parts:

* the game content itself, spix4.rb
* the engine, which is spread across the other files

### Scenes

Everything interactive in the game is a `Scene`. Scenes are stored on a stack, you can transition between them, and they carry state that is automatically persisted during the game and when saving+loading.

Scenes are just classes extending from the `Scene` base. They will be instantiated by the engine in order to do some housekeeping, can optionally take constructor parameters that are passed in during transition, and must define an `enter` method:

```
class Tavern < Scene
  state_variable :bar_tab, initial: 0

  def initialize(tavern_name)
    @tavern_name = tavern_name
  end

  def enter
    first_enter do
      para 'You enter the #{@name} for the first time ...'
    end

    para "The regulars grunt and ignore you. The bartender tells you your tab is $ #{bar_tab}"
  end
```

The scenes's `enter` method is run in an endless loop until they either finish, or otherwise alter the stack via a transition such that a new scene is on top:

* `finish_scene` pops the current scene. Note that it does not magically halt execution, so the current invocation of `enter` must then complete as usual.
* `proceed_to(:scene_name)` pushes a new scene onto the stack. Use to move to the user to a new scene, expecting them to return to the current scene later.
* `transition_to(:scene_name)` replaces the entire stack with just this scene. Useful for one-way transitions like game over, returning to the main menu, moving to a new major area with its own gameplay loop, etc.
* `replace_to(*next_scenes)` finishes the current scene and replaces it with one or more replacement scenes. Basically just a convenience method for `finish` + `proceed_to` as this is a common need.

Scene names are expected to be snake-case, and will be camel-cased to find the scene's class. Also, arguments after the name in `proceed_to` and `transition_to` will be passed in-order into the new scene as constructor parameters, but this should be used sparingly (see State section below)

You can see this style of scene management really only lends itself well to a tree of areas to explore where the user backtracks often, which is kinda how old BBS games tended to work. There is no cycle detection; multiple scenes of the same type run more or less independently.

### User Interaction

Because it's a text-based game, dialogue trees, exposition text and gathering user input are handled by `Scene` and are done with Ruby blocks:

```
class TheForest < Scene
  def enter
    para 'You walk into the forest, and the trees dampen the sunlight and noise.'
    choice :e, 'Explore' do
      proceed_to :combat, Foes.random_encounter(:forest, level_max: player.level)
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
```

So `para` writes a paragraph to the screen, choices are built-up using `choice(key)` while the scene is run, and `choose!` forces the player to make a selection by pressing the key indicated by the `key` parameter. Upon choosing, the callback is run, which can then transition or even prompt for further choices. It's easy for complexity+nesting to spiral with this setup, so I would recommend breaking things into new scenes fairly aggressively. 

Other helpful UI methods include:
* `line`, writes a single line to the window
* `newline`, as expected, inserts a blank line
* `pause` requires the user to press a key to continue
* `blank` if the window supports clearing, does so immediately

### Dialogue

Conversation is done through `dialogue` and `say`, which are analagous to `para` and `choice` above, but formats it nicely as a back-and-forth conversation, and simply takes arbitrary names for the participants:

```
say :a, 'You looking for work?' do
    dialogue 'Bob', 'I could do a job for $50 per day'

    if player.cash < 50
        say :d, "I don't have $50." do
            dialogue 'Bob', 'That's a shame.'
            pause
        end
    else
        # ... 
    end
end
choose!
```

### State Management

There are only four engine-provided holders of persistent state:

* the player's character sheet and inventory
* scene state variables setup with `state_variable :var_name`
* shared (global) state: `state_variable :var_name, ..., shared: true`
* the current scene stack -- not accessed directly, only through transitions

Note that scene arguments are conspicuously missing from the list. This means only scenes without arguments can be part of the stack on save. This works because complex scenes like interacting with vendors or fighting in combat aren't intended to be saved. 

Every other part of the game is expected to store state through one of the four sources above. Ideal? No. Good design? Also no. But it works for me.

### Inventory

Items can be important to the plot, equipped as a weapon, and be consumed in and out of battle. Items are loaded from `data/items.csv` and have a few attributes:

* `id`: Items are referred to by this id (symbolized for your convenience)
* `name`: A short name which is presented to the player.
* `value`: The cost of the item when purchased. Also used as the basis for the sale price.
* `description`: Used as a longer description when the player examines an item.
* `effect_dice`: An optional dice expression that is rolled when the item is used. Usage depends on the tag, details below. Doesn't support modifiers, just `{a}d{b}` where `b` is rolled `a` times.
* `tags`: Pipe-delimited set of tags, e.g. `tech|grenade`, explained below:

The tag system is used to organize items and determine usage:

* `heal`: Usable in and out of battle, and roll their effect dice to allow the player to recover HP.
* `plot`: Important for advancing the story and cannot be sold or used, and will not be stolen. Can only be removed from the inventory programmatically.
* `grenade`: Can be consumed during battle to deal its effect dice as damage.
* `weapon`: These are equippable as weapons, and deal their effect dice as damage.
* `fancy` or `tech`: Applied alongside `weapon` or `grenade` tag to items, and indicate that either fancy or tech skill is required for successful usage.

### Debugging

If the game is launched in plain window mode, so `WINDOW=plain ruby main.rb`, the fancy ncursed-based window management is disabled and all text in the game is written plainly to stdout. This makes it much easier to interact with the game via a CLI-based debugger like [Pry](https://github.com/pry/pry).

Also, a specific scene can be run on launch by passing it as an argument, along with arguments prefixed with the type, e.g.

`bundle exec ruby main.rb my_scene boolean:true int:42 string:whatever`

And finally, if you like IRB, you can launch an interactive session by requiring `./main`, and the usual startup sequence will be skipped. Then you can interact with and set up game objects directly. Calling `main_loop` will turn control over to the engine, which by default loops until the scene stack is empty. For finer-grained control, `loop_once` can be used to visit the top-most scene once.

```
$ bundle exec irb
3.2.2 :001 > require './main'
 => true

3.2.2 :002 > scenes = SceneOwner.new(PlainWindow.new)
 => #<SceneOwner:0x0000000100b0fa08 @player=nil, @scenes=[], @state={}, @window=#<PlainWindow:0x0000000100a4eb50>>

3.2.2 :003 > scenes.proceed_to :my_scene

3.2.2 :004 > scenes.loop_once
My scene begins blah blah

3.2.2 :005 > ... continue interactions ...
```
