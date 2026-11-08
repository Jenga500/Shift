extends Control

@onready var info_label: Label = $VBoxContainer/HBoxContainer/Label
@export var car: Node3D
var car_velocity: float

func _process(_delta: float) -> void:
	
	if car != null:
		# Speed
		var wheel_speed = car.wheeldata.wheel_angular_velocity[0] * car.VehicleValues.wheel_radius
		var speed = wheel_speed * 3.6 # m/s to km/h
		
		# Gear
		var gear = car.transmission.current_gear - 1
		
		# RPM
		var engine_rpm = car.engine.engine_rpm
		
		
		# Engine state
		var engine_state = ""
		if car.engine.engine_starting:
			engine_state = " | STARTING"
		elif not car.engine.engine_running:
			engine_state = " | ENGINE OFF"
		
		# Traction control
		var tc_state = ""
		if car.assists.tc_on:
			tc_state = " | TC ACTIVE" if car.assists.tc_active else " | TC"
		
		info_label.text = "%d km/h | %d RPM | %d Gear%s%s" % [int(speed), int(engine_rpm), int(gear), engine_state, tc_state]
