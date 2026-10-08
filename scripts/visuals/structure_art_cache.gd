class_name StructureArtCache
extends RefCounted
## Web сохраняет исходный рисунок неподвижных деталей в текстуру высокого разрешения.

const SCALE: int = 4
const PADDING: float = 3.0
const MAX_TEXTURE_SIZE: int = 4096
const MAX_ENTRIES: int = 64
const MAX_BYTES: int = 64 * 1024 * 1024
const STALE_FRAMES: int = 120
static var enabled: bool = OS.has_feature("web")
static var _entries: Dictionary[String, Dictionary] = {}
static var _pending: Dictionary[String, Dictionary] = {}
static var _active_job: BakeJob
static var _bytes: int = 0
static var _viewport_watches: Dictionary[int, ViewportWatch] = {}


static func paint(canvas: CanvasItem, key: String, bounds: Rect2, painter: Callable) -> bool:
	if not enabled or DisplayServer.get_name() == "headless" or not canvas.is_inside_tree():
		return false
	_watch_canvas(canvas)
	if maximum_screen_scale(canvas) > float(SCALE) + 0.001:
		return false
	var padded := cache_bounds(bounds)
	var dimensions := texture_dimensions(bounds)
	if dimensions == Vector2i.ZERO:
		return false
	if _entries.has(key):
		var entry: Dictionary = _entries[key]
		if entry["bounds"] != padded:
			return false
		entry["last_used"] = Engine.get_process_frames()
		canvas.draw_texture_rect(entry["texture"] as Texture2D, padded, false)
		return true
	if _pending.has(key):
		if _pending[key]["bounds"] == padded:
			_add_requester(_pending[key], canvas)
		return false
	if not painter.is_valid() or not _has_space(dimensions.x * dimensions.y * 4):
		return false
	var requesters: Array[WeakRef] = [weakref(canvas)]
	_pending[key] = {"bounds": padded, "painter": painter, "requesters": requesters}
	_start_next(canvas.get_tree())
	return false


static func maximum_screen_scale(canvas: CanvasItem) -> float:
	var viewport := canvas.get_viewport()
	var screen_transform := viewport.get_final_transform() * canvas.get_global_transform_with_canvas()
	var maximum := maxf(screen_transform.x.length(), screen_transform.y.length())
	var camera := viewport.get_camera_2d() as GameCamera
	if camera != null and canvas.get_canvas() == camera.get_canvas():
		# Физические детали не перерисовываются при zoom; заранее учитываем весь жест.
		var current_zoom := maxf(0.001, minf(absf(camera.zoom.x), absf(camera.zoom.y)))
		maximum *= maxf(1.0, camera.max_zoom / current_zoom)
	return maximum


static func _watch_canvas(canvas: CanvasItem) -> void:
	var viewport := canvas.get_viewport()
	var id := viewport.get_instance_id()
	if not _viewport_watches.has(id):
		var watch := ViewportWatch.new()
		watch.viewport_id = id
		_viewport_watches[id] = watch
		viewport.size_changed.connect(watch.redraw)
		viewport.tree_exiting.connect(watch.release)
	var canvas_id := canvas.get_instance_id()
	var viewport_watch: ViewportWatch = _viewport_watches[id]
	if not viewport_watch.requesters.has(canvas_id):
		viewport_watch.requesters[canvas_id] = weakref(canvas)
		canvas.tree_exiting.connect(viewport_watch.forget.bind(canvas_id), CONNECT_ONE_SHOT)


static func cache_bounds(bounds: Rect2) -> Rect2:
	var padded := bounds.grow(PADDING)
	var start := padded.position.floor()
	return Rect2(start, padded.end.ceil() - start)


static func texture_dimensions(bounds: Rect2) -> Vector2i:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Vector2i.ZERO
	var dimensions := Vector2i(cache_bounds(bounds).size) * SCALE
	if dimensions.x > MAX_TEXTURE_SIZE or dimensions.y > MAX_TEXTURE_SIZE:
		return Vector2i.ZERO
	return dimensions


static func _add_requester(entry: Dictionary, canvas: CanvasItem) -> void:
	var requesters: Array[WeakRef] = entry["requesters"]
	for requester: WeakRef in requesters:
		if requester.get_ref() == canvas:
			return
	requesters.append(weakref(canvas))


static func _live_requesters(entry: Dictionary) -> Array[CanvasItem]:
	var canvases: Array[CanvasItem] = []
	for requester: WeakRef in entry["requesters"]:
		var canvas := requester.get_ref() as CanvasItem
		if is_instance_valid(canvas) and canvas.is_inside_tree():
			canvases.append(canvas)
	return canvases


static func _has_space(incoming_bytes: int) -> bool:
	if _entries.size() < MAX_ENTRIES and _bytes + incoming_bytes <= MAX_BYTES:
		return true
	var previous_frame := Engine.get_process_frames() - STALE_FRAMES
	for key: String in _entries.keys():
		if _entries[key]["last_used"] < previous_frame:
			_bytes -= int(_entries[key]["bytes"])
			_entries.erase(key)
	return _entries.size() < MAX_ENTRIES and _bytes + incoming_bytes <= MAX_BYTES


static func _start_next(tree: SceneTree) -> void:
	if is_instance_valid(_active_job) or tree == null:
		return
	for key: String in _pending.keys():
		if _live_requesters(_pending[key]).is_empty():
			_pending.erase(key)
			continue
		_active_job = BakeJob.new()
		_active_job.key = key
		tree.root.add_child.call_deferred(_active_job)
		return


static func _finish_job(job: BakeJob, image: Image, elapsed_usec: int) -> void:
	if _active_job != job:
		return
	var entry: Dictionary = _pending.get(job.key, {})
	_pending.erase(job.key)
	_active_job = null
	var canvases: Array[CanvasItem] = _live_requesters(entry) if not entry.is_empty() else []
	if image != null and not canvases.is_empty():
		var image_bytes: int = image.get_width() * image.get_height() * 4
		if _has_space(image_bytes):
			_entries[job.key] = {
				"bounds": entry["bounds"], "texture": ImageTexture.create_from_image(image),
				"last_used": Engine.get_process_frames(), "bytes": image_bytes,
				"bake_usec": elapsed_usec,
			}
			_bytes += image_bytes
			for canvas: CanvasItem in canvases:
				canvas.queue_redraw()
	_start_next(job.get_tree())


class ViewportWatch:
	extends RefCounted
	var viewport_id: int
	var requesters: Dictionary[int, WeakRef] = {}

	func forget(id: int) -> void:
		requesters.erase(id)


	func redraw() -> void:
		for id: int in requesters.keys():
			var canvas := requesters[id].get_ref() as CanvasItem
			if is_instance_valid(canvas) and canvas.is_inside_tree():
				canvas.queue_redraw()
			else:
				requesters.erase(id)


	func release() -> void:
		StructureArtCache._viewport_watches.erase(viewport_id)


class BakeJob:
	extends Node
	var key: String

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_bake.call_deferred()


	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and StructureArtCache._active_job == self:
			StructureArtCache._pending.erase(key)
			StructureArtCache._active_job = null


	func _bake() -> void:
		var started := Time.get_ticks_usec()
		var entry: Dictionary = StructureArtCache._pending.get(key, {})
		if entry.is_empty() or StructureArtCache._live_requesters(entry).is_empty():
			_finish(null, started)
			return
		var bounds: Rect2 = entry["bounds"]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(bounds.size) * StructureArtCache.SCALE
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		var drawing := Node2D.new()
		drawing.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		drawing.position = -bounds.position * StructureArtCache.SCALE
		drawing.scale = Vector2.ONE * StructureArtCache.SCALE
		var painter: Callable = entry["painter"]
		drawing.draw.connect(func() -> void: painter.call(drawing))
		viewport.add_child(drawing)
		add_child(viewport)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		viewport.queue_free()
		if image == null or image.is_empty() or StructureArtCache._live_requesters(entry).is_empty():
			_finish(null, started)
			return
		image.convert(Image.FORMAT_RGBA8)
		var data := image.get_data()
		var chunk_started := Time.get_ticks_usec()
		# Прозрачный framebuffer хранит premultiplied RGB, текстура ожидает straight alpha.
		for offset in range(0, data.size(), 4):
			var alpha: int = data[offset + 3]
			if alpha > 0 and alpha < 255:
				for channel in 3:
					data[offset + channel] = mini(255, roundi(float(data[offset + channel]) * 255.0 / float(alpha)))
			if offset > 0 and offset % 65536 == 0 and Time.get_ticks_usec() - chunk_started >= 2000:
				await get_tree().process_frame
				if StructureArtCache._live_requesters(entry).is_empty():
					_finish(null, started)
					return
				chunk_started = Time.get_ticks_usec()
		image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
		_finish(image, started)


	func _finish(image: Image, started: int) -> void:
		StructureArtCache._finish_job(self, image, Time.get_ticks_usec() - started)
		queue_free()
