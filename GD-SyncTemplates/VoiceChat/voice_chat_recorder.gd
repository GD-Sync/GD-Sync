extends Node

#Make sure to create an Audio Bus for recording audio!
#https://docs.godotengine.org/en/stable/tutorials/audio/recording_with_microphone.html

@export var _record_bus_name : String

var _bus_index : int
var _recorder : AudioEffectRecord

var _enabled : bool = false

@onready var _timer : Timer = $Timer

func _ready():
	_bus_index = AudioServer.get_bus_index(_record_bus_name)
	_recorder = AudioServer.get_bus_effect(_bus_index, 0)

func enable_recording():
	_timer.start()
	_recorder.set_recording_active(true)

func disable_recording(): 
	_timer.stop()
	_recorder.set_recording_active(false)

func _on_timer_timeout():
	if !GDSync.is_active(): return
	
	_recorder.set_recording_active(true)
