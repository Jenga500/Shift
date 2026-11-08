## A ground surface type (asphalt, grass, gravel, ...) and how tires behave on it.
##
## The car looks up the surface under each wheel every physics frame (see
## [code]car/surface_lookup.gd[/code]):[br]
## 1. If the ground collider has the metadata [code]shift_surface[/code] with a
## [ShiftSurface], that one is used. Set it in the inspector of a
## [StaticBody3D] (or any collision object) under [i]Metadata[/i].[br]
## 2. Otherwise every node in the group [code]shift_surface_providers[/code] is
## asked, for example a [ShiftTerrain3DSurfaces] node for a Terrain3D terrain.[br]
## 3. Otherwise [code]default_surface[/code] of the car's [CarValues] is used, or
## asphalt (the defaults of this resource) if that is empty.
##
## Presets are in [code]presets/surfaces/[/code].
class_name ShiftSurface
extends Resource

## Name shown in the HUD and handy for your own scripts (for example
## [code]car.wheeldata.surface[i].surface_name[/code]).
@export var surface_name := "Asphalt"
## Grip multiplier for the tire friction ([code]brush_mu[/code] of the car).
## 1.0 = dry asphalt, about 0.7 gravel, 0.5 to 0.6 grass, 0.3 snow.
@export var grip := 1.0
## Rolling resistance multiplier ([code]rolling_resistance_coeff[/code] of the
## car). Soft ground slows the car down: about 3 gravel, 5 grass, 10 sand.
@export var rolling_resistance := 1.0
## Leaves tire marks on this surface.
@export var marks := true
## Color of the tire marks at full strength (alpha is the opacity).
@export var mark_color := Color(0.03, 0.03, 0.03, 0.85)
## Emits smoke (on asphalt) or dust (on loose ground) on this surface.
@export var smoke := true
## Color of the smoke or dust (alpha is the opacity of a single puff).
@export var smoke_color := Color(0.85, 0.85, 0.85, 0.3)
