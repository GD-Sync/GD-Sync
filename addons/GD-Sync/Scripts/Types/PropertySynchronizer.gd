@tool
extends Node
class_name PropertySynchronizer

#Copyright (c) 2023 Thomas Uijlen, GD-Sync.
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

func synchronize(forced : bool = true):
	var new_property = node.get(property_name)
	if !forced and new_property == _property: return
	_property = new_property
	GDSync.call_func(_sync_received, [_property], false)

func pause_interpolation(seconds : float):
	_pause_interpolation_remote(seconds)
	GDSync.call_func(_pause_interpolation_remote, [seconds])





#Private functions ----------------------------------------------------------------------

enum BROADCAST_MODE {
	WHEN_HOST,
	WHEN_CLIENT,
	WHEN_OWNER,
	WHEN_HOST_AND_NO_OWNER_OR_OWNER,
	ALWAYS,
	NEVER,
}

signal value_changed(new_value)

enum PROCESS_MODE {
	PROCESS,
	PHYSICS_PROCESS,
}

@export var broadcast: BROADCAST_MODE : set = _set_broadcast
@export var process : PROCESS_MODE
@export var refresh_rate : int = 30
@export var node_path : NodePath :
	set(value):
		node_path = value
		node = get_node_or_null(node_path)
		_refresh_property_list()
@export var property_name : String :
	set(value):
		property_name = value
		_refresh_property_list()
var interpolated : bool = false :
	set(value):
		interpolated = value
		notify_property_list_changed()

var GDSync

var interpolation_speed : float = 1.0

var node : Node
var _property

var _cooldown : float = 0.0
var _current_cooldown : float = 0.0
var _interval_cooldown : float = 0.0
var _should_broadcast : bool = false
var _type : int = -1

func _ready():
	node = get_node_or_null(node_path)
	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		_refresh_property_list()
	else:
		assert(node != null, "PropertySynchronizer Node is null")
		assert(property_name in node, "Node \""+node.name+"\" does not have property \""+property_name+ "\"")
		
		GDSync = get_node("/root/GDSync")
		
		_property = node.get(property_name)
		_type = typeof(_property)
		if interpolated and !_can_interpolate(): interpolated = false
		
		_cooldown = 1.0/refresh_rate
		GDSync.expose_func(_sync_received)
		GDSync.expose_func(_pause_interpolation_remote)
		GDSync.host_changed.connect(_host_changed)
		GDSync.client_joined.connect(_client_joined)
		GDSync.connect_gdsync_owner_changed(self, _owner_changed)
		_update_sync_mode()
		set_process(process == PROCESS_MODE.PROCESS)
		set_physics_process(process == PROCESS_MODE.PHYSICS_PROCESS)
		
		if interpolated:
			interpolated = false
			await value_changed
			interpolated = true

func _pause_interpolation_remote(seconds : float):
	interpolated = false
	await get_tree().create_timer(seconds).timeout
	interpolated = true

func _set_broadcast(mode : int):
	broadcast = mode
	_update_sync_mode()

func _owner_changed(owner):
	_update_sync_mode()

func _host_changed(is_host : bool, new_host_id : int):
	_update_sync_mode()

func _update_sync_mode():
	if Engine.is_editor_hint() || GDSync == null: return
	var is_host : bool = GDSync.is_host()
	var is_owner : bool = GDSync.is_gdsync_owner(self)
	match (broadcast):
		BROADCAST_MODE.WHEN_HOST:
			_should_broadcast = is_host
		BROADCAST_MODE.WHEN_CLIENT:
			_should_broadcast = !is_host
		BROADCAST_MODE.WHEN_OWNER:
			_should_broadcast = is_owner
		BROADCAST_MODE.WHEN_HOST_AND_NO_OWNER_OR_OWNER:
			_should_broadcast = (is_host and GDSync.get_gdsync_owner(self) == null) || is_owner
		BROADCAST_MODE.ALWAYS:
			_should_broadcast = true
		BROADCAST_MODE.NEVER:
			_should_broadcast = false

func _process(delta):
	if !GDSync.is_active(): return
	if _should_broadcast:
		if _may_synchronize(delta): synchronize(false)
	else:
		if interpolated: _interpolate(delta)

func _physics_process(delta):
	if !GDSync.is_active(): return
	if _should_broadcast:
		if _may_synchronize(delta):
			synchronize(false)
		elif _may_interval_synchronize(delta):
			synchronize()
	else:
		if interpolated: _interpolate(delta)

func _may_synchronize(delta) -> bool:
	_current_cooldown -= delta
	if _current_cooldown <= 0:
		_current_cooldown += _cooldown
		return true
	return false

func _may_interval_synchronize(delta) -> bool:
	_interval_cooldown -= delta
	if _interval_cooldown <= 0:
		_interval_cooldown = 10.0
		return true
	return false

func _client_joined(clientID):
	synchronize()

func _sync_received(new_value):
	_property = new_value
	if !interpolated:
		node.set(property_name, _property)
		value_changed.emit(_property)

func _interpolate(delta):
	var current_value = node.get(property_name)
	
	if _type == TYPE_BASIS:
		current_value = current_value.orthonormalized()
		_property = _property.orthonormalized()
	
	var lerped_value = lerp(current_value, _property, delta*interpolation_speed)
	node.set(property_name, lerped_value)
	value_changed.emit(lerped_value)

func _can_interpolate() -> bool:
	if node == null: return false
	var propertyList : Array = node.get_property_list()
	if node.get_script() != null: propertyList.append_array(node.get_script().get_script_property_list())
	
	var property_type : int = -1
	
	for node_property in propertyList:
		if node_property["name"] == property_name:
			property_type = node_property["type"]
			break
	
	return (property_type == TYPE_INT
		|| property_type == TYPE_FLOAT
		|| property_type == TYPE_VECTOR2
		|| property_type == TYPE_VECTOR3
		|| property_type == TYPE_VECTOR4
		|| property_type == TYPE_COLOR
		|| property_type == TYPE_QUATERNION
		|| property_type == TYPE_BASIS)

var _may_interpolate : bool = false
func _refresh_property_list():
	var can_interpolate : bool = _can_interpolate()
	if _may_interpolate != _can_interpolate():
		_may_interpolate = can_interpolate
		notify_property_list_changed()

func _get_property_list():
	var properties : Array = []
	
	var can_interpolate : bool = _can_interpolate()
	
	properties.append({
		"name" : "interpolation",
		"type" : TYPE_BOOL,
		"usage" : PROPERTY_USAGE_GROUP if can_interpolate else PROPERTY_USAGE_NO_EDITOR 
	})
	
	properties.append({
		"name" : "interpolated",
		"type" : TYPE_BOOL,
		"usage" : PROPERTY_USAGE_DEFAULT if can_interpolate else PROPERTY_USAGE_NO_EDITOR 
	})
	
	properties.append({
		"name" : "interpolation_speed",
		"type" : TYPE_FLOAT,
		"usage" : PROPERTY_USAGE_DEFAULT if interpolated and can_interpolate else PROPERTY_USAGE_NO_EDITOR 
	})
	
	return properties
