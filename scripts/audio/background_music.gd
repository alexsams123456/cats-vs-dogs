class_name BackgroundMusic
extends AudioStreamPlayer
## Непрерывный фон приложения; общий звук, пауза и фокус окна действуют на музыку.

@export_range(0.1, 10.0, 0.1) var fade_in_seconds: float = 2.5

var _application_focused: bool = true
var _fade: Tween


func _ready() -> void:
	var target_volume: float = volume_linear
	volume_linear = 0.0
	play()
	_fade = create_tween()
	_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade.tween_property(self, "volume_linear", target_volume, fade_in_seconds)
	_sync_playback()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_focused = false
		_sync_playback()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_application_focused = true
		_sync_playback()
	elif what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		# После встроенной обработки AudioStreamPlayer сохраняем также запрет по фокусу.
		_sync_playback.call_deferred()


func _sync_playback() -> void:
	if not is_inside_tree():
		return
	var suspended := not _application_focused or not can_process()
	stream_paused = suspended
	if _fade != null and _fade.is_valid():
		if suspended:
			_fade.pause()
		else:
			_fade.play()
