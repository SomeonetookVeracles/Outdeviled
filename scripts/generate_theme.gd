extends Node

func _ready():
	var theme := Theme.new()

	# Zorn palette colors
	var black       = Color("#2B2118")
	var warm_white  = Color("#EDE6D6")
	var red         = Color("#AE2315")
	var yellow      = Color("#D9B310")
	var brown_gray  = Color("#7D6752")
	var light_beige = Color("#C3B091")
	var dark_brown  = Color("#5B4A36")

	# Load font (replace with your font path or comment out)
	# var font_file := load("res://fonts/YourFont.ttf") as FontFile

	# BUTTON STYLING
	for state in ["normal", "hover", "pressed"]:
		var sb = StyleBoxFlat.new()
		if state == "normal":
			sb.bg_color = light_beige
		elif state == "hover":
			sb.bg_color = brown_gray
		elif state == "pressed":
			sb.bg_color = red

		sb.border_color = yellow
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2

		sb.corner_radius_top_left = 4
		sb.corner_radius_bottom_right = 4

		theme.set_stylebox(state, "Button", sb)

	# Button font colors
	theme.set_color("font_color", "Button", warm_white)
	theme.set_color("font_color_hover", "Button", warm_white)
	theme.set_color("font_color_pressed", "Button", warm_white)
	theme.set_color("font_color_disabled", "Button", brown_gray)

	# LABEL STYLING
	theme.set_color("font_color", "Label", warm_white)
	# theme.set_font("font", "Button", font_file)
	# theme.set_font("font", "Label", font_file)

	# BACKGROUND color (for example, if you have a Panel or Control)
	var bg_sb = StyleBoxFlat.new()
	bg_sb.bg_color = dark_brown
	theme.set_stylebox("panel", "Panel", bg_sb)

	# Save theme resource
	var save_path = "res://themes/main_menu_theme.tres"
	var err = ResourceSaver.save(theme, save_path)
	if err == OK:
		print("Zorn palette theme saved to ", save_path)
	else:
		push_error("Failed to save theme!")

	get_tree().quit()
