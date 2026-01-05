# 游戏场景地图视图接入测试（M2）
extends Control

const GAME_SCENE_PATH := "res://ui/scenes/game/game.tscn"

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

func _ready() -> void:
	output.clear()
	output.append_text("GameMapViewTest：验证游戏场景 GameArea 已接入 map.cells 渲染。\n")
	if _should_autorun():
		if is_instance_valid(run_button):
			run_button.disabled = true
		var code: int = await _run_test()
		get_tree().quit(code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	var code: int = await _run_test()
	if is_instance_valid(run_button):
		run_button.disabled = false
	output.append_text("\nExit code: %d\n" % code)

func _run_test() -> int:
	output.append_text("\n--- 开始测试 ---\n")
	print("[GameMapViewTest] START args=%s" % str(OS.get_cmdline_user_args()))

	Globals.reset_game_config()
	Globals.player_count = 2
	Globals.random_seed = 12345

	var packed := ResourceLoader.load(GAME_SCENE_PATH) as PackedScene
	if packed == null:
		var msg := "无法加载场景: %s" % GAME_SCENE_PATH
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		return 1

	var game := packed.instantiate()
	if game is Control:
		(game as Control).visible = false
	add_child(game)

	# 等待一帧，确保 _ready 完成并完成首次渲染。
	await get_tree().process_frame

	var engine = Globals.current_game_engine
	if engine == null:
		var msg := "Globals.current_game_engine 为空，游戏未初始化"
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		game.queue_free()
		return 1

	var state: GameState = engine.get_state()
	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	if grid_size == Vector2i.ZERO:
		var msg := "state.map.grid_size 无效"
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		game.queue_free()
		return 1

	var placeholder := game.get_node_or_null("GameArea/PlaceholderLabel")
	if placeholder != null:
		var msg := "仍存在占位节点 GameArea/PlaceholderLabel"
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		game.queue_free()
		return 1

	var map_view := game.get_node_or_null("GameArea/MapView")
	if map_view == null:
		var msg := "未找到 GameArea/MapView"
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		game.queue_free()
		return 1

	var grid := map_view.get_node_or_null("Grid") as GridContainer
	if grid == null:
		var msg := "未找到 MapView/Grid"
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		game.queue_free()
		return 1

	var expected := grid_size.x * grid_size.y
	var got := grid.get_child_count()
	if got != expected:
		var msg := "Grid child_count 不匹配：got=%d expected=%d" % [got, expected]
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		game.queue_free()
		return 1

	var has_content := false
	for child in grid.get_children():
		if child is Button and str((child as Button).text).strip_edges() != ".":
			has_content = true
			break
	if not has_content:
		var msg := "地图格子全部为空文本（未发现任何道路/房屋/饮品源标记）"
		output.append_text("FAIL: %s\n" % msg)
		push_error("[GameMapViewTest] FAIL: %s" % msg)
		game.queue_free()
		return 1

	output.append_text("PASS\n")
	output.append_text("  grid_size=%dx%d\n" % [grid_size.x, grid_size.y])
	output.append_text("  cell_count=%d\n" % got)
	print("[GameMapViewTest] PASS grid_size=%s cell_count=%d" % [str(grid_size), got])

	game.queue_free()
	return 0

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")

