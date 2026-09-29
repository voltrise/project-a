class_name CharacterManagerClass
extends Node

## Modular Character Management Library
## Tracks rolled characters in-memory and provides query/management APIs.

signal character_added(character_data: Dictionary)
signal character_removed(character_data: Dictionary)

# List of all obtained characters:
# [{ "id": "bocchi", "name": "Bocchi", "tier": "Rare", "image": "res://characters/bocchi.png", "chance": 24, "count": 1 }, ...]
var _characters: Array[Dictionary] = []

func _ready() -> void:
	pass

## Returns all characters obtained during this session
func get_characters() -> Array[Dictionary]:
	return _characters.duplicate(true)

## Returns all unique character IDs obtained
func get_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for c in _characters:
		var c_id = c.get("id", "")
		if c_id != "" and not c_id in ids:
			ids.append(c_id)
	return ids

## Returns a specific character dictionary by ID, or an empty dictionary if not owned
func get_character_by_id(char_id: String) -> Dictionary:
	for c in _characters:
		if c.get("id", "") == char_id:
			return c.duplicate(true)
	return {}

## Checks if a character has been obtained
func has_character(char_id: String) -> bool:
	for c in _characters:
		if c.get("id", "") == char_id:
			return true
	return false

## Returns how many times a character has been obtained (duplicates)
func get_character_count(char_id: String) -> int:
	for c in _characters:
		if c.get("id", "") == char_id:
			return c.get("count", 1)
	return 0

## Returns the total count of all characters obtained across all rolls
func get_total_character_count() -> int:
	var total: int = 0
	for c in _characters:
		total += int(c.get("count", 1))
	return total

## Adds a newly rolled character to the collection (in-memory only, no disk saving)
func add_character(char_data: Dictionary) -> Dictionary:
	if char_data.is_empty():
		return {}

	var char_id = char_data.get("id", char_data.get("name", "").to_lower())
	var existing_entry: Dictionary = {}

	for c in _characters:
		if c.get("id", "") == char_id:
			existing_entry = c
			break

	var dt = Time.get_datetime_dict_from_system()
	var date_str = "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

	if not existing_entry.is_empty():
		existing_entry["count"] = int(existing_entry.get("count", 1)) + 1
		existing_entry["obtained_date"] = date_str
		character_added.emit(existing_entry.duplicate(true))
		return existing_entry
	else:
		var new_entry = char_data.duplicate(true)
		new_entry["id"] = char_id
		new_entry["count"] = 1
		new_entry["obtained_date"] = date_str
		_characters.append(new_entry)
		character_added.emit(new_entry.duplicate(true))
		return new_entry

## Removes a character by ID (decrements count or removes completely)
func remove_character(char_id: String) -> bool:
	for i in range(_characters.size()):
		if _characters[i].get("id", "") == char_id:
			var item = _characters[i].duplicate(true)
			var count = int(item.get("count", 1))
			if count > 1:
				_characters[i]["count"] = count - 1
			else:
				_characters.remove_at(i)
			character_removed.emit(item)
			return true
	return false

## Clears all characters in memory
func clear_characters() -> void:
	_characters.clear()
