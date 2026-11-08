## Engine sound player that mixes the engine sound slots of the car.
##
## The sounds are assigned in the "Engine Sounds" group of the car script. In
## [method setup] one [AudioStreamPlayer3D] is created as a child of the car for
## each assigned sound; empty slots are skipped and stay silent.
##
## [b]One-shots:[/b] the ignition sound plays when the starter begins cranking,
## the shutdown sound when the engine goes off (switched off or stalled).
##
## [b]Loops[/b] (set the streams to loop in their import settings) all play at
## the same time and are mixed by volume:[br]
## - At the idle target RPM only the idle loops are heard. The cold and warm idle
## loops are crossfaded by [code]engine_warmth[/code].[br]
## - Over [code]sound_idle_blend_range[/code] RPM above idle the idle loops fade
## out and the load loops fade in.[br]
## - The smoothed drivetrain coupling (gear engaged, clutch released, not
## shifting) crossfades between the free rev list (decoupled: neutral or clutch
## pressed) and the in-gear lists. If one side has no sounds, the other side
## plays all the time.[br]
## - The in-gear lists are crossfaded by the smoothed effective throttle: engine
## brake at 0.0, partial load at 0.5, high load at 1.0. An empty list hands its
## share to its neighbours.[br]
## - Inside each load list, the two samples whose recorded RPM is closest to the
## engine RPM (one below, one above) are crossfaded. Below the lowest or above
## the highest sample, only that sample plays.[br]
## Each loop is pitched by [code]engine_rpm / sample rpm[/code], where the sample
## RPM is the engine speed the recording was made at. The loops are silent while
## the engine is off or cranking.
extends Node

## Throttle position each in-gear layer stands for (engine brake, partial,
## high).
const LAYER_LOADS = [0.0, 0.5, 1.0]

## Players of the one-shot sounds. null when the slot is empty.
var ignition_player: AudioStreamPlayer3D
var shutdown_player: AudioStreamPlayer3D
## Players of the idle loops. null when the slot is empty.
var idle_cold_player: AudioStreamPlayer3D
var idle_warm_player: AudioStreamPlayer3D
## A load layer is a dictionary with [code]"rpms"[/code] (recorded RPMs,
## ascending) and [code]"players"[/code] (one player per RPM). Samples without a
## stream are left out.[br]
## The free rev layer, heard while the drivetrain is decoupled.
var free_rev_layer := {}
## The in-gear layers (engine brake, partial load, high load).
var load_layers := []

## Overall volume of the loops (linear 0..1). Fades in when the engine runs and
## out when it stops.
var running_gain := 0.0
## Smoothed throttle used for the load crossfade.
var smoothed_load := 0.0
## Smoothed drivetrain coupling, from 0.0 (decoupled) to 1.0 (in gear, clutch
## engaged), used for the free rev / in-gear crossfade.
var smoothed_coupling := 0.0
## Engine state of the previous frame, to detect start and stop.
var was_starting := false
var was_on := false


## Creates the audio players as children of [param car] from its sound slots.
func setup(car: Node3D) -> void:
	ignition_player = make_player(car, car.sound_ignition, false)
	shutdown_player = make_player(car, car.sound_shutdown, false)
	idle_cold_player = make_player(car, car.sound_idle_cold, true)
	idle_warm_player = make_player(car, car.sound_idle_warm, true)
	free_rev_layer = make_layer(car, car.sounds_free_rev)
	load_layers = [
		make_layer(car, car.sounds_engine_brake),
		make_layer(car, car.sounds_partial_load),
		make_layer(car, car.sounds_high_load),
	]


## Returns a new player for [param stream] added to [param car], or null when the
## slot is empty. Loop players start playing right away at zero volume.
func make_player(car: Node3D, stream: AudioStream, looping: bool) -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = car.engine_sound_bus
	player.volume_db = car.engine_sound_volume_db if not looping else -80.0
	car.add_child(player)
	if looping:
		player.play()
	return player


## Returns a load layer built from [param samples], sorted by RPM, with one
## looping player per sample that has a stream.
func make_layer(car: Node3D, samples: Array[EngineSoundSample]) -> Dictionary:
	var sorted := samples.filter(func(sample): return sample != null and sample.stream != null)
	sorted.sort_custom(func(a, b): return a.rpm < b.rpm)
	var layer := {"rpms": [], "players": []}
	for sample in sorted:
		layer.rpms.append(sample.rpm)
		layer.players.append(make_player(car, sample.stream, true))
	return layer


## Updates the one-shots and the loop mix. Call once per frame.
##
## [param delta] is the frame time in seconds.[br]
## [param car] is the car node with the sound settings.[br]
## [param EngineData] is the runtime engine state (only read).[br]
## [param TransmissionData] is the runtime gearbox state (only read).
func sound_process(delta: float, car: Node3D, EngineData: RuntimeData.engine, TransmissionData: RuntimeData.transmission) -> void:

	# one-shots

	var is_on = EngineData.engine_running or EngineData.engine_starting

	if EngineData.engine_starting and not was_starting:
		stop_player(shutdown_player)
		play_player(ignition_player)
	elif was_on and not is_on:
		stop_player(ignition_player)
		play_player(shutdown_player)

	was_starting = EngineData.engine_starting
	was_on = is_on

	# loop mix

	running_gain = move_toward(running_gain, 1.0 if EngineData.engine_running else 0.0, car.sound_fade_speed * delta)
	smoothed_load = lerpf(smoothed_load, EngineData.throttle, minf(car.sound_load_smoothing * delta, 1.0))

	var in_gear = TransmissionData.current_gear_ratio != 0.0 and not TransmissionData.is_shifting
	var coupling = 1.0 - clampf(EngineData.clutch_input, 0.0, 1.0) if in_gear else 0.0
	smoothed_coupling = lerpf(smoothed_coupling, coupling, minf(car.sound_load_smoothing * delta, 1.0))

	var rpm = EngineData.engine_rpm
	var idle_weight = 1.0 - clampf((rpm - EngineData.idle_target_rpm) / maxf(car.sound_idle_blend_range, 1.0), 0.0, 1.0)
	var load_weight = 1.0 - idle_weight

	# an empty idle slot hands its share to the other one
	var warmth = EngineData.engine_warmth
	if idle_cold_player == null:
		warmth = 1.0
	elif idle_warm_player == null:
		warmth = 0.0

	set_loop(idle_cold_player, idle_weight * (1.0 - warmth), rpm / car.idle_cold_sample_rpm, car)
	set_loop(idle_warm_player, idle_weight * warmth, rpm / car.idle_warm_sample_rpm, car)

	# crossfade between the non-empty in-gear layers by throttle
	var used_layers := []
	var used_loads := []
	for i in range(load_layers.size()):
		if not load_layers[i].players.is_empty():
			used_layers.append(load_layers[i])
			used_loads.append(LAYER_LOADS[i])

	# crossfade between free rev and in-gear by coupling; an empty side hands
	# its share to the other one
	var in_gear_weight = smoothed_coupling
	if free_rev_layer.players.is_empty():
		in_gear_weight = 1.0
	elif used_layers.is_empty():
		in_gear_weight = 0.0

	set_layer(free_rev_layer, load_weight * (1.0 - in_gear_weight), rpm, car)

	var layer_weights = interpolation_weights(used_loads, clampf(smoothed_load, 0.0, 1.0))
	for i in range(used_layers.size()):
		set_layer(used_layers[i], load_weight * in_gear_weight * layer_weights[i], rpm, car)


## Mixes one load layer: crossfades its samples by RPM and pitches each one.
func set_layer(layer: Dictionary, layer_weight: float, rpm: float, car: Node3D) -> void:
	var sample_weights = interpolation_weights(layer.rpms, rpm)
	for i in range(layer.players.size()):
		set_loop(layer.players[i], layer_weight * sample_weights[i], rpm / layer.rpms[i], car)


## Returns one weight per entry of [param points] (ascending) for the value
## [param x]: the two points around [param x] share 1.0 linearly, all others get
## 0.0. Outside the range the first or last point gets 1.0.
func interpolation_weights(points: Array, x: float) -> Array:
	var weights := []
	weights.resize(points.size())
	weights.fill(0.0)
	if points.is_empty():
		return weights
	if x <= points[0]:
		weights[0] = 1.0
		return weights
	for i in range(points.size() - 1):
		if x < points[i + 1]:
			var f = (x - points[i]) / maxf(points[i + 1] - points[i], 0.001)
			weights[i] = 1.0 - f
			weights[i + 1] = f
			return weights
	weights[-1] = 1.0
	return weights


## Sets the volume (equal power from [param weight]) and pitch of a loop player.
func set_loop(player: AudioStreamPlayer3D, weight: float, pitch: float, car: Node3D) -> void:
	if player == null:
		return
	player.volume_db = linear_to_db(maxf(sqrt(weight) * running_gain, 0.0001)) + car.engine_sound_volume_db
	player.pitch_scale = clampf(pitch, 0.1, 4.0)


func play_player(player: AudioStreamPlayer3D) -> void:
	if player != null:
		player.play()


func stop_player(player: AudioStreamPlayer3D) -> void:
	if player != null:
		player.stop()
