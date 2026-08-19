# Development Guidelines

## Project Scope

- This is a Godot 4 top-down 2D survivor roguelite written in GDScript.
- Optimize for a small playable prototype before adding content or framework code.
- Keep the grimdark sci-fi theme in presentation and naming without coupling game logic to specific art assets.

## Architecture

- Put reusable Godot scenes in `scenes/` and GDScript files in `scripts/`.
- Group scenes and scripts by gameplay feature: `player`, `enemies`, `weapons`, `projectiles`, `pickups`, `ui`, and `systems`.
- Put imported source assets in `assets/`, organized by asset type.
- Prefer scene composition and small focused scripts over deep inheritance trees.
- Use signals for events between nodes that should not directly depend on one another.
- Add autoloads only for genuinely global state or services. Do not use an autoload as a general-purpose dependency container.
- Avoid speculative base classes, service layers, registries, and data abstractions. Introduce them only when repeated code or a concrete feature requires them.

## GDScript Style

- Use typed GDScript for properties, parameters, and return values where practical.
- Use `snake_case` for files, variables, functions, and signals.
- Use `PascalCase` for named classes and node names.
- Use `UPPER_SNAKE_CASE` for constants.
- Keep one primary responsibility per script.
- Prefer exported configuration values and resources over unexplained constants embedded in gameplay code.
- Use `@onready` only for references that must wait for the scene tree.

## Scene Guidelines

- Give scene roots descriptive names and attach the feature's primary script to the root when appropriate.
- Keep node paths stable and avoid reaching deeply into another scene's internal hierarchy.
- Reusable scenes should own their internal behavior and expose a small public API, signals, or exported properties.
- Keep UI under `CanvasLayer` or `Control` roots as appropriate, separate from world-space gameplay scenes.

## Assets

- Store source art in `assets/art`, audio in `assets/audio`, and fonts in `assets/fonts`.
- Use lowercase `snake_case` filenames.
- Do not edit generated files under `.godot/`.
- Commit source assets and Godot import metadata that resides beside them unless it is explicitly ignored.

## Verification

- Open the project in the Godot editor after structural or scene changes and resolve parser or import errors.
- Run the smallest relevant scene while developing, then run the project before considering a feature complete.
- Keep warnings actionable; do not suppress them without a documented reason.
- Do not add gameplay behavior as part of unrelated structural or documentation changes.
