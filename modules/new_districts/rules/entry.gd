extends RefCounted

func register(registrar) -> Result:
	# UI：apartment 的渲染提示（避免 core UI 写死 piece_id 分支）。
	var r: Result = registrar.register_piece_ui_hint(
		"apartment",
		{
			"structure_style": "house_id",
			"bg_color": Color("#814e60"),
		},
		100
	)
	if not r.ok:
		return r
	return Result.success()
