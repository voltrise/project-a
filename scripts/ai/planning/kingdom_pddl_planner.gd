class_name KingdomPDDLPlanner
extends RefCounted

## Automated Planning Engine for Kingdom Defense
## Plan sequence for King mobilizing troops: King moves -> commands troop -> troop deploys to post
## Supports multiple troops deploying to the same post!

class PDDLAction:
	var name: String
	var parameters: Array = []
	var preconditions: Dictionary = {}
	var add_effects: Dictionary = {}
	var del_effects: Dictionary = {}
	var cost: float = 1.0

	func _init(p_name: String, p_params: Array, p_pre: Dictionary, p_add: Dictionary, p_del: Dictionary, p_cost: float = 1.0):
		name = p_name
		parameters = p_params
		preconditions = p_pre.duplicate(true)
		add_effects = p_add.duplicate(true)
		del_effects = p_del.duplicate(true)
		cost = p_cost

	func is_applicable(state: Dictionary) -> bool:
		for k in preconditions.keys():
			if not state.has(k) or state[k] != preconditions[k]:
				return false
		return true

	func apply(state: Dictionary) -> Dictionary:
		var next_state = state.duplicate(true)
		for k in del_effects.keys():
			next_state.erase(k)
		for k in add_effects.keys():
			next_state[k] = add_effects[k]
		return next_state

	func to_action_string() -> String:
		if parameters.is_empty():
			return name + "()"
		return "%s(%s)" % [name, ", ".join(parameters)]

class PlanNode:
	var state: Dictionary
	var parent_node: PlanNode = null
	var action: PDDLAction = null
	var g_cost: float = 0.0

	func _init(p_state: Dictionary, p_parent: PlanNode = null, p_action: PDDLAction = null, p_cost: float = 0.0):
		state = p_state.duplicate(true)
		parent_node = p_parent
		action = p_action
		g_cost = p_cost

class PlanningResult:
	var is_success: bool = false
	var plan_actions: Array = []
	var visited_states_count: int = 0
	var execution_time_ms: float = 0.0
	var initial_state: Dictionary = {}
	var goal_state: Dictionary = {}

static func state_to_key(state: Dictionary) -> String:
	var keys = state.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%s" % [k, str(state[k])])
	return ";".join(parts)

static func is_goal_satisfied(state: Dictionary, goal: Dictionary) -> bool:
	for k in goal.keys():
		if not state.has(k) or state[k] != goal[k]:
			return false
	return true

## Build domain actions for King & Troop Mobilization
static func get_kingdom_domain_actions(locations: Array[String], troops: Array[String], posts: Array[String]) -> Array:
	var actions: Array = []

	# 1. King Move(from, to)
	for loc_a in locations:
		for loc_b in locations:
			if loc_a != loc_b:
				actions.append(PDDLAction.new(
					"KingMove",
					[loc_a, loc_b],
					{ "KingAt": loc_a },
					{ "KingAt": loc_b },
					{ "KingAt": loc_a },
					1.0
				))

	# 2. King MobilizeTroop(Troop, TroopCamp)
	for tr in troops:
		var camp_loc = "Marker_" + tr + "s" # e.g. Marker_Archers
		actions.append(PDDLAction.new(
			"MobilizeTroop",
			[tr, camp_loc],
			{ "KingAt": camp_loc, tr + "Mobilized": false, tr + "Deployed": false },
			{ tr + "Mobilized": true },
			{},
			1.0
		))

	# 3. DeployTroopToPost(Troop, Post)
	# NOTE: Multiple troops can deploy to the same post!
	for tr in troops:
		for post in posts: # "MainGate", "Cave", "Docks"
			actions.append(PDDLAction.new(
				"DeployTroop",
				[tr, post],
				{ tr + "Mobilized": true, tr + "Deployed": false },
				{ tr + "Deployed": true, tr + "_At_" + post: true },
				{ tr + "Mobilized": true },
				1.5
			))

	# 4. Emergency RingBell
	actions.append(PDDLAction.new(
		"RingAlarmBell",
		["Marker_Bell"],
		{ "KingAt": "Marker_Bell", "BellRang": false },
		{ "BellRang": true },
		{},
		1.0
	))

	return actions

## Forward Search Planner
static func plan(initial_state: Dictionary, goal_state: Dictionary, actions: Array) -> PlanningResult:
	var start_time = Time.get_ticks_usec()
	var result = PlanningResult.new()
	result.initial_state = initial_state.duplicate(true)
	result.goal_state = goal_state.duplicate(true)

	if is_goal_satisfied(initial_state, goal_state):
		result.is_success = true
		result.execution_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
		return result

	var queue: Array = []
	var visited: Dictionary = {}

	var root = PlanNode.new(initial_state, null, null, 0.0)
	queue.append(root)
	visited[state_to_key(initial_state)] = true

	var max_nodes = 3000
	while not queue.is_empty() and max_nodes > 0:
		max_nodes -= 1
		result.visited_states_count += 1
		var current = queue.pop_front()

		if is_goal_satisfied(current.state, goal_state):
			result.is_success = true
			var curr = current
			while curr.parent_node != null:
				result.plan_actions.push_front(curr.action)
				curr = curr.parent_node
			result.execution_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
			return result

		for act in actions:
			if act.is_applicable(current.state):
				var next_st = act.apply(current.state)
				var key = state_to_key(next_st)
				if not visited.has(key):
					visited[key] = true
					var next_node = PlanNode.new(next_st, current, act, current.g_cost + act.cost)
					queue.append(next_node)

	result.is_success = false
	result.execution_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
	return result
