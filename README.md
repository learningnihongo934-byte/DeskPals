# DeskPals

A tiny pixel pet that lives on your Mac desktop. It walks along the tops of your windows,
rides them when you drag them around, and reacts to what you do.

Pick one of four pets from the menu bar:

| Pet | Personality |
| --- | --- |
| **Mochi** the cat | Curious, chases your clicks, naps a lot |
| **Gloop** the slime | Slow and bouncy, jumps when you click near it |
| **Ember** the fox | Fast, always checks out new windows |
| **Pip** the dragon | Jumpy, glides down instead of falling |

## What it reacts to

- **New windows and apps**: hops onto a window that just opened to take a look, dances when a music app comes to the front.
- **Mouse clicks**: chases or startles at clicks. Click a lot in a row and it gets dizzy.
- **Typing**: speeds up and cheers while you type, says "phew" after a long typing session.
- **Idle and time of day**: falls asleep when you step away, wakes up when you're back, says good morning, yawns late at night.
- **You**: click it to pet it, drag it to pick it up, and fling it to throw it.

## Settings

Open DeskPals again (from Finder, Spotlight or Launchpad) or choose **Settings…** in the menu bar to pick your pet,
change its size, turn each reaction on or off, set how long you're idle before it naps, hide speech bubbles,
and start DeskPals when you log in.

Privacy: DeskPals only reads window positions, click positions and "a key was pressed recently".
It never reads which keys you press, window titles or anything on screen, and it needs no permissions.

## Build

Needs macOS 13+ and Xcode or the Swift toolchain.

```bash
./build.sh run        # build and launch
./build.sh install    # copy to /Applications
./build.sh preview    # render all the pet art to build/preview.png
```

## Code

- `Pets.swift`: the pets' pixel art (ASCII) and personalities
- `Sprite.swift`: turns the art into images for each pose and eye style
- `World.swift`: finds the visible top edges of windows to stand on
- `Pet.swift`: physics, the behavior state machine and reactions
- `Senses.swift`: watches windows, apps, clicks, typing and idle time
- `PetWindow.swift`: the click-through window the pet is drawn in
- `Settings.swift`: the Settings window and saved preferences
- `Icon.swift`: draws the app icon (built into `AppIcon.icns` by `build.sh`)
- `AppDelegate.swift`: menu bar and the 60 fps loop

Made by **Virat Reddy Kaukuntla** ([@learningnihongo934-byte](https://github.com/learningnihongo934-byte))
