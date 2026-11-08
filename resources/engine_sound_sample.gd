## One looping engine sound recording and the RPM it was recorded at.
##
## Used in the engine sound lists of the car script (free rev, engine brake,
## partial load, high load). Add as many as you have for different RPM ranges; the engine
## sound mixer crossfades between the two samples closest to the current RPM and
## pitches each by [code]engine_rpm / rpm[/code].
class_name EngineSoundSample
extends Resource

## The looping sound. Set it to loop in its import settings.
@export var stream: AudioStream
## Engine RPM the sound was recorded at.
@export var rpm := 3000.0
