extends SceneTree

var checks: int = 0
var preserved_core_pixels: int = 0
var blended_edge_pixels: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func _initialize() -> void:
	run.call_deferred()

func mask_pixel(atlas: Image, mask: int, x: int, y: int) -> Color:
	return atlas.get_pixel((mask - 1) % 5 * 256 + x, floori(float(mask - 1) / 5) * 256 + y)

func viewport_for(mask: int, blended: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = TerrainRoads.TEXTURES[mask]
	if blended:
		sprite.material = TerrainRoads.EDGE_MATERIAL
		sprite.set_instance_shader_parameter(&"edge_index", float(mask - 1))
	viewport.add_child(sprite)
	return viewport

func run() -> void:
	var texture: Texture2D = TerrainRoads.EDGE_MATERIAL.get_shader_parameter(&"edge_masks")
	var atlas := texture.get_image()
	check(atlas.get_size() == Vector2i(1280, 768) and not atlas.has_mipmaps(), "Static lossless non-mipmapped mask atlas")
	for mask in range(1, 16):
		var road := TerrainRoads.TEXTURES[mask].get_image()
		var core := 0
		var fringe := 0
		for y in 256:
			for x in 256:
				if road.get_pixel(x, y).a == 0.0:
					continue
				var weight := mask_pixel(atlas, mask, x, y).r
				core += int(weight == 1.0)
				fringe += int(weight > 0.0 and weight < 1.0)
		check(core > 4000 and fringe > 500, "Every piece retains an opaque core and a partial-alpha dirt fringe")
	for a in range(1, 16):
		for b in range(1, 16):
			for pixel in 256:
				if a & 2 and b & 8:
					check(mask_pixel(atlas, a, 255, pixel) == mask_pixel(atlas, b, 0, pixel), "E/W blend weights exactly match")
				if a & 4 and b & 1:
					check(mask_pixel(atlas, a, pixel, 255) == mask_pixel(atlas, b, pixel, 0), "N/S blend weights exactly match")
	if DisplayServer.get_name() != "headless":
		for mask in range(1, 16):
			var before := viewport_for(mask, false)
			var after := viewport_for(mask, true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var original := before.get_texture().get_image()
			var blended := after.get_texture().get_image()
			for y in 256:
				for x in 256:
					var weight := mask_pixel(atlas, mask, x, y).r
					var old := original.get_pixel(x, y)
					var now := blended.get_pixel(x, y)
					if weight == 1.0 and old.a > 0.0:
						check(old == now, "GPU road core RGBA remains pixel-exact")
						preserved_core_pixels += 1
					if old.a == 0.0:
						check(now.a == 0.0, "No rectangular halo or opacity outside original artwork")
					if old.a > 0.0 and weight > 0.0 and weight < 1.0:
						check(now.a < old.a and absf(now.a - old.a * weight) < 0.009, "GPU shader applies exterior alpha only")
						blended_edge_pixels += 1
			before.free()
			after.free()
		var report := {"checks": checks, "preserved_core_pixels": preserved_core_pixels, "blended_edge_pixels": blended_edge_pixels, "fringe_width": 16}
		var output := FileAccess.open("res://docs/road_blending_validation.json", FileAccess.WRITE)
		output.store_string(JSON.stringify(report, "\t") + "\n")
		output.close()
		print("RENDERED BLEND PASS ", report)
	else:
		print("HEADLESS BLEND DATA PASS checks=", checks, " (run rendered for GPU comparison)")
	quit()
