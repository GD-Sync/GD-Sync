@tool
extends Node

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

func instantiate_node() -> Node:
	var node : Node = scene.instantiate()
	var id : int = _assign_instance_id(node)
	node.name = str(id)
	
	if target_location:
		target_location.add_child(node)
	else:
		add_child(node)
	
	_send_remote_instantiate.call_deferred(node, _get_properties_as_bytes(node))
	_call_multiplayer_ready(node)
	node_instantiated.emit(node)
	return node





#Private functions ----------------------------------------------------------------------

enum SPAWN_TYPE {
	NODEPATH,
	SCENE_ROOT
}

signal node_instantiated(node : Node)

@export var spawn_type : SPAWN_TYPE = SPAWN_TYPE.NODEPATH : set = _set_spawn_type
var target_location : Node
var scene : PackedScene
var sync_starting_changes : bool = true

const EXCLUDED_PROPERTIES : PackedStringArray = [
	"position",
	"rotation",
	"scale"
]

var GDSync

var rng : RandomNumberGenerator = RandomNumberGenerator.new()
var node_id_list : Dictionary = {}

func _ready():
	if Engine.is_editor_hint(): return
	GDSync = get_node("/root/GDSync")
	GDSync.expose_func(_instance_remote)
	rng.randomize()
	
	if spawn_type == SPAWN_TYPE.SCENE_ROOT:
		target_location = get_tree().current_scene

func _call_multiplayer_ready(node : Node):
	await get_tree().process_frame
	node.propagate_call("_multiplayer_ready")

func _get_random_id() -> int:
	var id : int = rng.randi()
	if node_id_list.has(id):
		return _get_random_id()
	return id

func _assign_instance_id(node : Node) -> int:
	var id : int = _get_random_id()
	node_id_list[id] = node
	node.set_meta("GDID", id)
	_await_id_deletion(node)
	return id

func _remove_node_id(id : int):
	if node_id_list.has(id):
		node_id_list.erase(id)

func _await_id_deletion(node : Node):
	await node.tree_exiting
	_remove_node_id(node.get_meta("GDID"))

func _send_remote_instantiate(node : Node, starting_properties : Dictionary):
	var start : float = Time.get_ticks_msec()
	var changed_properties : Dictionary = {}
	
	if sync_starting_changes:
		var new_properties : Dictionary = _get_properties_as_bytes(node)
		for name in starting_properties:
			if new_properties[name] != starting_properties[name]:
				var new_value = bytes_to_var(new_properties[name])
				var type : int = typeof(new_value)
				match(type):
					TYPE_OBJECT: continue
					TYPE_CALLABLE: continue
					TYPE_SIGNAL: continue
					TYPE_RID: continue
				if EXCLUDED_PROPERTIES.has(name): continue
				changed_properties[name] = new_value
	
	GDSync.call_func(_instance_remote, [node.get_meta("GDID"), changed_properties])

func _instance_remote(id : int, changed_properties : Dictionary):
	var node : Node = scene.instantiate()
	node_id_list[id] = node
	node.set_meta("GDID", id)
	_await_id_deletion(node)
	node.name = str(id)
	
	if target_location:
		target_location.add_child(node)
	else:
		add_child(node)
	
	for name in changed_properties:
		node.set(name, changed_properties[name])
	
	node.propagate_call("_multiplayer_ready")
	node_instantiated.emit(node)

func _get_properties_as_bytes(node : Node) -> Dictionary:
	var property_values : Dictionary = {}
	for property in node.get_property_list():
		property_values[property["name"]] = var_to_bytes(node.get(property["name"]))
	
	return property_values

func _set_spawn_type(t : int):
	spawn_type = t
	notify_property_list_changed()

func _get_property_list():
	var properties : Array = []
	
	properties.append({
		"name" : "target_location",
		"type" : TYPE_NODE_PATH,
		"usage" : PROPERTY_USAGE_DEFAULT if spawn_type == SPAWN_TYPE.NODEPATH else PROPERTY_USAGE_NO_EDITOR 
	})
	
	properties.append({
		"name" : "scene",
		"type" : TYPE_OBJECT,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string" : "PackedScene" 
	})
	
	properties.append({
		"name" : "sync_starting_changes",
		"type" : TYPE_BOOL,
		"usage" : PROPERTY_USAGE_DEFAULT
	})
	
	return properties
