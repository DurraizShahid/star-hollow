# Pre-Existing State (baseline audit)

Documented before any feature work began on branch `feat/scientific-planet-simulation`.

## Repository state at start

- Directory: `C:\Users\durra\Documents\star-hollow`
- Not yet a git repository (initialized by this work: `main` baseline commit,
  feature branch `feat/scientific-planet-simulation`).
- Project name: **StarHollow**
- Godot version: **4.7.2 stable** (mono editor build installed at
  `D:\Godot_v4.7.2-stable_mono_win64\`).
- Scripting language: **GDScript** (no `C#` in `config/features`; no `.csproj`
  present; the `[dotnet]` section and `.godot/mono` artifacts are leftovers from
  editor history, not an active C# project).

## Existing files (complete)

```
project.godot      (32 lines; empty app config, window stretch canvas_items/aspect expand,
                    dotnet placeholder, Jolt 3D physics, d3d12 driver)
icon.svg           (default Godot icon)
icon.svg.import    (import settings)
.editorconfig
.gitattributes
.gitignore         (.godot/ and /android/)
.godot/            (engine cache only — not committed)
```

## What did NOT exist

- No scenes (`res://*.tscn`)
- No scripts (`res://*.gd`)
- No main scene, no autoloads, no UI
- No tests
- No documentation beyond engine defaults
- No `res://science`, `res://world`, `res://player`, `res://ui` modules

## Decisions taken

- Keep GDScript (matches the existing feature set; no C# active).
- Keep the existing `project.godot` keys untouched except additions required by
  this feature (main scene, autoloads, renderer/input settings).
- All new code lives under namespaced folders; nothing pre-existing was rewired.