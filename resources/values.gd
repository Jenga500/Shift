## Tuning data for a single car: chassis, suspension, steering, brakes,
## driver assists, engine, drivetrain, wheels, tires and debug options.
##
## This resource only stores values. It contains no simulation logic, so the
## vehicle scripts (for example the engine and drivetrain script) read these
## properties and do the actual calculations. Create a [code].tres[/code] file
## of this type to define a car, and edit it in the Inspector, where the
## properties are grouped by system.
##
## [b]Per-wheel arrays[/b] use the order 0 = front left (FL), 1 = front right
## (FR), 2 = rear left (RL), 3 = rear right (RR).
##
## [b]Units[/b] are SI unless stated otherwise: meters, kilograms, seconds,
## newton-meters for torque, kg·m² for inertia, and RPM for engine speed.
## Where a unit is not obvious from the name it is described on the property.
##
## [b]Note:[/b] the empty functions such as [method car] and [method suspension]
## do nothing. They are placeholders that mark the start of each section of the
## file.
class_name CarValues
extends Resource

@export_group("Car")

## Distance between the front and rear axles, in meters.
@export var wheel_base = 2.265 
## Distance between the left and right wheels of an axle (track width), in
## meters.
@export var track = 1.41
## Aerodynamic drag coefficient (Cd) of the body. Air drag is
## [code]0.5 * air_density * drag_coefficient * frontal_area * v²[/code],
## opposing the body's velocity.
@export var drag_coefficient = 0.38
## Frontal area of the body used for air drag, in m².
@export var frontal_area = 1.9
## Density of the air used for air drag, in kg/m³.
@export var air_density = 1.225

## Placeholder marking the "Car" section. Does nothing.
func car():
	pass

@export_group("Suspension")

## Natural frequency of each corner's spring, in Hz. Used to derive the spring
## stiffness for that wheel.
@export var ride_frequency = [1.0, 1.0, 1.0, 1.0]
## Maximum suspension compression of each wheel, in meters.
@export var max_compression = [0.11, 0.11, 0.11, 0.11]
## Share of the car's weight carried by each wheel. The four values are
## fractions and should add up to 1.0.
@export var weight_distribution = [0.25, 0.25, 0.25, 0.25]
## Damping ratio of each corner's damper. A value of 1.0 is critical damping;
## lower values are underdamped and bouncier.
@export var damper_ratio = [0.69, 0.69, 0.75, 0.75]
## Enables the rear anti-roll bar when true.
@export var rear_antiroll_bar = true
## Enables the front anti-roll bar when true.
@export var front_antiroll_bar = true
## Stiffness of the front anti-roll bar. Has no effect if
## [member front_antiroll_bar] is false.
@export var front_antiroll_bar_stiffness = 8500.0
## Stiffness of the rear anti-roll bar. Has no effect if
## [member rear_antiroll_bar] is false.
@export var rear_antiroll_bar_stiffness = 2500.0
## Exponent applied to suspension velocity when computing damping force.
## 1.0 gives ordinary linear damping.
@export var velocity_exponent = 1.0

## Placeholder marking the "Suspension" section. Does nothing.
func suspension():
	pass

@export_group("Steering")

## Maximum steering angle of the front tires, in degrees.
@export var max_tire_turn_angle = 38.0
## Total travel of the steering wheel from one lock to the other, in degrees.
@export var steering_wheel_travel = 1000.0
## Steering ratio: how many degrees the steering wheel turns for one degree of
## tire turn.
@export var steering_ratio = 15.0
## How quickly the tires move toward the requested steering angle. Higher
## values respond faster.
@export var tire_turn_speed = 3.5
## Stiffness of the steering, which affects how strongly the wheel returns to
## center and how it feels under load.
@export var steering_stiffness = 720.0
## Speed sensitive steering: the steering angle is divided by
## [code]1 + speed_factor_coeff * speed_in_km/h[/code]. With 0.05 a full key
## press turns the tires about 10° at 50 km/h and 6° at 100 km/h instead of the
## full lock. Higher values steer less at speed; 0.0 turns it off (for steering
## wheel controllers).
@export var speed_factor_coeff = 0.05
## Amount of Ackermann steering geometry. 0.0 turns both front wheels by the
## same angle, 1.0 is full Ackermann (the inner wheel turns more than the outer).
@export var ackermann_factor = 1.0

## Placeholder marking the "Steering" section. Does nothing.
func steering():
	pass

@export_group("Brake")

## Maximum braking torque the brakes can apply, in N·m.
@export var max_brake_torque = 900.0
## Handbrake torque on each handbrake wheel at full lever, in N·m. It must be
## high enough to lock the wheels for drifting.
@export var max_handbrake_torque = 2000.0
## Whether the handbrake acts on the front left, front right, rear left and rear
## right wheel (in that order).
@export var handbrake_wheels = [false, false, true, true]
## In the clutchless and automatic transmission modes, opens the automatic
## clutch while the handbrake is pulled, so the engine keeps revving in a drift.
@export var handbrake_opens_clutch = true

## Placeholder marking the "Brake" section. Does nothing.
func brake():
	pass

@export_group("Assists")

## Placeholder marking the "Assists" section. Does nothing.
func assists():
	pass

@export_subgroup("ABS")

enum ABSType {
	## ABS Modes, changing how ABS behaves per wheel.
	PerWheel,
	SingleUnit
}

var current_abs_mode = ABSType.SingleUnit

## Enables the anti-lock braking system when true.
@export var ABS = false
## Rate at which ABS acts (how quickly it applies brake pressure). On a 1.0-0.0 scale of input.
@export var abs_rate_apply = 0.0
## Rate at which ABS acts (how quickly it releases brake pressure). On a 1.0-0.0 scale of input.
@export var abs_rate_release = 0.0
## Slip ratio  which ABS starts reducing brake force. Braking slip is
## negative, so this is a negative number.
@export var abs_slip_apply = -0.25
## Slip ratio  which ABS starts increasing brake force. Braking slip is
## negative, so this is a negative number.
@export var abs_slip_release = -0.10
## Target brake input after ABS is enabled. On a 1.0-0.0 scale of input.
@export var abs_pedal_target = 0.2

@export_subgroup("TC")

## Traction control is on when the car starts. The player can switch it with
## the ToggleTC action; from code use [code]car.assists.tc_on[/code].
@export var TC = false
## Slip ratio of a driven wheel above which traction control steps in. About
## 0.1 to 0.15 gives the most grip; higher values allow some wheel spin.
@export var tc_slip_threshold = 0.12
## How fast traction control closes the throttle while a wheel spins, in full
## throttle per second.
@export var tc_cut_rate = 6.0
## How fast traction control gives the throttle back once the wheels grip
## again, in full throttle per second.
@export var tc_recover_rate = 2.0
## Brake torque, in N·m, that traction control puts on a single spinning driven
## wheel (for example one wheel on grass with an open differential). 0.0 uses
## only the throttle.
@export var tc_brake_torque = 300.0
## Below this ground speed, in m/s, the slip is measured against this speed
## instead, so pulling away from a standstill does not read as endless slip.
@export var tc_min_speed = 3.0

@export_subgroup("Stability")

## Stability control switch. Not implemented yet, and not exported, so it does
## not appear in the Inspector.
var Stability = false # a thing to work on

@export_group("Motor")

## Placeholder marking the "Motor" section. Does nothing.
func motor():
	pass

## Returns which wheels receive engine torque as
## [code][FL, FR, RL, RR][/code] booleans, from [member drive_type].
func driven_wheels() -> Array:
	match drive_type:
		DriveType.RWD:
			return [false, false, true, true]
		DriveType.FWD:
			return [true, true, false, false]
		DriveType.AWD:
			return [true, true, true, true]
	return [FL_torque_engine, FR_torque_engine, RL_torque_engine, RR_torque_engine]

## Peak engine torque, in N·m. The [member torque_curve] is scaled by this
## value.
@export var max_torque = 136.0
## Rev limiter. The engine is not driven above this speed, in RPM. Also used to
## normalize RPM when sampling [member torque_curve].
@export var max_rpm = 7200.0
## Engine idle speed, in RPM.
@export var idle_rpm = 800.0
## RPM below which the engine stalls when the clutch is loading it. 0.0
## disables stalling.
@export var stall_rpm = 0.0
## Idle speed of a cold engine, in RPM. The idle target moves from this value
## to [member idle_rpm] as the engine warms up.
@export var cold_idle_rpm = 1200.0
## Largest throttle opening the idle control may use to hold the idle speed
## (0 to 1).
@export var idle_throttle_max = 0.25
## How long the starter cranks before the engine runs, in seconds. Match this
## to the length of the cranking part of the ignition sound.
@export var starter_crank_time = 0.8
## Torque of the starter motor, in N·m at the crankshaft.
@export var starter_torque = 40.0
## Speed the starter spins the engine up to, in RPM.
@export var starter_rpm = 250.0
## When true, the engine is already running (and warm) when the scene starts.
@export var start_engine_running = false
## Engine warmth when the scene starts, from 0.0 (cold) to 1.0 (warm). Ignored
## when [member start_engine_running] is true.
@export var initial_engine_warmth = 0.0
## Time a running engine takes to warm up from cold at idle, in seconds. Higher
## RPM warms it faster.
@export var warmup_time = 180.0
## Time a switched off engine takes to cool down from warm, in seconds.
@export var cooldown_time = 600.0
## Rotational inertia of the engine (flywheel and rotating parts), in kg·m².
@export var engine_inertia = 0.1
## Constant term of the engine friction polynomial, in N·m.
@export var friction_c0 = 3.0
## Linear term of the engine friction polynomial. Multiplied by normalized RPM
## (RPM divided by [member max_rpm]).
@export var friction_c1 = 4.5
## Quadratic term of the engine friction polynomial. Multiplied by the square of
## normalized RPM.
@export var friction_c2 = 8.0
## Which wheels the engine drives.
enum DriveType {
	## Rear wheel drive.
	RWD,
	## Front wheel drive.
	FWD,
	## All wheel drive. The front/rear split is [member center_diff_split].
	AWD,
	## Uses the four per-wheel flags below ([member FL_torque_engine] and so on).
	CUSTOM
}

## Drivetrain layout. Use [method driven_wheels] to read the result.
@export var drive_type: DriveType = DriveType.RWD
## Whether the front left wheel receives engine torque. Only used when
## [member drive_type] is CUSTOM.
@export var FL_torque_engine = false
## Whether the front right wheel receives engine torque (CUSTOM only).
@export var FR_torque_engine = false
## Whether the rear left wheel receives engine torque (CUSTOM only).
@export var RL_torque_engine = true
## Whether the rear right wheel receives engine torque (CUSTOM only).
@export var RR_torque_engine = true
## Whether the front right wheel has brakes.
@export var FR_torque_brake = false
## Whether the front left wheel has brakes.
@export var FL_torque_brake = false
## Whether the rear right wheel has brakes.
@export var RR_torque_brake = true
## Whether the rear left wheel has brakes.
@export var RL_torque_brake = true
## Engine torque curve. The x axis is normalized RPM (0 to 1, where 1 equals
## [member max_rpm]) and the y axis is the fraction of [member max_torque]
## (0 to 1).
@export var torque_curve: Curve

@export_subgroup("Limited Slip Differential")

## Type of differential used on each driven axle.
enum DiffType {
	## Always splits the axle torque evenly between the two wheels.
	OPEN,
	## Torsen-style limited slip. Biases torque toward the wheel with more grip
	## using [member TBR].
	TORSEN_LSD,
	## Clutch-pack limited slip. Locks the wheels together using
	## [member minimum_clutch_lsd_force] and [member clutch_lsd_ramp_factor].
	CLUTCH_LSD,
	## Electronically controlled limited slip. Not implemented yet.
	ELECTRONIC_LSD
}

## The differential type used on the driven axle(s).
@export var differential: DiffType = DiffType.OPEN

## Preload of the clutch-type LSD, in N·m. This lock torque is always present,
## even with little axle torque. Only used by [constant DiffType.CLUTCH_LSD].
@export var minimum_clutch_lsd_force = 100.0
## How much extra lock torque the clutch-type LSD gains per unit of axle torque.
## Higher values lock harder under power. Only used by
## [constant DiffType.CLUTCH_LSD].
@export var clutch_lsd_ramp_factor = 1.0
## Share of the drive torque sent to the front axle when both axles are driven
## (all-wheel drive). The rear axle gets the remainder, so 0.5 is an even split.
@export var center_diff_split = 0.5
## Torque bias ratio of the Torsen LSD. A value of 2.0 means the wheel with more
## grip can receive up to twice the torque of the other wheel. Only used by
## [constant DiffType.TORSEN_LSD].
@export var TBR = 2.0
## Minimum difference in slip ratio between the two wheels of an axle before the
## differential starts biasing torque. Smaller differences are split evenly.
@export var SLIP_THRESHOLD = 0.01

@export_group("Transmission")

## Placeholder marking the "Transmission" section. Does nothing.
func transmisson():
	pass

## Gear ratios indexed by gear number: index 0 is reverse (negative), index 1 is
## neutral (0.0), and indices 2 and up are the forward gears (first gear is at
## index 2).
@export var gear_ratio = [-3.758, 0.0, 3.136, 1.888, 1.330, 1.000, 0.814]
## Fraction of torque that survives the drivetrain (1.0 is lossless, 0.9 loses
## 10 percent).
@export var drive_train_efficeny = 1.0
## Final drive ratio, applied after the gearbox.
@export var final_drive = 4.3
## Maximum torque the clutch can transmit when fully engaged, in N·m.
@export var max_clutch_torque = 262.5

## How gears are changed.
enum TransmissionMode {
	## Clutch must be pressed (over 95 percent) to change gear.
	MANUAL,
	## Gears are changed with ShiftUp/ShiftDown without the clutch. An automatic
	## clutch opens during shifts and at low RPM so the car can pull away and stop
	## without the clutch pedal.
	CLUTCHLESS,
	## Fully automatic. ShiftUp/ShiftDown only select R, N and D; in D the gearbox
	## picks the forward gear itself. Uses the automatic clutch.
	AUTOMATIC
}

## The gear change mode.
@export var transmission_mode: TransmissionMode = TransmissionMode.MANUAL
## RPM at which the automatic clutch is fully engaged. Below it the clutch slips,
## down to fully open at the idle speed. Used in the clutchless and automatic
## modes.
@export var auto_clutch_engage_rpm = 2000.0
## Upshift RPM of the automatic gearbox at very light throttle.
@export var auto_upshift_rpm_min = 2500.0
## Upshift RPM of the automatic gearbox at full throttle.
@export var auto_upshift_rpm_max = 6400.0
## The automatic gearbox shifts down when the RPM in the next lower gear would
## be below this fraction of the current upshift RPM. Lower values hold gears
## longer; keep it below 1.0 to avoid hunting.
@export var auto_downshift_factor = 0.8
## Minimum time between two automatic shifts, in seconds.
@export var auto_shift_cooldown = 0.8

@export_group("Wheel")

## Static camber angle of each wheel, in degrees. Negative means the top of the
## wheel leans inward.
@export var camber_angles = [-1.2, -1.2, -1.7, -1.7]
## Camber change per unit of suspension travel for each wheel. Typically
## negative so that the wheel gains negative camber as it compresses.
@export var camber_gain = [-18.0, -18.0, -25.0, -25.0]
## Radius of the wheel including the tire, in meters.
@export var wheel_radius = 0.2885
## Mass of one wheel, in kg.
@export var wheel_mass = 13.4
## Rolling resistance coefficient (dimensionless).
@export var rolling_resistance_coeff = 0.0105
## Rotational inertia of one wheel, in kg·m².
@export var wheel_inertia: float = 0.8

## Placeholder marking the "Wheel" section. Does nothing.
func wheel():
	pass

## Available tire force models.
enum TireModelType {
	## A brush tire model. Configured under "Brush Model" below.
	Brush_Model
}

## The tire model used to compute tire forces.
@export var TireModel: TireModelType = TireModelType.Brush_Model
# Brush Model

@export_subgroup("Brush Model")

## Placeholder marking the "Brush Model" section. Does nothing.
func brush_model():
	pass

## Longitudinal slip stiffness of the tire, in N per unit slip ratio. Controls
## how quickly the tire builds force under braking and acceleration.
@export var brush_Csx: float = 65000.0  
## Lateral slip stiffness of the tire, in N per radian of slip angle. Controls
## how quickly the tire builds cornering force.
@export var brush_Csy: float = 50000.0  
## Friction coefficient between tire and road. Limits the maximum tire force.
@export var brush_mu: float = 1.25
## Share of [member brush_mu] left while the tire slides fast (sliding
## friction). Real tires lose grip once they slide: about 0.7 to 0.8. 1.0 turns
## the effect off.
@export var brush_mu_slide: float = 0.75
## Sliding speed of the contact patch, in m/s, that sets how quickly the grip
## falls from [member brush_mu] to the sliding friction. At this speed about 63
## percent of the drop is reached.
@export var brush_slide_speed: float = 3.0
## Surface used where the ground has no surface of its own (see
## [ShiftSurface]). Empty means asphalt.
@export var default_surface: ShiftSurface


@export_group("Effects")

## Leaves tire marks on the ground while a tire slides. Colors and whether a
## surface gets marks or smoke at all are set per surface ([ShiftSurface]).
@export var tire_marks = true
## Emits tire smoke while a tire slides.
@export var tire_smoke = true
## Sliding speed of the tire contact patch, in m/s, at which marks and smoke
## start. The sliding speed combines wheel spin, locking and sideways sliding.
@export var effect_slip_start = 3.0
## Sliding speed, in m/s, at which marks and smoke reach full strength.
@export var effect_slip_full = 10.0
## Width of one tire mark, in meters.
@export var tire_mark_width = 0.2
## Length of one tire mark segment, in meters. Shorter segments follow curves
## more closely but use up [member tire_mark_max_segments] faster.
@export var tire_mark_segment_length = 0.15
## Number of tire mark segments a car keeps. When the limit is reached, the
## oldest segments are reused.
@export var tire_mark_max_segments = 4000
## Number of smoke puffs one wheel can have at the same time.
@export var tire_smoke_amount = 96
## Lifetime of one smoke puff, in seconds.
@export var tire_smoke_lifetime = 2.5


@export_group("Debug")

## Enables the debug visuals when true.
@export var DEBUG = true
## Color of the suspension force arrows.
@export var Suspension_Arrow_Color: Color = Color.GREEN
## Color of the longitudinal (forward and back) tire force arrows. (The
## spelling of the name is kept as in the source.)
@export var Longtiude_Arrow_Color: Color = Color.RED
## Color of the lateral (sideways) tire force arrows.
@export var Lateral_Arrow_Color: Color = Color.BLUE
## Offset applied to the debug arrows relative to their wheel, so they do not
## overlap the car.
@export var Position_Offset: Vector3 = Vector3(2, 0, 0)
## Shows the numeric force magnitude next to the debug arrows when true. (The
## spelling of the name is kept as in the source.)
@export var Display_Force_Magntiude = false
