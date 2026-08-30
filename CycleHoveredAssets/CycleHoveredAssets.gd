#########################################################################################################
##
## SCROLL HOVERED MOD
## Allows cycling through stacked assets with Tab key to select assets underneath
## Shows a tooltip with the asset name when cycling
##
#########################################################################################################

var script_class = "tool"

var select_tool = null
var select_tool_panel = null

# List of nodes under the cursor
var nodes_under_cursor = []
var current_index = 0

# Track key state to avoid repeated triggers
var _tab_pressed = false

# Track state to detect changes
var last_mouse_pos = Vector2.ZERO
var last_filter_hash = 0
var last_layer_filter_hash = 0

# Tooltip UI
var tooltip_label = null
var tooltip_timer = null
const TOOLTIP_DURATION = 2.0  # seconds

# Tooltip drag
var tooltip_dragging = false
var tooltip_drag_offset = Vector2.ZERO
var tooltip_custom_position = null  # If set, use this instead of centering

func start() -> void:
	select_tool = Global.Editor.Tools["SelectTool"]
	select_tool_panel = Global.Editor.Toolset.GetToolPanel("SelectTool")
	call_deferred("setup_tooltip")
	print("[ScrollHovered] Mod loaded")

func setup_tooltip() -> void:
	# Create tooltip label
	tooltip_label = Label.new()
	tooltip_label.name = "ScrollHoveredTooltip"
	tooltip_label.align = Label.ALIGN_CENTER
	tooltip_label.valign = Label.VALIGN_CENTER
	
	# Style the tooltip
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	stylebox.border_color = Color(0.4, 0.6, 0.9, 1.0)  # Blue tint to differentiate from InspectAsset
	stylebox.border_width_top = 2
	stylebox.border_width_bottom = 2
	stylebox.border_width_left = 2
	stylebox.border_width_right = 2
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	stylebox.content_margin_left = 12
	stylebox.content_margin_right = 12
	stylebox.content_margin_top = 8
	stylebox.content_margin_bottom = 8
	
	tooltip_label.add_stylebox_override("normal", stylebox)
	tooltip_label.add_color_override("font_color", Color(1, 1, 1, 1))
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_STOP  # Allow mouse interaction for dragging
	tooltip_label.visible = false
	
	# Connect drag signals
	tooltip_label.connect("gui_input", self, "_on_tooltip_gui_input")
	
	# Add to UI layer
	var ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	ui_layer.name = "ScrollHoveredTooltipLayer"
	
	Global.Editor.add_child(ui_layer)
	ui_layer.add_child(tooltip_label)
	
	# Create timer for auto-hide
	tooltip_timer = Timer.new()
	tooltip_timer.one_shot = true
	tooltip_timer.connect("timeout", self, "_on_tooltip_timeout")
	Global.Editor.add_child(tooltip_timer)

func _on_tooltip_timeout() -> void:
	tooltip_label.visible = false

func _on_tooltip_gui_input(event) -> void:
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				tooltip_dragging = true
				tooltip_drag_offset = tooltip_label.rect_position - event.global_position
				# Stop the timer while dragging
				tooltip_timer.stop()
			else:
				# Stop dragging
				tooltip_dragging = false
				# Save the custom position
				tooltip_custom_position = tooltip_label.rect_position
				# Restart timer
				tooltip_timer.start(TOOLTIP_DURATION)
	
	elif event is InputEventMouseMotion:
		if tooltip_dragging:
			var new_pos = event.global_position + tooltip_drag_offset
			
			# Clamp to window bounds
			var viewport = Global.Editor.get_viewport()
			var screen_size = viewport.size
			var tooltip_size = tooltip_label.rect_size
			
			new_pos.x = clamp(new_pos.x, 0, screen_size.x - tooltip_size.x)
			new_pos.y = clamp(new_pos.y, 0, screen_size.y - tooltip_size.y)
			
			tooltip_label.rect_position = new_pos

func show_tooltip(text: String) -> void:
	# Reset size first to force recalculation
	tooltip_label.rect_min_size = Vector2.ZERO
	tooltip_label.rect_size = Vector2.ZERO
	
	# Set new text
	tooltip_label.text = text
	
	# Position the tooltip
	if tooltip_custom_position != null:
		# Use saved custom position
		tooltip_label.rect_position = tooltip_custom_position
	else:
		# Center at top of screen
		var viewport = Global.Editor.get_viewport()
		var screen_size = viewport.size
		call_deferred("_position_tooltip_centered", screen_size)
	
	tooltip_label.visible = true
	
	# Restart timer
	tooltip_timer.stop()
	tooltip_timer.start(TOOLTIP_DURATION)

func _position_tooltip_centered(screen_size: Vector2) -> void:
	# Force size recalculation
	tooltip_label.rect_size = Vector2.ZERO
	
	var tooltip_size = tooltip_label.rect_size
	tooltip_label.rect_position.x = (screen_size.x - tooltip_size.x) / 2
	tooltip_label.rect_position.y = 60

func update(delta: float) -> void:
	# Check that editor is ready and a map is open
	if Global.World == null:
		return
	if Global.World.levels == null or Global.World.levels.empty():
		return
	
	# Only work when SelectTool is active
	if Global.Editor.Toolset == null:
		return
	if not Global.Editor.Toolset.ToolPanels.has("SelectTool"):
		return
	if not Global.Editor.Toolset.ToolPanels["SelectTool"].visible:
		return
	
	# Check that SelectTool is properly initialized by checking if Selected array exists
	if select_tool.Selected == null:
		return
	
	# Check for Tab key
	if Input.is_key_pressed(KEY_TAB):
		if not _tab_pressed:
			_tab_pressed = true
			cycle_selection()
	else:
		_tab_pressed = false

func cycle_selection() -> void:
	var current_thing = null
	
	# Get current mouse position
	var viewport = Global.World.get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var canvas_transform = viewport.get_canvas_transform()
	var world_mouse_pos = canvas_transform.affine_inverse().xform(mouse_pos)
	
	# Check if we have a selected thing that's in our list AND the list is still valid for current position
	if select_tool.Selected.size() > 0:
		var selected_thing = select_tool.Selected[0]
		
		# Check if selected thing is in our list
		var in_list = false
		for node in nodes_under_cursor:
			if node == selected_thing:
				in_list = true
				break
		
		# Only use selected thing if it's in the list AND mouse hasn't moved too far
		if in_list and last_mouse_pos.distance_to(world_mouse_pos) <= 50:
			current_thing = selected_thing
	
	# If selected thing not usable, check highlighted
	if current_thing == null:
		select_tool.HighlightThingAtPoint()
		var current_highlighted = select_tool.get("highlighted")
		
		if current_highlighted == null:
			nodes_under_cursor.clear()
			return
		
		current_thing = current_highlighted.get("Thing")
	
	if current_thing == null:
		return
	
	# Check if filters changed
	var current_filter_hash = get_filter_hash()
	var current_layer_filter_hash = get_layer_filter_hash()
	
	# Check if we need to rebuild
	var need_rebuild = false
	
	# Rebuild if list is empty
	if nodes_under_cursor.size() == 0:
		need_rebuild = true
	
	# Rebuild if mouse moved significantly (more than 50 pixels)
	if last_mouse_pos.distance_to(world_mouse_pos) > 50:
		need_rebuild = true
	
	# Rebuild if filters changed
	if current_filter_hash != last_filter_hash or current_layer_filter_hash != last_layer_filter_hash:
		need_rebuild = true
	
	# Rebuild if current_thing is not in list
	if not need_rebuild:
		var found = false
		for node in nodes_under_cursor:
			if node == current_thing:
				found = true
				break
		if not found:
			need_rebuild = true
	
	if need_rebuild:
		build_nodes_list(current_thing)
		current_index = 0
		last_mouse_pos = world_mouse_pos
		last_filter_hash = current_filter_hash
		last_layer_filter_hash = current_layer_filter_hash
		print("[ScrollHovered] Rebuilt list with ", nodes_under_cursor.size(), " nodes")
		for i in range(nodes_under_cursor.size()):
			print("[ScrollHovered]   [", i, "] ", nodes_under_cursor[i].name)
	else:
		# Find current_thing's index
		var found = false
		for i in range(nodes_under_cursor.size()):
			if nodes_under_cursor[i] == current_thing:
				current_index = i
				found = true
				break
		print("[ScrollHovered] Reusing list, looking for ", current_thing.name, " found=", found, " current_index=", current_index)
	
	if nodes_under_cursor.size() <= 1:
		return
	
	# Cycle to next
	current_index += 1
	if current_index >= nodes_under_cursor.size():
		current_index = 0
	
	print("[ScrollHovered] Cycling to index ", current_index, " of ", nodes_under_cursor.size(), ": ", nodes_under_cursor[current_index].name)
	
	var next_node = nodes_under_cursor[current_index]
	
	# Select the next node
	select_tool.DeselectAll()
	select_tool.SelectThing(next_node, true)
	
	if select_tool.Selected.size() == 0:
		select_tool.Select(next_node)
	
	select_tool.OnFinishSelection()
	
	# Update the panel to reflect the new selection
	var sel_type = get_selectable_type(next_node)
	if sel_type > 0:
		select_tool_panel.OnSelect(sel_type)
	
	# Show tooltip with asset name
	var asset_name = get_asset_name(next_node)
	var type_name = get_asset_type(next_node)
	var layer_name = get_layer_name(next_node)
	show_tooltip(asset_name + "\n[" + type_name + "] " + str(current_index + 1) + "/" + str(nodes_under_cursor.size()) + "\n" + layer_name)

func get_filter_hash() -> int:
	var filter = select_tool.get("Filter")
	if filter == null:
		return 0
	var hash_val = 0
	for key in filter:
		if filter[key]:
			hash_val += key.hash()
	return hash_val

func get_layer_filter_hash() -> int:
	var layer_filter = select_tool.get("LayerFilter")
	if layer_filter == null:
		return 0
	var hash_val = 0
	for key in layer_filter:
		if layer_filter[key]:
			hash_val += key
	return hash_val

func get_selectable_type(node) -> int:
	# Return the selectable type based on parent
	var parent = node.get_parent()
	if parent == null:
		return 0
	
	var parent_name = parent.name
	match parent_name:
		"Objects":
			return 4
		"Lights":
			return 6
		"Pathways":
			return 5
		"Walls":
			return 1
		"Portals":
			return 2
		"Roofs":
			return 8
	
	# Pattern shapes
	if node is Polygon2D:
		return 7
	
	return 0

func build_nodes_list(reference_thing) -> void:
	nodes_under_cursor.clear()
	current_index = 0
	
	if reference_thing == null:
		return
	
	# Use mouse position for detection
	var viewport = Global.World.get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var canvas_transform = viewport.get_canvas_transform()
	var world_mouse_pos = canvas_transform.affine_inverse().xform(mouse_pos)
	
	# Also get reference thing position
	var ref_pos = reference_thing.global_position
	
	# Use mouse position as primary, but fallback to ref_pos if mouse is at origin
	var check_pos = world_mouse_pos
	if world_mouse_pos == Vector2.ZERO:
		check_pos = ref_pos
	
	# Add the reference thing first
	nodes_under_cursor.append(reference_thing)
	
	# Get current level
	var current_level = Global.World.levels[Global.World.CurrentLevelId]
	
	# Check Objects
	if is_type_filter_enabled("Objects"):
		for obj in current_level.Objects.get_children():
			if obj == reference_thing:
				continue
			if obj.get("global_position") == null:
				continue
			if not passes_layer_filter(obj):
				continue
			var dist = obj.global_position.distance_to(check_pos)
			if dist < 100:
				nodes_under_cursor.append(obj)
	
	# Check Lights
	if is_type_filter_enabled("Lights"):
		for light in current_level.Lights.get_children():
			if light == reference_thing:
				continue
			if light.get("global_position") == null:
				continue
			if not passes_layer_filter(light):
				continue
			var dist = light.global_position.distance_to(check_pos)
			if dist < 100:
				nodes_under_cursor.append(light)
	
	# Check Pathways
	if is_type_filter_enabled("Paths"):
		for path in current_level.Pathways.get_children():
			if path == reference_thing:
				continue
			if not passes_layer_filter(path):
				continue
			if is_point_near_path(check_pos, path):
				nodes_under_cursor.append(path)
	
	# Check PatternShapes
	if is_type_filter_enabled("Patterns"):
		if current_level.PatternShapes.has_method("GetShapes"):
			var shapes = current_level.PatternShapes.GetShapes()
			for shape in shapes:
				if shape == reference_thing:
					continue
				if not passes_layer_filter(shape):
					continue
				if is_point_in_polygon_node(check_pos, shape):
					nodes_under_cursor.append(shape)
	
	# Check Walls
	if is_type_filter_enabled("Walls"):
		for wall in current_level.Walls.get_children():
			if wall == reference_thing:
				continue
			if is_point_near_path(check_pos, wall):
				nodes_under_cursor.append(wall)
	
	# Check Portals
	if is_type_filter_enabled("Portals"):
		for portal in current_level.Portals.get_children():
			if portal == reference_thing:
				continue
			if portal.get("global_position") == null:
				continue
			var dist = portal.global_position.distance_to(check_pos)
			if dist < 100:
				nodes_under_cursor.append(portal)
	
	# Check Roofs
	if is_type_filter_enabled("Roofs"):
		for roof in current_level.Roofs.get_children():
			if roof == reference_thing:
				continue
			if is_point_in_polygon_node(check_pos, roof):
				nodes_under_cursor.append(roof)

func is_type_filter_enabled(type_name: String) -> bool:
	# Check if type is enabled in SelectTool filter
	var filter = select_tool.get("Filter")
	
	if filter == null:
		return true
	if not filter.has(type_name):
		return true
	
	return filter[type_name]

func passes_layer_filter(node) -> bool:
	# Check if node's layer passes the SelectTool layer filter
	
	# Get node's layer
	var node_layer = null
	
	# Try different layer properties
	if node.get("Layer") != null:
		node_layer = node.Layer
	elif node.get("layer") != null:
		node_layer = node.layer
	elif node.z_index != 0:
		node_layer = node.z_index
	
	# If no layer found, include by default
	if node_layer == null:
		return true
	
	# Check LayerFilter
	var layer_filter = select_tool.get("LayerFilter")
	
	if layer_filter == null or layer_filter.empty():
		return true
	
	if not layer_filter.has(node_layer):
		return true
	
	return layer_filter[node_layer]

func get_asset_name(node) -> String:
	# Get texture path and extract name
	var tex_path = get_texture_path(node)
	
	if tex_path == "":
		return node.name
	
	# Extract name from path
	var name = ""
	
	# For roofs, use folder name
	if "/roofs/" in tex_path and "/tiles.png" in tex_path:
		var parts = tex_path.split("/")
		for i in range(parts.size()):
			if parts[i] == "roofs" and i + 1 < parts.size():
				name = parts[i + 1]
				break
	else:
		# Use filename without extension
		var filename = tex_path.get_file()
		name = filename.get_basename()
		
		# Remove common prefixes
		if name.begins_with("tileset_"):
			name = name.substr(8)
		elif name.begins_with("Wall_"):
			name = name.substr(5)
		elif name.begins_with("Path_"):
			name = name.substr(5)
	
	# Clean up: replace underscores, capitalize
	name = name.replace("_", " ")
	var words = name.split(" ")
	var capitalized = []
	for word in words:
		if word.length() > 0:
			capitalized.append(word.capitalize())
	
	return PoolStringArray(capitalized).join(" ")

func get_texture_path(node) -> String:
	# Try different properties based on node type
	
	# Object (Texture property)
	if node.get("Texture") != null and node.Texture != null:
		return node.Texture.resource_path
	
	# Path/Light (get_texture method)
	if node.has_method("get_texture"):
		var tex = node.get_texture()
		if tex != null:
			return tex.resource_path
	
	# Pattern (_Texture property)
	if node.get("_Texture") != null and node._Texture != null:
		return node._Texture.resource_path
	
	# Roof (TilesTexture property)
	if node.get("TilesTexture") != null and node.TilesTexture != null:
		return node.TilesTexture.resource_path
	
	return ""

func get_asset_type(node) -> String:
	# Determine type based on parent or properties
	var parent = node.get_parent()
	if parent != null:
		var parent_name = parent.name
		if parent_name == "Objects":
			return "Object"
		elif parent_name == "Lights":
			return "Light"
		elif parent_name == "Pathways":
			return "Path"
		elif parent_name == "Roofs":
			return "Roof"
		elif parent_name == "Walls":
			return "Wall"
		elif parent_name == "Portals":
			return "Portal"
	
	# Check for pattern
	if node is Polygon2D:
		return "Pattern"
	
	return "Asset"

func get_layer_name(node) -> String:
	# Get the layer value
	var node_layer = null
	
	# Check Layer property first (uppercase)
	if node.get("Layer") != null:
		node_layer = node.Layer
	# Then check z_index (for Objects, Paths) - only if not 0
	elif node.z_index != 0:
		node_layer = node.z_index
	# For patterns, the layer is in the parent's z_index
	elif node is Polygon2D:
		var parent = node.get_parent()
		if parent != null and parent.z_index != 0:
			node_layer = parent.z_index
	
	if node_layer == null:
		return "Layer: Unknown"
	
	# Map layer values to names (DD vanilla)
	var layer_names = {
		-500: "Terrain",
		-400: "Below Ground",
		-300: "Caves",
		-200: "Floor",
		-100: "Below Water",
		0: "Water",
		100: "User Layer 1",
		200: "User Layer 2",
		300: "User Layer 3",
		400: "User Layer 4",
		500: "Portals",
		600: "Walls",
		700: "Above Walls",
		800: "Roofs",
		900: "Above Roofs"
	}
	
	if layer_names.has(node_layer):
		return "Layer: " + layer_names[node_layer]
	else:
		return "Layer: " + str(node_layer)

func is_point_in_polygon_node(point: Vector2, polygon_node) -> bool:
	if not polygon_node is Polygon2D:
		return false
	var poly_points = polygon_node.polygon
	if poly_points == null or poly_points.size() < 3:
		return false
	
	var local_point = polygon_node.get_global_transform().affine_inverse().xform(point)
	return is_point_in_polygon(local_point, poly_points)

func is_point_near_path(point: Vector2, path_node) -> bool:
	var points = null
	if path_node.get("points") != null:
		points = path_node.points
	elif path_node.get("Points") != null:
		points = path_node.Points
	
	if points == null or points.size() < 2:
		return false
	
	var tolerance = 80.0
	if path_node.get("width") != null:
		tolerance = max(tolerance, path_node.width / 2 + 40)
	
	for i in range(points.size() - 1):
		var p1 = path_node.to_global(points[i])
		var p2 = path_node.to_global(points[i + 1])
		var dist = point_to_segment_distance(point, p1, p2)
		if dist < tolerance:
			return true
	
	return false

func point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var seg = seg_end - seg_start
	var seg_length_sq = seg.length_squared()
	
	if seg_length_sq == 0:
		return point.distance_to(seg_start)
	
	var t = max(0, min(1, (point - seg_start).dot(seg) / seg_length_sq))
	var projection = seg_start + t * seg
	
	return point.distance_to(projection)

func is_point_in_polygon(point: Vector2, polygon) -> bool:
	var inside = false
	var j = polygon.size() - 1
	
	for i in range(polygon.size()):
		var pi = polygon[i]
		var pj = polygon[j]
		
		if ((pi.y > point.y) != (pj.y > point.y)) and \
		   (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	
	return inside
