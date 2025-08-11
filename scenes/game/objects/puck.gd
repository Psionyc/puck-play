extends RigidBody2D

@onready var line: Line2D = $Line2D

@export var MAX_PUCK_SPEED := 2000.0

@export var trail_color: Color = Color(0.2, 0.8, 1.0, 1.0)
@export var min_speed := 50.0         # start drawing above this
@export var lifetime := 0.35          # seconds each point lives
@export var min_dist := 6.0           # add a new point only if we moved this far
@export var max_points := 64          # hard cap
@export var width_min := 50
@export var width_max := 54

var _points: Array[Vector2] = []
var _ages: Array[float] = []
var _last_pos: Vector2

func _ready() -> void:
	# Make the line draw in world space (so it stays behind the moving puck)


	# Styling: round caps/joins, width curve, gradient (transparent tail -> solid head)

	line.width = width_min

	var grad := Gradient.new()
	grad.colors = [
		Color(trail_color.r, trail_color.g, trail_color.b, 0.0), # tail transparent
		trail_color                                                    # head solid
	]
	grad.offsets = [0.0, 1.0]
	line.gradient = grad

	# Additive blend for juicy glow
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = mat

	_last_pos = global_position

func _physics_process(delta: float) -> void:
	var speed := linear_velocity.length()

	# Update existing points' ages and cull old ones
	for i in range(_ages.size()):
		_ages[i] += delta
	# remove from front while too old
	while _ages.size() > 0 and _ages[0] > lifetime:
		_ages.remove_at(0)
		_points.remove_at(0)

	# Add a new point if moving fast enough and we moved far enough
	if speed >= min_speed:
		var moved := global_position.distance_to(_last_pos)
		if moved >= min_dist or _points.is_empty():
			_points.push_back(global_position)
			_ages.push_back(0.0)
			_last_pos = global_position

	# Hard cap
	while _points.size() > max_points:
		_points.remove_at(0)
		_ages.remove_at(0)

	# Width reacts to speed a bit
	var t = clamp(speed / (min_speed * 8.0), 0.0, 1.0)
	line.width = lerp(width_min, width_max, t)

	# Feed points to the Line2D (convert to the line's local since it's toplevel)
	var local_pts: Array[Vector2] = []
	local_pts.resize(_points.size())
	for i in _points.size():
		local_pts[i] = line.to_local(_points[i])
	line.points = local_pts

	# Hide when idle
	line.visible = _points.size() > 1


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Hard cap speed to keep solver stable
	var v = state.linear_velocity
	var s = v.length()
	if s > MAX_PUCK_SPEED:
		state.linear_velocity = v * (MAX_PUCK_SPEED / s)
