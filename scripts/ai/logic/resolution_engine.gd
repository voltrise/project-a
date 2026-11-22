class_name ResolutionEngine
extends RefCounted

## Resolution Refutation Inference Engine
## Implements Propositional Logic Resolution (Slide 15-28 of Logic & Knowledge Representation)
## Searches for empty clause (CONTRADICTION / FALSE) to prove a query Q by showing KB AND ~Q is unsatisfiable.

class ResolutionStep:
	var step_num: int
	var clause_a: Array
	var clause_b: Array
	var resolved_literal: String
	var resolvent: Array
	var from_indices: Array = [] # [idxA, idxB]

	func _init(p_num: int, p_a: Array, p_b: Array, p_lit: String, p_res: Array, p_indices: Array = []):
		step_num = p_num
		clause_a = p_a.duplicate()
		clause_b = p_b.duplicate()
		resolved_literal = p_lit
		resolvent = p_res.duplicate()
		from_indices = p_indices

	func to_display_string() -> String:
		var str_a = _clause_to_str(clause_a)
		var str_b = _clause_to_str(clause_b)
		var str_res = "FALSE (CONTRADICTION)" if resolvent.is_empty() else _clause_to_str(resolvent)
		return "[Step %d] Resolve (%s) with (%s) on '%s' -> %s" % [step_num, str_a, str_b, resolved_literal, str_res]

	func _clause_to_str(c: Array) -> String:
		if c.is_empty():
			return "EMPTY"
		return " OR ".join(c)

class ProofResult:
	var query: String
	var is_proved: bool = false
	var steps: Array[ResolutionStep] = []
	var initial_clauses: Array = []
	var execution_time_ms: float = 0.0

	func get_trace_text() -> String:
		var lines: Array[String] = []
		lines.append("=== RESOLUTION REFUTATION PROOF ===")
		lines.append("Query: Prove %s" % query)
		lines.append("Negated Query added: %s" % ("-" + query if not query.begins_with("-") else query.substr(1)))
		lines.append("\nInitial KB Clauses:")
		for i in range(initial_clauses.size()):
			lines.append("  (%d) %s" % [i + 1, " OR ".join(initial_clauses[i])])
		lines.append("\nResolution Steps (Proof Tree):")
		if steps.is_empty():
			lines.append("  (No resolution steps performed or contradiction not found)")
		else:
			for s in steps:
				lines.append("  " + s.to_display_string())
		lines.append("\nResult: %s" % ("PROVED (Contradiction Found)" if is_proved else "FAILED (Cannot Prove / Satisfiable)"))
		return "\n".join(lines)


static func negate_literal(lit: String) -> String:
	if lit.begins_with("-"):
		return lit.substr(1)
	return "-" + lit

static func are_complementary(lit1: String, lit2: String) -> bool:
	return negate_literal(lit1) == lit2

static func normalize_clause(clause: Array) -> Array:
	var unique = {}
	for lit in clause:
		unique[lit] = true
	var sorted_lits = unique.keys()
	sorted_lits.sort()
	return sorted_lits

static func is_tautology(clause: Array) -> bool:
	var seen = {}
	for lit in clause:
		if seen.has(negate_literal(lit)):
			return true
		seen[lit] = true
	return false

static func load_rules_from_file(filepath: String) -> Array:
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("Cannot open KB file: " + filepath)
		return []
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		push_error("Error parsing KB JSON: " + json.get_error_message())
		return []
	var data = json.get_data()
	var clauses = []
	if data.has("rules"):
		for rule in data["rules"]:
			if rule.has("cnf_clauses"):
				for c in rule["cnf_clauses"]:
					clauses.append(normalize_clause(c))
	return clauses

## Solve Resolution Refutation for Query
## Set-of-Support strategy: Prioritize resolving with negated query or clauses derived from it
static func prove(clauses_input: Array, facts: Dictionary, query: String) -> ProofResult:
	var start_time = Time.get_ticks_usec()
	var result = ProofResult.new()
	result.query = query

	# 1. Base KB clauses
	var base_clauses: Array = []
	for c in clauses_input:
		base_clauses.append(normalize_clause(c))

	# Add facts as unit clauses
	for fact_name in facts.keys():
		var val = facts[fact_name]
		if val == true:
			base_clauses.append([fact_name])
		elif val == false:
			base_clauses.append(["-" + fact_name])

	# 2. Set of Support (SoS): initially contains only the negated query
	var negated_query = negate_literal(query)
	var sos: Array = [[negated_query]]

	var all_initial: Array = []
	for c in base_clauses:
		all_initial.append(c.duplicate())
	all_initial.append([negated_query])
	result.initial_clauses = all_initial

	var all_clauses: Array = []
	for c in base_clauses:
		all_clauses.append(c.duplicate())
	all_clauses.append([negated_query])

	var steps: Array[ResolutionStep] = []
	var step_counter = 1
	var max_iterations = 250

	while not sos.is_empty() and max_iterations > 0:
		max_iterations -= 1
		var current_sos = sos.pop_front()

		# Resolve current_sos against all clauses in all_clauses
		for other in all_clauses:
			if current_sos == other:
				continue

			# Check if there is exactly one complementary pair
			var comp_lits = []
			for l1 in current_sos:
				if other.has(negate_literal(l1)):
					comp_lits.append(l1)

			if comp_lits.size() == 1:
				var lit = comp_lits[0]
				var comp = negate_literal(lit)

				var resolvent: Array = []
				for l in current_sos:
					if l != lit:
						resolvent.append(l)
				for l in other:
					if l != comp:
						resolvent.append(l)
				resolvent = normalize_clause(resolvent)

				if not is_tautology(resolvent):
					var step = ResolutionStep.new(step_counter, current_sos, other, lit, resolvent)
					steps.append(step)
					step_counter += 1

					if resolvent.is_empty():
						# Contradiction derived!
						result.is_proved = true
						result.steps = steps
						result.execution_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
						return result

					if not all_clauses.has(resolvent) and not sos.has(resolvent):
						sos.append(resolvent)
						all_clauses.append(resolvent)

	result.is_proved = false
	result.steps = steps
	result.execution_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
	return result
