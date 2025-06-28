extends Node
class_name MovementProfileManager

signal profile_changed(character_name: String, new_profile: String)

var movement_profiles: Dictionary = {}
var character_assignments: Dictionary = {}

func _ready():
	create_default_profiles()

func create_default_profiles():
	"""Create all default movement profiles"""
	register_profile(MovementProfile.create_infantry_profile())
	register_profile(MovementProfile.create_scout_profile())
	register_profile(MovementProfile.create_heavy_profile())
	register_profile(MovementProfile.create_knight_profile())
	register_profile(MovementProfile.create_archer_profile())
	register_profile(MovementProfile.create_flyer_profile())
	
	print("Created %d movement profiles" % movement_profiles.size())

func register_profile(profile: MovementProfile):
	"""Register a movement profile"""
	movement_profiles[profile.profile_name] = profile

func get_character_profile(character_name: String) -> MovementProfile:
	"""Get the movement profile assigned to a character"""
	var profile_name = character_assignments.get(character_name, "Infantry")
	return movement_profiles.get(profile_name, null)

func assign_profile_to_character(character_name: String, profile_name: String) -> bool:
	"""Assign a movement profile to a character"""
	if not movement_profiles.has(profile_name):
		push_error("Movement profile '%s' not found!" % profile_name)
		return false
	
	character_assignments[character_name] = profile_name
	profile_changed.emit(character_name, profile_name)
	return true

func get_all_profile_names() -> Array[String]:
	"""Get list of all available profile names"""
	var names: Array[String] = []
	for name in movement_profiles.keys():
		names.append(name)
	return names

func create_custom_profile(name: String, max_range: int, pattern: MovementProfile.MovementPattern) -> MovementProfile:
	"""Helper to create custom profiles"""
	var profile = MovementProfile.new()
	profile.profile_name = name
	profile.max_movement_range = max_range
	profile.movement_pattern = pattern
	register_profile(profile)
	return profile
