# Audio

## Audio players
- Use `AudioStreamPlayer` nodes for sound effects and music. You can have multiple players (e.g. one for SFX, one for Music) in your scenes or an `AudioManager` autoload.
- Organize audio files under `res://assets/audio/` (e.g. `res://assets/audio/explosion.wav`).
- Use separate audio buses (Master, SFX, Music) configured in the Audio panel for volume control.
- Example usage:
  
      var explosion = preload("res://assets/audio/explosion.wav")
      $SfxPlayer.stream = explosion
      $SfxPlayer.play()

      $MusicPlayer.play()  # (assuming a stream is already assigned for background)

## Best practices
- Use short clips for sound effects and longer, looped tracks for background music.
- Ensure only one music track is playing at a time; stop or fade out the previous track before playing a new one.
- Apply user volume settings by calling `AudioServer.set_bus_volume_db()` on the appropriate buses.

## Prohibited patterns
- Do not spawn redundant AudioStreamPlayer nodes for the same sound; reuse existing ones.
- Do not play or control audio on the server side (audio is client-only).