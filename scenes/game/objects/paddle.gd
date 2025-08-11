extends RigidBody2D

@export var MAX_VELOCITY := 3000.0
@export var DEAD_RADIUS := 3.0
@export var controllable := true
@export var TARGET_SMOOTH := 0.25

# Auto-scaling for mobile screen
@export var auto_scale := true
@export var reference_size := Vector2(402.0, 874.0)
@export var table: Sprite2D

# Table / sides (VERTICAL layout: top vs bottom)
@export var center_y := 0.0                     # fallback if marker not set
@export var center_marker: Marker2D
@export var is_top_side := true                 # true = this paddle owns the TOP half
@export var goal_x := -500.0                    # fallback if ai_goal not set (x only used as fallback)
@export var opp_goal_x := 500.0                 # fallback if player_goal not set
@export var ai_goal: Node2D                     # AI-side goal node (near top)
@export var player_goal: Node2D                 # Player-side goal node (near bottom)

# Board bounds (world coordinates) - now computed automatically
@export var wall_buffer := 18.0                 # puck radius + small margin
var board_rect := Rect2(0, 0, 0, 0)  # will be computed in _ready()

# AI settings
enum Difficulty { EASY, MEDIUM, HARD }
@export var difficulty: Difficulty = Difficulty.MEDIUM
@export var puck: RigidBody2D

# Engagement tuning
@export var engage_radius := 220.0
@export var defend_line_offset := 120.0         # how far from our goal to hold the line (toward center)
@export var strike_radius := 80.0
@export var behind_dist := 40.0
@export var hit_cooldown := 0.25

# Difficulty modifiers
var _ai_reaction := 0.08
var _ai_lead := 0.12
var _ai_noise := 0.0
var _ai_speed_scale := 0.8

# Runtime
var target_pos := Vector2.ZERO
var active_touch := -1
var touch_offset := Vector2.ZERO
var _cooldown := 0.0

# Hysteresis to stop state flapping
var _engage_radius_out := 180.0

enum AIState { DEFEND, CHASE, STRIKE, RETREAT }
var _state: AIState = AIState.DEFEND

func _ready():
	custom_integrator = true
	# CCD helps prevent tunneling in fast contacts
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	randomize()
	_set_ai_params()
	if auto_scale:
		_apply_screen_scaling()
	
	# Compute board_rect based on table if available
	if table:
		board_rect = _compute_board_rect_from_table()
	
	_engage_radius_out = max(50.0, engage_radius * 0.8)

func _apply_screen_scaling():
	var vp = get_viewport()
	var sz = vp.get_visible_rect().size
	var ref_short = min(reference_size.x, reference_size.y)
	var cur_short = min(sz.x, sz.y)
	if ref_short <= 0.0:
		return
	var k = cur_short / ref_short

	DEAD_RADIUS = max(2.0, DEAD_RADIUS * k)
	engage_radius = max(100.0, engage_radius * k)
	defend_line_offset = max(60.0, defend_line_offset * k)
	strike_radius = max(40.0, strike_radius * k)
	behind_dist = max(20.0, behind_dist * k)
	MAX_VELOCITY = clamp(MAX_VELOCITY * k, 800.0, 3200.0)

func _set_ai_params():
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

# ---------------- Player control ----------------
func _unhandled_input(event):
	if controllable == false:
		return

	if event is InputEventScreenTouch:
		if event.pressed and active_touch == -1:
			active_touch = event.index
			touch_offset = global_position - event.position
			target_pos = event.position + touch_offset
		elif !event.pressed and event.index == active_touch:
			active_touch = -1
			linear_velocity = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == active_touch:
		var desired = event.position + touch_offset
		target_pos = target_pos.lerp(desired, TARGET_SMOOTH)

# ---------------- Helpers ----------------
func _center_line_y() -> float:
	var cy = center_y
	if center_marker:
		cy = center_marker.global_position.y
	return cy

func _ai_goal_pos() -> Vector2:
	var g = Vector2(goal_x, 0.0)
	if ai_goal:
		g = ai_goal.global_position
	return g

func _opp_goal_pos() -> Vector2:
	var g = Vector2(opp_goal_x, 0.0)
	if player_goal:
		g = player_goal.global_position
	return g

func _puck_near_wall(p: Vector2) -> bool:
	var grown = board_rect.grow(-wall_buffer)
	return !grown.has_point(p)

func _nearest_wall_normal(p: Vector2) -> Vector2:
	var left = board_rect.position.x
	var right = board_rect.position.x + board_rect.size.x
	var top = board_rect.position.y
	var bottom = board_rect.position.y + board_rect.size.y

	var dl = abs(p.x - left)
	var dr = abs(right - p.x)
	var dt = abs(p.y - top)
	var db = abs(bottom - p.y)

	var mn = min(min(dl, dr), min(dt, db))
	if mn == dl:
		return Vector2(-1, 0)
	if mn == dr:
		return Vector2(1, 0)
	if mn == dt:
		return Vector2(0, -1)
	return Vector2(0, 1)

# Compute board rect in world space from the table sprite
func _compute_board_rect_from_table() -> Rect2:
	var r: Rect2 = table.get_rect()
	var xf: Transform2D = table.global_transform
	var p0: Vector2 = xf * r.position
	var p1: Vector2 = xf * (r.position + Vector2(r.size.x, 0.0))
	var p2: Vector2 = xf * (r.position + Vector2(0.0, r.size.y))
	var p3: Vector2 = xf * (r.position + r.size)
	var minx = min(min(p0.x, p1.x), min(p2.x, p3.x))
	var maxx = max(max(p0.x, p1.x), max(p2.x, p3.x))
	var miny = min(min(p0.y, p1.y), min(p2.y, p3.y))
	var maxy = max(max(p0.y, p1.y), max(p2.y, p3.y))
	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))

# Clamp opponent goal to a safe in-bounds aim point
func _safe_goal_pos() -> Vector2:
	var g = _opp_goal_pos()
	var left = board_rect.position.x + wall_buffer * 2.0
	var right = board_rect.position.x + board_rect.size.x - wall_buffer * 2.0
	var top = board_rect.position.y + wall_buffer * 2.0
	var bottom = board_rect.position.y + board_rect.size.y - wall_buffer * 2.0
	g.x = clamp(g.x, left, right)
	g.y = clamp(g.y, top, bottom)
	return g

# ---------------- AI brain (TOP/BOTTOM) ----------------
func _physics_process(delta):
	if controllable:
		return
	if !puck or !is_instance_valid(puck):
		return

	_cooldown = max(0.0, _cooldown - delta)

	var pos = global_position
	var pp = puck.global_position
	var pv = puck.linear_velocity
	var center_line_y = _center_line_y()

	var on_my_half = false
	if is_top_side:
		on_my_half = pp.y <= center_line_y
	else:
		on_my_half = pp.y >= center_line_y

	var dist_to_puck = pos.distance_to(pp)
	var close_enough = dist_to_puck <= engage_radius
	var far_enough = dist_to_puck >= _engage_radius_out

	match _state:
		AIState.DEFEND:
			if on_my_half or close_enough:
				_state = AIState.CHASE

		AIState.CHASE:
			if pos.distance_to(pp) <= strike_radius and _aligned_for_shot(pos, pp):
				_state = AIState.STRIKE
			else:
				if !on_my_half and far_enough:
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
			tgt = _defend_spot_vertical(pp, center_line_y)
		AIState.CHASE:
			tgt = _intercept_point_vertical(pp, pv, center_line_y, dist_to_puck)
		AIState.STRIKE:
			tgt = _strike_point_vertical(pp, center_line_y)
		AIState.RETREAT:
			tgt = _defend_spot_vertical(pp, center_line_y)
		_:
			tgt = pos

	# Clamp target to our half (Y) BEFORE smoothing
	if is_top_side and tgt.y > center_line_y:
		tgt.y = center_line_y - 2.0
	if !is_top_side and tgt.y < center_line_y:
		tgt.y = center_line_y + 2.0

	# Smooth at a rate tied to reaction time
	var react_alpha = 1.0
	if _ai_reaction > 0.0:
		react_alpha = clamp(delta / _ai_reaction, 0.0, 1.0)
	target_pos = target_pos.lerp(tgt, react_alpha)

# Where to stand while defending (vertical)
func _defend_spot_vertical(pp: Vector2, center_line_y: float) -> Vector2:
	var ai_goal_pos = _ai_goal_pos()
	var _sign = 1.0
	if !is_top_side:
		_sign = -1.0

	var y_line = ai_goal_pos.y + _sign * defend_line_offset

	if is_top_side:
		y_line = min(y_line, center_line_y - 2.0)
	else:
		y_line = max(y_line, center_line_y + 2.0)

	return Vector2(pp.x, y_line)

# Predict puck position a short time ahead (vertical clamp)
func _intercept_point_vertical(pp: Vector2, pv: Vector2, center_line_y: float, dist_to_puck: float) -> Vector2:
	var lead = _ai_lead
	var dist = dist_to_puck
	lead += clamp(dist / 1200.0, 0.0, 0.25)
	var predicted = pp + pv * lead

	# optional wobble, but keep it off near the puck to avoid jitter
	if _ai_noise > 0.0 and dist > strike_radius * 1.5:
		var jitter = Vector2(randf() - 0.5, randf() - 0.5).normalized() * randf() * _ai_noise
		predicted += jitter

	# clamp to our half
	if is_top_side and predicted.y > center_line_y:
		predicted.y = center_line_y - 2.0
	if !is_top_side and predicted.y < center_line_y:
		predicted.y = center_line_y + 2.0

	# Nudge off the wall if puck is near rail to avoid pinning
	if _puck_near_wall(predicted):
		var n = _nearest_wall_normal(predicted)
		predicted += n * 6.0

	return predicted

# Get behind the puck, then drive through it toward the opponent goal (vertical clamp)
func _strike_point_vertical(pp: Vector2, center_line_y: float) -> Vector2:
	var opp_goal = _safe_goal_pos()
	var dir = (opp_goal - pp).normalized()
	var behind = pp - dir * behind_dist

	if is_top_side and behind.y > center_line_y:
		behind.y = center_line_y - 2.0
	if !is_top_side and behind.y < center_line_y:
		behind.y = center_line_y + 2.0

	# Also nudge the staging point off the wall
	if _puck_near_wall(behind):
		var n = _nearest_wall_normal(behind)
		behind += n * 6.0

	return behind

# Are we roughly on the shooting line behind the puck?
func _aligned_for_shot(pos: Vector2, pp: Vector2) -> bool:
	var opp_goal = _safe_goal_pos()
	var shot_dir = (opp_goal - pp).normalized()
	var our_dir = (pp - pos).normalized()
	return our_dir.dot(shot_dir) > 0.6

# ---------------- Movement ----------------
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if controllable:
		if active_touch == -1:
			state.linear_velocity = Vector2.ZERO
			return
		_move_toward(state, target_pos, MAX_VELOCITY)
	else:
		if !puck or !is_instance_valid(puck):
			state.linear_velocity = Vector2.ZERO
			return
		_move_toward_with_vertical_boundary(state, target_pos, MAX_VELOCITY * _ai_speed_scale, _center_line_y(), is_top_side)

# Prevent crossing the horizontal center line and avoid pushing into walls near puck.
func _move_toward_with_vertical_boundary(state: PhysicsDirectBodyState2D, tgt: Vector2, max_speed: float, center_line_y: float, top_side: bool) -> void:
	# Pre-clamp target to our half
	if top_side and tgt.y > center_line_y:
		tgt.y = center_line_y - 2.0
	if !top_side and tgt.y < center_line_y:
		tgt.y = center_line_y + 2.0

	var pos = state.transform.origin
	var to_target = tgt - pos
	var dist = to_target.length()

	if dist <= DEAD_RADIUS:
		state.linear_velocity = Vector2.ZERO
		return

	var max_step_speed = min(max_speed, dist / state.step)
	var desired = to_target * (max_step_speed / dist)

	# Prevent crossing the horizontal center in this step
	var next_y = pos.y + desired.y * state.step
	if top_side and next_y > center_line_y - 1.0:
		desired.y = (center_line_y - 1.0 - pos.y) / state.step
		if desired.y < 0.0:
			desired.y = 0.0
	if !top_side and next_y < center_line_y + 1.0:
		desired.y = (center_line_y + 1.0 - pos.y) / state.step
		if desired.y > 0.0:
			desired.y = 0.0

	# Wall-aware steering: if puck is near rail and we're pushing into the wall, remove that component
	if puck and is_instance_valid(puck):
		var pp = puck.global_position
		if _puck_near_wall(pp):
			var n = _nearest_wall_normal(pp) # outward normal of nearest wall
			var into = desired.dot(n)
			if into > 0.0:
				desired = desired - n * into

	state.linear_velocity = desired

# Free movement (used by the player)
func _move_toward(state: PhysicsDirectBodyState2D, tgt: Vector2, max_speed: float) -> void:
	var pos = state.transform.origin
	var to_target = tgt - pos
	var dist = to_target.length()
	if dist <= DEAD_RADIUS:
		state.linear_velocity = Vector2.ZERO
	else:
		var max_step_speed = min(max_speed, dist / state.step)
		state.linear_velocity = to_target * (max_step_speed / dist)
