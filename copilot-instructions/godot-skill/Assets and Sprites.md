# Assets and Sprites

## Asset organization
- Store assets under `res://assets/`, with subfolders for images, UI, audio, etc. For example: `res://assets/sprites/`, `res://assets/ui/`.
- Use lowercase snake_case for asset file names (e.g. `hero_idle.png`, `coin_animation.tres`).
- Use placeholder art files with clear names (e.g. `hero_placeholder.png`) until final assets are available.

## Sprites & Scenes
- Use `Sprite2D` or `AnimatedSprite2D` for 2D game characters and objects.
- Example loading a texture:
  
      var sprite = Sprite2D.new()
      sprite.texture = preload("res://assets/sprites/hero_idle.png")
      add_child(sprite)

- For animations, include an `AnimationPlayer` or `AnimatedSprite2D`:
    - With `AnimatedSprite2D`, preload a `SpriteFrames` resource:
      ```
      var hero_frames = preload("res://assets/sprites/hero_walk.tres")
      $AnimatedSprite2D.frames = hero_frames
      $AnimatedSprite2D.animation = "Walk"
      $AnimatedSprite2D.play()
      ```
    - With `AnimationPlayer`, define animations (e.g. `"Idle"`, `"Run"`) on the node.

## Prohibited patterns
- Do not hard-code asset paths in multiple places; use `preload()` or constants for resources.
- Do not modify imported asset files at runtime; keep art and resource files static in the project.