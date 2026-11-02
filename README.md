# DeskPals

A tiny pixel pet that lives on your Mac. It walks on your windows and your Dock, watches videos with you,
gets hungry, plays ball, and reacts to almost everything you do.

| Pet | Personality |
| --- | --- |
| **Mochi** the cat | Chases clicks and pounces at your cursor, climbs walls, loves fish |
| **Gloop** the slime | Slow, very bouncy, follows your cursor around, loves berries |
| **Ember** the fox | Fast, nosy about new windows, gets the zoomies, loves cookies |
| **Pip** the dragon | Jumpy, glides and flaps instead of falling, puffs fire, loves peppers |

Have as many pets on screen as you like, even several of the same kind. Each one has its own name, needs and outfit.
They say hi when they meet, play tag, and climb onto each other's heads to build pet towers.

## Physics and movement

- Walks along the visible tops of windows and rides them when you drag them
- Stands on text boxes, buttons, toolbars and images inside the app you're using
- Knows when the Dock is hidden (full-screen apps) and walks on the real bottom of the screen
- Gets flung off if you throw a window around too fast
- Hangs off window ledges, then pulls itself up or drops
- Climbs up the sides of the screen (cat and fox), and grabs the wall when you throw it there
- Throw it: it spins, bounces (the slime most of all) and slides when it lands
- The Dock is a trampoline
- Shake it while you hold it and it gets dizzy; it swings like a pendulum while you carry it
- Double-click it for a super jump with a flip
- Hops up onto higher ledges as it walks, and drops to the ground when you switch apps or Spaces
- Dust puffs, sparkles and other particles

## Videos, music and apps

- **Watches videos with you:** it sits at the bottom of the video window with its back to you and a bucket of popcorn, reacts now and then, and dozes off during long ones
- Dances and bobs to music, with little notes
- Walks on your **Dock icons**, hops from icon to icon, says hi to apps you open, and says "eww" at the Trash
- Drop it on the Trash and it pops out angry
- Reacts to Xcode, VS Code, Terminal, Claude, Roblox, Mail, Finder, FaceTime, Photo Booth, the App Store, Activity Monitor and more (and gets jealous of ChatGPT)
- Notices low battery, plugging in and a full charge
- Says hi when your screen wakes up

## Needs and care

- Hunger, happiness and energy, saved between launches
- Feed it fish, berries, cookies or peppers; each pet has a favorite
- Throw a ball and it chases and kicks it around
- Place a bed and it goes there to sleep
- Pet it by clicking it or rubbing your cursor on it
- Your bond grows into levels that unlock a bow, a party hat, sunglasses, a Santa hat and a crown
- Very happy pets sometimes bring you gifts
- Throw it around too much and it sulks

## Moods and personality

- Sits, grooms, stretches, sneezes, looks around and chats
- Eyes follow your cursor, plus happy, sad, angry, dizzy and heart eyes, and blushing
- Gets the zoomies when it's happy
- Falls asleep when you step away, says good morning, and nags you to sleep late at night
- Counts the days you've been together, notices your favorite app, and asks to play when it's bored

## Settings

Open DeskPals again (from Finder, Spotlight or Launchpad) or choose **Settings…** in the menu bar.
The **Pets** tab lists the pets on your screen (click one to edit it, × to remove it), lets you add more,
and has the selected pet's name, needs, care buttons and outfits.
The **Behavior** tab has its size, every reaction on its own switch, nap time, speech bubbles and opening at login.

## Privacy and permissions

DeskPals only reads window positions, click positions, "a key was pressed recently" (never which key),
whether an app is keeping the screen awake (videos), whether the speakers are in use (music), and the battery level.
It never reads window titles or anything on screen.

Walking on individual Dock icons, and standing on text boxes and buttons inside apps, needs Accessibility
permission. DeskPals uses it only to find where those things are (their role and position, never any text).
Without it, the pet walks on top of the Dock as one long ledge and on window tops. Because the app is signed locally,
macOS may ask again after you rebuild it.

## Make your own pet

Put a JSON file in `~/Library/Application Support/DeskPals/Pets/` and restart DeskPals. It shows up next to the built-in pets.

```json
{
  "id": "bolt",
  "name": "Bolt",
  "species": "robot",
  "sound": "beep",
  "art": ["...16 characters per row, up to 16 rows..."],
  "legs": [5, 9],
  "palette": { "o": "22212B", "b": "9AD0FF", "h": "FFFFFF", "K": "111111" },
  "favorite": "cookie",
  "special": "barrage",
  "shout": "BEEP BEEP!",
  "phrases": ["beep", "boop"]
}
```

- Art uses the same letters as the built-in pets (see `Pets.swift`): `1`/`2` mark the eyes, `3`/`4` an eye drawn in the `R` colour, `n` the mouth.
- Optional: `mirrored`, `walkSpeed`, `jumpiness`, `curiosity`, `sleepiness`, `clickStyle` (`chase`/`startle`), `gravity`, `hops`,
  `bounciness`, `zoomy`, `climbs`, `clingy`, `trait`, `backHair` (art rows shown as hair from behind).
- `special`: `fire`, `tentacles`, `spinKick` or `barrage`. `favorite`: fish, berry, cookie, pepper, coffee, taiyaki or cherry.
- `build.sh` also copies any `private-pets/*.json` (git-ignored) into that folder, for pets you keep to yourself.

## Build

Needs macOS 13+ and Xcode or the Swift toolchain.

```bash
./build.sh run        # build and launch
./build.sh install    # copy to /Applications
./build.sh preview    # render all the pet art to build/preview.png
```

## Code

- `Pets.swift`: the pets' pixel art, personalities and outfits
- `Sprite.swift`: turns the art into images for each pose and expression
- `World.swift`: window tops, the Dock, floors and the bed as places to stand
- `Pet.swift`: physics, behavior, needs and reactions
- `Care.swift`: needs, food, the ball, the bed, gifts and particles
- `Senses.swift`: watches windows, apps, clicks, typing, idle time, videos, music and the battery
- `PetWindow.swift`: the click-through window the pet is drawn in
- `CustomPets.swift`: loads your own pets from JSON
- `Settings.swift`: the Settings window and saved preferences
- `Icon.swift`: draws the app icon
- `AppDelegate.swift`: menu bar and the 60 fps loop

Made by **Virat Reddy Kaukuntla** ([@learningnihongo934-byte](https://github.com/learningnihongo934-byte))
