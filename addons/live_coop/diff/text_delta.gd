@tool
class_name CoopTextDelta
extends RefCounted

## Computes the minimal prefix-suffix delta between old_text and new_text.
## Returns a Dictionary:
## {
##   "empty": bool,
##   "offset": int,
##   "deleted_len": int,
##   "inserted_text": String
## }
static func compute_delta(old_text: String, new_text: String) -> Dictionary:
	if old_text == new_text:
		return { "empty": true, "offset": 0, "deleted_len": 0, "inserted_text": "" }
	
	var old_len: int = old_text.length()
	var new_len: int = new_text.length()
	
	# 1. Find common prefix length
	var prefix_len: int = 0
	var min_len: int = mini(old_len, new_len)
	while prefix_len < min_len and old_text.unicode_at(prefix_len) == new_text.unicode_at(prefix_len):
		prefix_len += 1
	
	# 2. Find common suffix length (bounded so it does not overlap the prefix)
	var suffix_len: int = 0
	var max_suffix: int = mini(old_len - prefix_len, new_len - prefix_len)
	while suffix_len < max_suffix and old_text.unicode_at(old_len - 1 - suffix_len) == new_text.unicode_at(new_len - 1 - suffix_len):
		suffix_len += 1
	
	var deleted_len: int = (old_len - suffix_len) - prefix_len
	var inserted_len: int = (new_len - suffix_len) - prefix_len
	var inserted_text: String = new_text.substr(prefix_len, inserted_len)
	
	return {
		"empty": false,
		"offset": prefix_len,
		"deleted_len": deleted_len,
		"inserted_text": inserted_text
	}

## Applies a delta to an existing string.
static func apply_delta(text: String, delta: Dictionary) -> String:
	if delta.get("empty", false):
		return text
	
	var offset: int = delta.get("offset", 0)
	var deleted_len: int = delta.get("deleted_len", 0)
	var inserted_text: String = delta.get("inserted_text", "")
	
	var text_len: int = text.length()
	offset = clampi(offset, 0, text_len)
	var end_del: int = clampi(offset + deleted_len, offset, text_len)
	
	var before: String = text.substr(0, offset)
	var after: String = text.substr(end_del)
	
	return before + inserted_text + after

## Converts a 1D character offset into a Vector2i(line, column), 0-indexed.
static func offset_to_line_col(text: String, offset: int) -> Vector2i:
	var line: int = 0
	var col: int = 0
	var target: int = mini(offset, text.length())
	
	for i in range(target):
		if text.unicode_at(i) == 10: # '\n'
			line += 1
			col = 0
		else:
			col += 1
			
	return Vector2i(line, col)

## Converts a Vector2i(line, column) into a 1D character offset.
static func line_col_to_offset(text: String, line: int, col: int) -> int:
	var cur_line: int = 0
	var cur_col: int = 0
	var text_len: int = text.length()
	
	for i in range(text_len):
		if cur_line == line and cur_col == col:
			return i
		if text.unicode_at(i) == 10: # '\n'
			if cur_line == line:
				# Column exceeded line length, stop here
				return i
			cur_line += 1
			cur_col = 0
		else:
			cur_col += 1
			
	return text_len

## Adjusts a caret offset in response to a remote delta.
static func adjust_caret_offset(caret_offset: int, delta: Dictionary) -> int:
	if delta.get("empty", false):
		return caret_offset
		
	var edit_offset: int = delta.get("offset", 0)
	var deleted_len: int = delta.get("deleted_len", 0)
	var inserted_len: int = delta.get("inserted_text", "").length()
	
	if caret_offset <= edit_offset:
		# Caret is before the edit, untouched
		return caret_offset
	elif caret_offset < edit_offset + deleted_len:
		# Caret fell inside the deleted range; snap to end of insertion
		return edit_offset + inserted_len
	else:
		# Caret was after the edit; shift by delta length change
		return caret_offset + (inserted_len - deleted_len)
