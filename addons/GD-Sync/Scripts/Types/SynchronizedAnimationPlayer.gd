@icon("res://addons/GD-Sync/UI/Icons/SynchronizedAnimationPlayer.png")
extends AnimationPlayer
class_name SynchronizedAnimationPlayer

#Copyright (c) 2026 GD-Sync.
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

## If enabled, GD-Sync will attempt to synchronize the playback of animations across clients.
@export var sync_playback : bool = true

func play_synced(name: StringName = &"", custom_blend: float = -1, custom_speed: float = 1.0, from_end: bool = false) -> void:
	var send_remote_play : bool = !is_playing() || current_animation != name
	play(name, custom_blend, custom_speed, from_end)
	
	_playing_backwards = from_end
	_custom_speed = custom_speed
	
	if !GDSync.is_active(): return
	if !send_remote_play: return
	
	var use_name : bool = name.length() > 0
	var name_cached : bool = use_name and GDSync._session_controller.name_is_cached(name)
	var parameters : Array = []
	
	var defaults_flipped : Array = [false, 1.0, -1, null if name_cached else &""]
	var actual_values : Array = [
		from_end,
		custom_speed,
		custom_blend,
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
	
	parameters.push_front(GDSync.get_multiplayer_time())
	
	if name_cached:
		GDSync.call_func(_play_remote_cached, parameters)
	else:
		if use_name:GDSync._request_processor.create_name_cache("", name)
		GDSync.call_func(_play_remote, parameters)

func play_backwards_synced(name: StringName = &"", custom_blend: float = -1) -> void:
	self.play(name, custom_blend, -1.0, true)

func pause_synced() -> void:
	pause()
	if !GDSync.is_active(): return
	GDSync.call_func(_pause_remote)

func stop_synced(keep_state : bool = false) -> void:
	stop(keep_state)
	if !GDSync.is_active(): return
	GDSync.call_func(_stop_remote, [keep_state])

func queue_synced(name : StringName) -> void:
	queue(name)
	if !GDSync.is_active(): return
	GDSync.call_func(_queue_remote, [name])

func seek_synced(seconds : float, update : bool = false, update_only : bool = false) -> void:
	seek(seconds, update, update_only)
	if !GDSync.is_active(): return
	
	var parameters : Array = []
	
	var defaults_flipped : Array = [false, false]
	var actual_values : Array = [update_only, update]
	
	var include_all : bool = false
	for i in range(defaults_flipped.size()):
		var default = defaults_flipped[i]
		var actual = actual_values[i]
		if default != actual:
			include_all = true
		
		if include_all:
			parameters.push_front(actual)
	
	parameters.push_front(seconds)
	parameters.push_front(GDSync.get_multiplayer_time())
	GDSync.call_func(_seek_remote, parameters)

func advance_synced(delta : float) -> void:
	advance(delta)
	if !GDSync.is_active(): return
	GDSync.call_func(_advance_remote, [delta])







#Private functions ----------------------------------------------------------------------

var GDSync

var _playing_backwards : bool = false
var _custom_speed : float = 1.0

func _ready() -> void:
	GDSync = get_node("/root/GDSync")
	
	GDSync.expose_func(_play_remote)
	GDSync.expose_func(_play_remote_cached)
	GDSync.expose_func(_pause_remote)
	GDSync.expose_func(_stop_remote)
	GDSync.expose_func(_queue_remote)
	GDSync.expose_func(_seek_remote)
	GDSync.expose_func(_advance_remote)
	
	GDSync.client_joined.connect(_client_joined)

func _client_joined(client_id : int) -> void:
	if is_playing():
		GDSync.call_func_on(client_id, _stop_remote)
		
		GDSync.call_func_on(client_id, _play_remote, [
			GDSync.get_multiplayer_time(),
			current_animation,
			-1,
			_custom_speed,
			_playing_backwards
		])
		
		GDSync.call_func_on(client_id, _advance_remote, [current_animation_position/_custom_speed])

func _play_remote_cached(start_time : float = 0.0, name_index = 0, custom_blend : float = -1, custom_speed : float = 1.0, from_end : bool = false) -> void:
	if !GDSync._session_controller.has_name_from_index(name_index): return
	_play_remote(start_time, GDSync._session_controller.get_name_from_index(name_index), custom_blend, custom_speed, from_end)

func _play_remote(start_time : float = 0.0, name : StringName = &"", custom_blend : float = -1, custom_speed : float = 1.0, from_end : bool = false) -> void:
	play(name, custom_blend, custom_speed, from_end)
	
	if sync_playback:
		var time_passed : float = GDSync.get_multiplayer_time() - start_time
		if time_passed <= 0.5: advance(time_passed)

func _pause_remote() -> void:
	pause()

func _queue_remote(name : StringName) -> void:
	queue(name)

func _stop_remote(keep_state : bool = false) -> void:
	stop(keep_state)

func _seek_remote(start_time : float, seconds : float, update : bool = false, update_only : bool = false) -> void:
	seek(seconds, update, update_only)
	
	if sync_playback:
		var time_passed : float = GDSync.get_multiplayer_time() - start_time
		if time_passed < 0.5: advance(time_passed)

func _advance_remote(delta : float) -> void:
	advance(delta)
