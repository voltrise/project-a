class_name KingdomUncertaintySolver
extends RefCounted

## Multi-Post Bayesian Threat Evaluation & Dynamic Maximum Expected Utility (MEU)
## Calculates P(Threat | Clue, Environment) and finds optimal assignment of [Archer, Warrior, Builder]
## Allows flexible multi-troop deployment (e.g., 2 troops at MainGate, 1 at Cave, 0 at Docks)

class ThreatBelief:
	var post_name: String
	var clue_name: String
	var prior: float
	var p_clue_given_threat: float
	var p_clue_given_no_threat: float
	var posterior: float
	var is_confirmed: bool
	var calculation_text: String

	func _init(p_post: String, p_clue: String, p_prior: float, p_c_t: float, p_c_nt: float, p_post_val: float, p_calc: String):
		post_name = p_post
		clue_name = p_clue
		prior = p_prior
		p_clue_given_threat = p_c_t
		p_clue_given_no_threat = p_c_nt
		posterior = p_post_val
		is_confirmed = posterior >= 0.50
		calculation_text = p_calc

class MultiPostAssessment:
	var environment: String
	var beliefs: Dictionary = {} # { "MainGate": ThreatBelief, ... }
	var priority_order: Array = [] # posts sorted by posterior desc
	var post_troop_assignments: Dictionary = { "MainGate": [], "Cave": [], "Docks": [] } # e.g. { "MainGate": ["Archer", "Builder"], "Cave": ["Warrior"], "Docks": [] }
	var troop_to_post: Dictionary = {} # { "Archer": "MainGate", "Builder": "MainGate", "Warrior": "Cave" }
	var utility_breakdown: Dictionary = {} # Detailed score logs

static func evaluate_post_belief(post_name: String, clue: String, env: String) -> ThreatBelief:
	var prior = 0.20
	var p_clue_threat = 0.10
	var p_clue_no_threat = 0.90

	match env:
		"Night": prior = 0.35
		"Foggy": prior = 0.28
		"Rain":  prior = 0.30
		"Clear": prior = 0.15

	match clue:
		"None":
			p_clue_threat = 0.05
			p_clue_no_threat = 0.95
		# Main Gate Clues
		"Distant Drums":
			p_clue_threat = 0.70
			p_clue_no_threat = 0.25
		"Campfire Smoke":
			p_clue_threat = 0.85
			p_clue_no_threat = 0.20
		"War Horn":
			p_clue_threat = 0.95
			p_clue_no_threat = 0.08
		# Cave Clues
		"Faint Hissing":
			p_clue_threat = 0.65
			p_clue_no_threat = 0.30
		"Earthquake Vibration":
			p_clue_threat = 0.88
			p_clue_no_threat = 0.15
		"Low Growl":
			p_clue_threat = 0.92
			p_clue_no_threat = 0.10
		# Docks Clues
		"Splashing Waves":
			p_clue_threat = 0.60
			p_clue_no_threat = 0.40
		"Fog Siren":
			p_clue_threat = 0.82
			p_clue_no_threat = 0.18
		"Water Shadow":
			p_clue_threat = 0.94
			p_clue_no_threat = 0.10

	# Weather context boosts
	if env == "Rain" and post_name == "Docks":
		p_clue_threat = min(1.0, p_clue_threat + 0.10)
	elif env == "Night" and post_name == "Cave":
		p_clue_threat = min(1.0, p_clue_threat + 0.10)
	elif env == "Foggy" and post_name == "MainGate":
		p_clue_threat = min(1.0, p_clue_threat + 0.08)

	var num = p_clue_threat * prior
	var den = num + (p_clue_no_threat * (1.0 - prior))
	var posterior = 0.0
	if den > 0.0:
		posterior = num / den

	var calc_str = "P(Threat|%s) = (%.2f * %.2f) / %.3f = %.1f%%" % [
		clue, p_clue_threat, prior, den, posterior * 100.0
	]

	return ThreatBelief.new(post_name, clue, prior, p_clue_threat, p_clue_no_threat, posterior, calc_str)

## Dynamic Tactical Utility Matrix
## Returns tactical score of deploying a specific troop to a post under given clue & environment
static func get_tactical_score(troop: String, post: String, clue: String, env: String) -> float:
	var base_score = 60.0

	# 1. Base Counter affinities
	if troop == "Archer" and post == "MainGate": base_score += 25.0
	if troop == "Warrior" and post == "Cave":     base_score += 25.0
	if troop == "Builder" and post == "Docks":    base_score += 25.0

	# 2. Clue-specific weaknesses & counters
	match clue:
		"War Horn": # Armored heavy invasion at Gate -> Warrior excels, Archer arrows bounce off
			if troop == "Warrior" and post == "MainGate": base_score += 35.0
			elif troop == "Archer" and post == "MainGate": base_score -= 15.0
		"Campfire Smoke": # Ranged archer horde -> Builder needed for barricades, Archer trades shots
			if troop == "Builder" and post == "MainGate": base_score += 30.0
		"Earthquake Vibration": # Cave structural tremor -> Builder reinforces cave entrance
			if troop == "Builder" and post == "Cave": base_score += 35.0
		"Faint Hissing": # Poisonous snakes/spiders -> Archer picks them from distance safely
			if troop == "Archer" and post == "Cave": base_score += 30.0
		"Fog Siren": # Sea ship stealth -> Archer fires signal fire arrows
			if troop == "Archer" and post == "Docks": base_score += 30.0
		"Splashing Waves": # Tentacle/aquatic beasts at shoreline -> Warrior chops tentacles
			if troop == "Warrior" and post == "Docks": base_score += 25.0

	# 3. Environment effects
	if env == "Rain":
		if troop == "Archer": base_score -= 20.0 # Bowstrings wet
		elif troop == "Warrior": base_score += 15.0 # Armor & melee unaffected
	elif env == "Night":
		if troop == "Archer": base_score -= 25.0 # Low night visibility
		elif troop == "Warrior": base_score += 20.0 # Close quarters brawl
		elif troop == "Builder": base_score += 10.0 # Lanterns & fortifications
	elif env == "Foggy":
		if troop == "Archer": base_score -= 15.0 # Obscured range
		elif troop == "Builder": base_score += 20.0 # Physical barriers compensate for low sight

	return max(10.0, base_score)

## Assess entire kingdom and optimize troop assignment via MEU
## Permutes all 3^3 = 27 possible assignments of (Archer -> P1, Warrior -> P2, Builder -> P3)
## Allows multiple troops to be assigned to the same post!
static func assess_kingdom(clues: Dictionary, env: String) -> MultiPostAssessment:
	var result = MultiPostAssessment.new()
	result.environment = env

	for post in ["MainGate", "Cave", "Docks"]:
		var clue = clues.get(post, "None")
		result.beliefs[post] = evaluate_post_belief(post, clue, env)

	var posts_sorted = ["MainGate", "Cave", "Docks"]
	posts_sorted.sort_custom(func(a, b):
		return result.beliefs[a].posterior > result.beliefs[b].posterior
	)
	result.priority_order = posts_sorted

	var troops = ["Archer", "Warrior", "Builder"]
	var posts = ["MainGate", "Cave", "Docks"]

	# Check which posts actually have confirmed threats
	var confirmed_posts = []
	for p in posts:
		if result.beliefs[p].is_confirmed:
			confirmed_posts.append(p)

	var best_score = -999999.0
	var best_assignment = {} # { "Archer": "MainGate", "Warrior": "MainGate", ... }

	# All 27 permutations: each troop chooses a post in ["MainGate", "Cave", "Docks"]
	for p_arc in posts:
		for p_war in posts:
			for p_bld in posts:
				var current_eval = 0.0
				var assignment_candidate = { "Archer": p_arc, "Warrior": p_war, "Builder": p_bld }

				# Count troops per post
				var counts = { "MainGate": 0, "Cave": 0, "Docks": 0 }
				counts[p_arc] += 1
				counts[p_war] += 1
				counts[p_bld] += 1

				# Penalty for sending troops to a post with NO threat (posterior < 0.5)
				for p in posts:
					var threat_p = result.beliefs[p].posterior
					var is_threat = result.beliefs[p].is_confirmed
					if not is_threat and counts[p] > 0:
						current_eval -= counts[p] * 60.0 # Waste of troops

				# Reward for matching threatened posts
				for tr in troops:
					var target_post = assignment_candidate[tr]
					var threat_prob = result.beliefs[target_post].posterior
					var clue_at_post = clues.get(target_post, "None")
					var tactical_val = get_tactical_score(tr, target_post, clue_at_post, env)

					# Expected Utility formula: P(Threat) * TacticalValue
					current_eval += threat_prob * tactical_val

				# Concentration synergy bonus: If a high threat (>75%) gets 2 troops, reward synergy
				for p in posts:
					if result.beliefs[p].posterior >= 0.75 and counts[p] >= 2:
						current_eval += 25.0 # Combined arms bonus

				# Coverage bonus: If 2 or 3 posts have confirmed threats, don't leave one completely defenseless if possible
				if confirmed_posts.size() >= 2:
					var defended_confirmed = 0
					for cp in confirmed_posts:
						if counts[cp] > 0:
							defended_confirmed += 1
					current_eval += defended_confirmed * 20.0

				if current_eval > best_score:
					best_score = current_eval
					best_assignment = assignment_candidate

	# Save optimal assignment
	result.troop_to_post = best_assignment
	for tr in best_assignment.keys():
		var target_p = best_assignment[tr]
		# Only actually deploy if that post has a confirmed threat or all threats are active
		if result.beliefs[target_p].is_confirmed:
			result.post_troop_assignments[target_p].append(tr)

	return result
