@icon("res://addons/GD-Sync/UI/Icons/SynchronizedAnimatedSprite.png")
extends AnimatedSprite2D
class_name SynchronizedAnimatedSprite2D

#Copyright (c) 2023-present GD-Sync.
#All rights reserved.
#
#Redistribution and use in source form, with or without modification,
#are permitted provided that the following conditions are met:
#
#1. Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
#
#2. Neither the name of GD-Sync nor the names of its contributors may be used
#   to endorse or promote products derived from this software without specific
#   prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
#EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
#OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
#SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
#TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
#BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#SUCH DAMAGE.

func play_synced(name: StringName = &"", custom_speed: float = 1.0, from_end: bool = false) -> void:
	var send_remote_play : bool = !is_playing() || animation != name
	play(name, custom_speed, from_end)
	
	if !GDSync.is_active(): return
	if !_should_broadcast: return
	if !send_remote_play: return
	
	var use_name : bool = name.length() > 0
	var name_cached : bool = use_name and GDSync._session_controller.name_is_cached(name)
	var parameters : Array = []
	
	var defaults_flipped : Array = [false, 1.0, null if name_cached else &""]
	var actual_values : Array = [
		from_end,
		custom_speed,
		GDSync._session_controller.get_name_index(name) if name_cached else name
	]
	
	var include_all : bool = false
	for i in range(defaults_flipped.size()):
		var default = defaults_flipped[i]
		var actual = actual_values[i]
		if default != actual:
			include_all = true
		
		if include_all:
			parameters.push_front(actual)
	
	if name_cached:
		parameters.push_front(_play_remote_cached)
		GDSync.call_func_relevant.callv(parameters)
	else:
		if use_name:GDSync._request_processor.create_name_cache("", name)
		parameters.push_front(_play_remote)
		GDSync.call_func_relevant.callv(parameters)

func play_backwards_synced(name: StringName = &"") -> void:
	play_backwards(name)
	if !GDSync.is_active() or !_should_broadcast: return
	GDSync.call_func_relevant(_play_backwards_remote, name)

func set_frame_and_progress_synced(frame: int, progress: float) -> void:
	set_frame_and_progress(frame, progress)
	if !GDSync.is_active() or !_should_broadcast: return
	GDSync.call_func_relevant(_set_frame_and_progress_remote, frame, progress)

func stop_synced() -> void:
	stop()
	if !GDSync.is_active() or !_should_broadcast: return
	GDSync.call_func_relevant(_stop_remote)



#Private functions ----------------------------------------------------------------------

var GDSync

var _last_flip_h : bool
var _last_flip_v : bool
var _last_speed_scale : float
var _last_animation : StringName
var _should_broadcast : bool = false
var _last_owner : int = -1

func _ready() -> void:
	GDSync = get_node("/root/GDSync")
	
	GDSync.expose_func(_play_remote_cached)
	GDSync.expose_func(_play_remote)
	GDSync.expose_func(_play_backwards_remote)
	GDSync.expose_func(_set_frame_and_progress_remote)
	GDSync.expose_func(_stop_remote)
	GDSync.expose_func(_refresh_last_changes)
	
	GDSync.expose_var(self, "flip_h")
	GDSync.expose_var(self, "flip_v")
	GDSync.expose_var(self, "speed_scale")
	
	var timer : Timer = Timer.new()
	add_child(timer)
	timer.wait_time = 0.001
	timer.timeout.connect(_check_for_changes)
	timer.start()
	
	_last_owner = GDSync.get_gdsync_owner(self)
	GDSync.host_changed.connect(_host_changed)
	GDSync.client_joined.connect(_client_joined)
	GDSync.connect_gdsync_owner_changed(self, _owner_changed)
	
	_refresh_last_changes()
	_update_sync_mode()

func _multiplayer_ready() -> void:
	_refresh_last_changes()
	_update_sync_mode()

func _check_for_changes() -> void:
	if !_has_changed():
		return
	if _should_broadcast:
		_refresh_last_changes()
		play_synced(animation)
		GDSync.sync_var_relevant(self, "flip_h")
		GDSync.sync_var_relevant(self, "flip_v")
		GDSync.sync_var_relevant(self, "speed_scale")
		GDSync.call_func_relevant(_refresh_last_changes)
	else:
		_refresh_last_changes()

func _refresh_last_changes() -> void:
	_last_flip_h = flip_h
	_last_flip_v = flip_v
	_last_speed_scale = speed_scale
	_last_animation = animation

func _has_changed() -> bool:
	return (
		_last_flip_h != flip_h or 
		_last_flip_v != flip_v or
		_last_speed_scale != speed_scale or
		_last_animation != animation
	)

func _play_remote_cached(name_index = 0, custom_speed : float = 1.0, from_end : bool = false) -> void:
	if !GDSync._session_controller.has_name_from_index(name_index): return
	_play_remote(GDSync._session_controller.get_name_from_index(name_index), custom_speed, from_end)

func _play_remote(name : StringName = &"", custom_speed : float = 1.0, from_end : bool = false) -> void:
	play(name, custom_speed, from_end)

func _play_backwards_remote(name : StringName = &"") -> void:
	play_backwards(name)

func _set_frame_and_progress_remote(frame : int, progress : float) -> void:
	set_frame_and_progress(frame, progress)

func _stop_remote() -> void:
	stop()

func _owner_changed(owner) -> void:
	if owner >= 0:
		_last_owner = owner
	_update_sync_mode()

func _client_joined(_client_id : int) -> void:
	_update_sync_mode()

func _interest_object_client_entered(client_id : int) -> void:
	if !_should_broadcast:
		return
	GDSync.sync_var_on(client_id, self, "flip_h")
	GDSync.sync_var_on(client_id, self, "flip_v")
	GDSync.sync_var_on(client_id, self, "speed_scale")
	if is_playing():
		GDSync.call_func_on(client_id, _play_remote, animation, speed_scale, false)
		GDSync.call_func_on(client_id, _set_frame_and_progress_remote, frame, frame_progress)
	else:
		GDSync.call_func_on(client_id, _stop_remote)

func _host_changed(_is_host : bool, _new_host_id : int) -> void:
	_update_sync_mode()

func _update_sync_mode() -> void:
	if GDSync == null or !GDSync.is_active():
		return
	var is_host : bool = GDSync.is_host()
	var valid_owner : bool = GDSync.lobby_get_all_clients().has(_last_owner)
	_should_broadcast = (is_host and !valid_owner) || (valid_owner and _last_owner == GDSync.get_client_id())
