extends CharacterBody2D


@export var push_force: float = 80
@export var MAX_VELOCITY: float = 3000.0
@export var DEAD_RADIUS: float = 3.0
@export var controllable: bool = true
@export var TARGET_SMOOTH: float = 0.25

# Auto-scaling for mobile screen
@export var auto_scale: bool = true
@export var reference_size: Vector2 = Vector2(402.0, 874.0)

# Table / sides (VERTICAL layout: top vs bottom)
@export var center_y: float = 0.0
@export var center_marker: Marker2D
@export var is_top_side: bool = true
@export var goal_x: float = -500.0
@export var opp_goal_x: float = 500.0
@export var ai_goal: Node2D
@export var player_goal: Node2D

# Board bounds (world coordinates) used for wall-aware steering
@export var board_rect: Rect2 = Rect2(201, 431, 384, 768)
@export var wall_buffer: float = 18.0

# AI settings
enum Difficulty { EASY, MEDIUM, HARD }
@export var difficulty: Difficulty = Difficulty.MEDIUM
@export var puck: RigidBody2D

# Engagement tuning
@export var engage_radius: float = 220.0
@export var defend_line_offset: float = 120.0
@export var strike_radius: float = 80.0
@export var behind_dist: float = 40.0
@export var hit_cooldown: float = 0.25

# Difficulty modifiers
var _ai_reaction: float = 0.08
var _ai_lead: float = 0.12
var _ai_noise: float = 0.0
var _ai_speed_scale: float = 0.8

# Runtime
var target_pos: Vector2 = Vector2.ZERO
var active_touch: int = -1
var touch_offset: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0

# Hysteresis
var _engage_radius_out: float = 180.0

enum AIState { DEFEND, CHASE, STRIKE, RETREAT }
var _state: AIState = AIState.DEFEND

func _ready() -> void:
	_set_ai_params()
	if auto_scale:
		_apply_screen_scaling()
	_engage_radius_out = max(50.0, engage_radius * 0.8)

# ---------------- Player input ----------------
func _unhandled_input(event: InputEvent) -> void:
	if controllable == false:
		return

	if event is InputEventScreenTouch:
		var te: InputEventScreenTouch = event
		if te.pressed and active_touch == -1:
			active_touch = te.index
			touch_offset = global_position - te.position
			target_pos = te.position + touch_offset
		elif not te.pressed and te.index == active_touch:
			active_touch = -1
			velocity = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == active_touch:
		var desired: Vector2 = event.position + touch_offset
		target_pos = target_pos.lerp(desired, TARGET_SMOOTH)

# ---------------- Helpers ----------------
func _center_line_y() -> float:
	var cy: float = center_y
	if center_marker:
		cy = center_marker.global_position.y
	return cy

func _ai_goal_pos() -> Vector2:
	var g: Vector2 = Vector2(goal_x, 0.0)
	if ai_goal:
		g = ai_goal.global_position
	return g

func _opp_goal_pos() -> Vector2:
	var g: Vector2 = Vector2(opp_goal_x, 0.0)
	if player_goal:
		g = player_goal.global_position
	return g

func _puck_near_wall(p: Vector2) -> bool:
	var grown: Rect2 = board_rect.grow(-wall_buffer)
	return not grown.has_point(p)

func _nearest_wall_normal(p: Vector2) -> Vector2:
	var left: float = board_rect.position.x
	var right: float = board_rect.position.x + board_rect.size.x
	var top: float = board_rect.position.y
	var bottom: float = board_rect.position.y + board_rect.size.y

	var dl: float = abs(p.x - left)
	var dr: float = abs(right - p.x)
	var dt: float = abs(p.y - top)
	var db: float = abs(bottom - p.y)

	var mn: float = min(min(dl, dr), min(dt, db))
	if mn == dl:
		return Vector2(-1, 0)
	if mn == dr:
		return Vector2(1, 0)
	if mn == dt:
		return Vector2(0, -1)
	return Vector2(0, 1)

func _apply_screen_scaling() -> void:
	var sz: Vector2 = get_viewport().get_visible_rect().size
	var ref_short: float = min(reference_size.x, reference_size.y)
	var cur_short: float = min(sz.x, sz.y)
	if ref_short <= 0.0:
		return

	var k: float = cur_short / ref_short
	DEAD_RADIUS = max(2.0, DEAD_RADIUS * k)
	engage_radius = max(100.0, engage_radius * k)
	defend_line_offset = max(60.0, defend_line_offset * k)
	strike_radius = max(40.0, strike_radius * k)
	behind_dist = max(20.0, behind_dist * k)
	MAX_VELOCITY = clamp(MAX_VELOCITY * k, 800.0, 3200.0)

func _set_ai_params() -> void:
	match difficulty:
		Difficulty.EASY:
			_ai_reaction = 0.12
			_ai_lead = 0.05
			_ai_noise = 12.0
			_ai_speed_scale = 0.6
		Difficulty.MEDIUM:
			_ai_reaction = 0.08
			_ai_lead = 0.12
			_ai_noise = 6.0
			_ai_speed_scale = 0.8
		Difficulty.HARD:
			_ai_reaction = 0.04
			_ai_lead = 0.20
			_ai_noise = 0.0
			_ai_speed_scale = 1.0

# ---------------- Core update ----------------
func _physics_process(delta: float) -> void:
	if controllable:
		_update_target_player()
	else:
		_update_target_ai(delta)

	var cy: float = _center_line_y()

	# Compute desired velocity
	var speed_scale: float = 1.0
	if controllable == false:
		speed_scale = _ai_speed_scale
	var desired: Vector2 = _compute_desired_velocity(global_position, target_pos, MAX_VELOCITY * speed_scale, delta)

	# Center-line clamp: ONLY for AI
	if controllable == false:
		var next_y: float = global_position.y + desired.y * delta
		if is_top_side and next_y > cy - 1.0:
			desired.y = (cy - 1.0 - global_position.y) / delta
			if desired.y < 0.0:
				desired.y = 0.0
		if not is_top_side and next_y < cy + 1.0:
			desired.y = (cy + 1.0 - global_position.y) / delta
			if desired.y > 0.0:
				desired.y = 0.0

		# Wall-aware steering: ONLY for AI
		if puck and is_instance_valid(puck):
			var pp: Vector2 = puck.global_position
			if _puck_near_wall(pp):
				var n: Vector2 = _nearest_wall_normal(pp)
				var into: float = desired.dot(n)
				if into > 0.0:
					desired = desired - n * into

	velocity = desired
	move_and_slide()
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody2D:
			c.get_collider().apply_central_impulse(-c.get_normal() * push_force)

# ---------------- Target selection ----------------
func _update_target_player() -> void:
	# If not touching, hold position
	if active_touch == -1:
		target_pos = global_position
		return
	# Player target is already smoothed in input; do not clamp to center for player.

func _update_target_ai(delta: float) -> void:
	if not puck or not is_instance_valid(puck):
		target_pos = global_position
		return

	_cooldown = max(0.0, _cooldown - delta)

	var pos: Vector2 = global_position
	var pp: Vector2 = puck.global_position
	var pv: Vector2 = puck.linear_velocity
	var cy: float = _center_line_y()

	var on_my_half: bool = false
	if is_top_side:
		on_my_half = pp.y <= cy
	else:
		on_my_half = pp.y >= cy

	var dist_to_puck: float = pos.distance_to(pp)
	var close_enough: bool = dist_to_puck <= engage_radius
	var far_enough: bool = dist_to_puck >= _engage_radius_out

	match _state:
		AIState.DEFEND:
			if on_my_half or close_enough:
				_state = AIState.CHASE
		AIState.CHASE:
			if pos.distance_to(pp) <= strike_radius and _aligned_for_shot(pos, pp):
				_state = AIState.STRIKE
			else:
				if not on_my_half and far_enough:
					_state = AIState.DEFEND
		AIState.STRIKE:
			_state = AIState.RETREAT
			_cooldown = hit_cooldown
		AIState.RETREAT:
			if _cooldown <= 0.0:
				if on_my_half or close_enough:
					_state = AIState.CHASE
				else:
					_state = AIState.DEFEND

	var tgt: Vector2
	match _state:
		AIState.DEFEND:
			tgt = _defend_spot_vertical(pp, cy)
		AIState.CHASE:
			tgt = _intercept_point_vertical(pp, pv, cy, dist_to_puck)
		AIState.STRIKE:
			tgt = _strike_point_vertical(pp, cy)
		AIState.RETREAT:
			tgt = _defend_spot_vertical(pp, cy)
		_:
			tgt = pos

	# Clamp AI target to its half before smoothing, then smooth
	if is_top_side and tgt.y > cy:
		tgt.y = cy - 2.0
	if not is_top_side and tgt.y < cy:
		tgt.y = cy + 2.0

	var react_alpha: float = 1.0
	if _ai_reaction > 0.0:
		react_alpha = clamp(delta / _ai_reaction, 0.0, 1.0)
	target_pos = target_pos.lerp(tgt, react_alpha)

# ---------------- Steering helpers ----------------
func _compute_desired_velocity(pos: Vector2, tgt: Vector2, max_speed: float, dt: float) -> Vector2:
	var to_target: Vector2 = tgt - pos
	var dist: float = to_target.length()
	if dist <= DEAD_RADIUS:
		return Vector2.ZERO

	var safe_dt: float = max(dt, 0.000001)
	var max_step_speed: float = min(max_speed, dist / safe_dt)
	return to_target * (max_step_speed / dist)

# Where to stand while defending (vertical)
func _defend_spot_vertical(pp: Vector2, center_line_y: float) -> Vector2:
	var ai_goal_pos: Vector2 = _ai_goal_pos()
	var sign: float = 1.0
	if not is_top_side:
		sign = -1.0

	var y_line: float = ai_goal_pos.y + sign * defend_line_offset
	if is_top_side:
		y_line = min(y_line, center_line_y - 2.0)
	else:
		y_line = max(y_line, center_line_y + 2.0)

	return Vector2(pp.x, y_line)

# Predict puck position a short time ahead (vertical clamp)
func _intercept_point_vertical(pp: Vector2, pv: Vector2, center_line_y: float, dist_to_puck: float) -> Vector2:
	var lead: float = _ai_lead
	lead += clamp(dist_to_puck / 1200.0, 0.0, 0.25)
	var predicted: Vector2 = pp + pv * lead

	if _ai_noise > 0.0 and dist_to_puck > strike_radius * 1.5:
		var jitter: Vector2 = Vector2(randf() - 0.5, randf() - 0.5).normalized() * randf() * _ai_noise
		predicted += jitter

	if is_top_side and predicted.y > center_line_y:
		predicted.y = center_line_y - 2.0
	if not is_top_side and predicted.y < center_line_y:
		predicted.y = center_line_y + 2.0

	if _puck_near_wall(predicted):
		var n: Vector2 = _nearest_wall_normal(predicted)
		predicted += n * 6.0

	return predicted

# Get behind the puck, then drive through it toward the opponent goal (vertical clamp)
func _strike_point_vertical(pp: Vector2, center_line_y: float) -> Vector2:
	var opp_goal: Vector2 = _opp_goal_pos()
	var dir: Vector2 = (opp_goal - pp).normalized()
	var behind: Vector2 = pp - dir * behind_dist

	if is_top_side and behind.y > center_line_y:
		behind.y = center_line_y - 2.0
	if not is_top_side and behind.y < center_line_y:
		behind.y = center_line_y + 2.0

	if _puck_near_wall(behind):
		var n: Vector2 = _nearest_wall_normal(behind)
		behind += n * 6.0

	return behind

# Are we roughly on the shooting line behind the puck?
func _aligned_for_shot(pos: Vector2, pp: Vector2) -> bool:
	var opp_goal: Vector2 = _opp_goal_pos()
	var shot_dir: Vector2 = (opp_goal - pp).normalized()
	var our_dir: Vector2 = (pp - pos).normalized()
	return our_dir.dot(shot_dir) > 0.6
