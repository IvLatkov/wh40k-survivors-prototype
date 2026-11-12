# WH40K Survivors Prototype

A 2D top-down survivors-style game prototype made in Godot 4.

The project is currently in active development.

## Engine

Godot 4.6.x

## Current features

- Ultramarine-style playable character
- Bolter ranged combat
- Knife melee combat
- Crit system
- Squig Tier 1 enemies
- Ork Tier 2 enemies
- Ork walking and melee attack animations
- XP skull pickups
- Level-up system
- Weapon upgrades
- Generic upgrades
- Weapon Ultimates
- Ultramarines Chapter perks
- Infinite procedural battlefield terrain
- Chunk streaming
- Deterministic terrain generation
- Optimized swarm/enemy movement
- Floating damage numbers

## Running the project

Source WAV audio is stored with Git LFS. Install Git LFS and run these commands
from the repository before opening the project on a new checkout:

```sh
git lfs install
git lfs pull
```

This downloads the playable audio files rather than leaving LFS pointer files.

Open `project.godot` in Godot 4.6.x, then run the project with F6 for the current scene or F5 for the main scene.
