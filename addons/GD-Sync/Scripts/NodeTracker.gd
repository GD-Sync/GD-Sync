extends Node

#Copyright (c) 2025 GD-Sync.
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

var INSTANTIATOR_SCENE : GDScript = load("res://addons/GD-Sync/Scripts/Types/NodeInstantiator.gd")

var GDSync
var request_processor

var replication_cache : Dictionary = {}
var replication_settings : Dictionary = {}
var root_instantiator

var instantiator_lib : Dictionary = {}

func _ready() -> void:
	name = "SessionController"
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	
	root_instantiator = INSTANTIATOR_SCENE.new()
	root_instantiator.spawn_type = 1
	add_child(root_instantiator)
	
	GDSync.expose_func(replicate_remote)
	GDSync.expose_func(create_instantiator_remote)
	GDSync.client_joined.connect(client_joined)

func lobby_left() -> void:
	instantiator_lib.clear()
	replication_cache.clear()
	replication_settings.clear()

func client_joined(client_id : int) -> void:
	if client_id == GDSync.get_client_id(): return
	if !GDSync.is_host(): return
	create_instantiators(client_id)
	broadcast_replication(client_id)

func create_instantiators(client_id : int) -> void:
	for settings_key in instantiator_lib:
		var instantiator = instantiator_lib[settings_key]
		GDSync.call_func_on(client_id, create_instantiator_remote, [
			instantiator.scene.resource_path,
			str(instantiator.target.get_path()),
			instantiator.sync_starting_changes,
			instantiator.excluded_properties,
			instantiator.replicate_on_join
		])

func broadcast_replication(client_id : int) -> void:
	for instantiator_path in replication_cache:
		var nodes_to_replicate : Array = replication_cache[instantiator_path].duplicate()
		
		while nodes_to_replicate.size() > 0:
			create_replication_requests(client_id, instantiator_path, nodes_to_replicate)

func create_replication_requests(client_id : int, instantiator_path : String, nodes_to_replicate : Array) -> void:
	var settings : Array = replication_settings[instantiator_path]
	
	var sync_starting_changes : bool = settings[ENUMS.NODE_REPLICATION_SETTINGS.SYNC_STARTING_CHANGES]
	var original_properties : Dictionary = settings[ENUMS.NODE_REPLICATION_SETTINGS.ORIGINAL_PROPERTIES]
	var excluded_properties : PackedStringArray = settings[ENUMS.NODE_REPLICATION_SETTINGS.EXCLUDED_PROPERTIES]
	
	var replication_data : Array = []
	
	var replication_counter : int = 0
	while nodes_to_replicate.size() > 0 and replication_counter < 32:
		var node : Node = nodes_to_replicate.pop_front()
		replication_counter += 1
		if !is_instance_valid(node): continue
		if !node.is_inside_tree(): continue
		
		var id : int = node.get_meta("GDID")
		var changed_properties : Dictionary = {}
		
		if sync_starting_changes:
			var starting_properties : Dictionary = original_properties
			var new_properties : Dictionary = root_instantiator._get_properties_as_bytes(node)
			
			for property_name in starting_properties:
				if new_properties[property_name] != starting_properties[property_name]:
					var new_value = bytes_to_var(new_properties[property_name])
					var type : int = typeof(new_value)
					match(type):
						TYPE_OBJECT: continue
						TYPE_CALLABLE: continue
						TYPE_SIGNAL: continue
						TYPE_RID: continue
					if root_instantiator._PERMANENT_EXCLUDED_PROPERTIES.has(property_name): continue
					if excluded_properties.has(property_name): continue
					if root_instantiator._contains_object(new_value): continue
					changed_properties[property_name] = new_value
		
		replication_data.append([id, changed_properties])
	
	GDSync.call_func_on(client_id, replicate_remote, [
		settings,
		replication_data
	])

func replicate_remote(settings : Array, replication_data : Array) -> void:
	var instantiator : Node = get_node_or_null(settings[ENUMS.NODE_REPLICATION_SETTINGS.INSTANTIATOR])
	var target : Node = get_node_or_null(settings[ENUMS.NODE_REPLICATION_SETTINGS.TARGET])
	
	if target == null: return
	if instantiator == null:
		var scene : PackedScene = load(settings[ENUMS.NODE_REPLICATION_SETTINGS.SCENE])
		root_instantiator.scene = scene
		root_instantiator.target = target
		root_instantiator.replicate_settings = settings
		instantiator = root_instantiator
	
	for node_replication_data in replication_data:
		instantiator._instantiate_remote(
			node_replication_data[ENUMS.NODE_REPLICATION_DATA.ID],
			node_replication_data[ENUMS.NODE_REPLICATION_DATA.CHANGED_PROPERTIES]
		)

func register_replication(node : Node, instantiator_path : String, settings : Array) -> void:
	if !replication_cache.has(instantiator_path):
		replication_cache[instantiator_path] = []
		replication_settings[instantiator_path] = settings
	
	replication_cache[instantiator_path].append(node)

func deregister_replication(node : Node) -> void:
	var instantiator_path : String = node.get_meta("Instantiator")
	if replication_cache.has(instantiator_path):
		replication_cache[instantiator_path].erase(node)

func multiplayer_instantiate(
		scene : PackedScene,
		parent : Node,
		sync_starting_changes : bool,
		excluded_properties : PackedStringArray,
		replicate_on_join : bool) -> Node:
	
	if parent == null:
		parent = get_tree().current_scene
	
	var settings_key : StringName = StringName(
		str(scene.resource_path, sync_starting_changes, excluded_properties, replicate_on_join
	))
	
	var instantiator : Node
	if !instantiator_lib.has(settings_key):
		instantiator = INSTANTIATOR_SCENE.new()
		instantiator.spawn_type = 1
		instantiator.scene = scene
		instantiator.sync_starting_changes = sync_starting_changes
		instantiator.excluded_properties = excluded_properties
		instantiator.replicate_on_join = replicate_on_join
		instantiator.name = settings_key
		add_child(instantiator)
		
		instantiator_lib[settings_key] = instantiator
		
		GDSync.call_func(create_instantiator_remote, [
			scene.resource_path,
			str(parent.get_path()),
			sync_starting_changes,
			excluded_properties,
			replicate_on_join
		])
	else:
		instantiator = instantiator_lib[settings_key]
	
	instantiator.target = parent
	instantiator.target_path = str(parent.get_path())
	
	GDSync.call_func(instantiator._set_target_remote, [instantiator.target_path])
	
	return instantiator.instantiate_node()

func create_instantiator_remote(
		scene_path : String,
		parent_path : NodePath,
		sync_starting_changes : bool,
		excluded_properties : PackedStringArray,
		replicate_on_join : bool
	) -> void:
	
	var scene : PackedScene = load(scene_path)
	var parent : Node = get_node_or_null(parent_path)
	
	if scene == null:
		push_error("Remote instantiate failed, invalid scene path.")
		return
	if parent == null:
		push_error("Remote instantiate failed, parent node not found")
		return
	
	var settings_key : StringName = StringName(
		str(scene_path, sync_starting_changes, excluded_properties, replicate_on_join
	))
	
	if !instantiator_lib.has(settings_key):
		var instantiator : Node = INSTANTIATOR_SCENE.new()
		instantiator.spawn_type = 1
		instantiator.scene = scene
		instantiator.sync_starting_changes = sync_starting_changes
		instantiator.excluded_properties = excluded_properties
		instantiator.replicate_on_join = replicate_on_join
		instantiator.name = settings_key
		add_child(instantiator)
		
		instantiator.target = parent
		instantiator.target_path = str(parent.get_path())
		
		instantiator_lib[settings_key] = instantiator
