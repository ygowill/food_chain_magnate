extends RefCounted

static func bind(scene, overlay: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	var action_panel = scene.get("action_panel")
	if action_panel != null and is_instance_valid(action_panel) and action_panel.has_method("bind_context_overlay"):
		action_panel.call("bind_context_overlay", overlay)

static func clear(scene) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	var action_panel = scene.get("action_panel")
	if action_panel != null and is_instance_valid(action_panel) and action_panel.has_method("clear_context_overlay"):
		action_panel.call("clear_context_overlay")
