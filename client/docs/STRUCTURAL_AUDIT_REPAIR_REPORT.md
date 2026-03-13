# Structural Audit & Repair Report (Godot 4 Client)

Date: 2026-03-13

## Repaired

### 1) Broken script references

- Fixed missing script reference in scene:
  - `scenes/ui/HeroIcon.tscn`
- Added missing script implementation:
  - `scripts/ui/components/hero_icon/HeroIcon.gd`
- Rewired scene to existing valid script path under components.

### 2) Godot 3 -> Godot 4 compatibility

Updated scripts:

- `Player.gd`
  - `extends KinematicBody2D` -> `extends CharacterBody2D`
  - `move_and_slide(velocity, Vector2.UP)` -> `move_and_slide()`
  - `onready` -> `@onready`

- `ItemDrop.gd`
  - `extends KinematicBody2D` -> `extends CharacterBody2D`
  - `move_and_slide(velocity, Vector2.UP)` -> `move_and_slide()`

Updated scenes:

- `Player.tscn`
  - root `KinematicBody2D` -> `CharacterBody2D`
  - `Sprite` -> `Sprite2D`
  - `PoolRealArray` -> `PackedFloat32Array`
  - `RectangleShape2D.extents` -> `size`
  - `format=2` -> `format=3`

- `ItemDrop.tscn`
  - root `KinematicBody2D` -> `CharacterBody2D`
  - `Sprite` -> `Sprite2D`
  - `PoolRealArray` -> `PackedFloat32Array`
  - `RectangleShape2D.extents` -> `size`
  - `format=2` -> `format=3`

### 3) Indentation/syntax

- Runtime/client scripts compile cleanly.
- Non-test script indentation check: no leading-space indentation found.
- Global parse check: no errors found.

### 4) Duplicate scripts removed

Canonical kept in `scripts/utils/`.

Removed duplicates from `scripts/ui/utils/`:

- `scripts/ui/utils/ConfigManager.gd`
- `scripts/ui/utils/ConfigManager.gd.uid`
- `scripts/ui/utils/ServerConfig.gd`
- `scripts/ui/utils/ServerConfig.gd.uid`

### 5) Scene hierarchy/resource validation

- Static root-node check: all scenes have valid root node declarations.
- Scene resource check: no missing `ext_resource` paths remaining.

### 6) Translation system

- `.translation` files were missing.
- Disabled translation loading in `project.godot`:
  - `locale/translations=PackedStringArray()`

### 7) UI module structure

- Added canonical modules folder scaffold:
  - `scripts/ui/modules/README.md`

## Validation Status

- Script diagnostics: pass
- Missing script/resource references in scenes: pass
- Legacy Godot 3 class/type scan (KinematicBody/PoolRealArray/Sprite old type in tscn): pass
- Duplicate UI utils: removed

## Remaining Notes

- Some test files still use space indentation style; runtime scripts are tab-indented and compile cleanly.
- Live editor/runtime verification (opening every scene in Godot editor UI) is still recommended for final sign-off.
