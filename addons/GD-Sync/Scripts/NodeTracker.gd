extends Node

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

var INSTANTIATOR_SCENE : GDScript = load("res://addons/GD-Sync/Scripts/Types/NodeInstantiator.gd")

var GDSync
var request_processor
var logger

var replication_cache : Dictionary = {}
var replication_settings : Dictionary = {}
var root_instantiator
var instantiator_regex : RegEx

var instantiator_lib : Dictionary = {}

var lobby_i : int = 0

func _ready() -> void:
	name = "NodeTracker"
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	logger = GDSync._logger
	
	root_instantiator = INSTANTIATOR_SCENE.new()
	root_instantiator.spawn_type = 1
	root_instantiator.name = "RootInstantiator"
	add_child(root_instantiator)
	
	instantiator_regex = RegEx.new()
	instantiator_regex.compile("[^a-z0-9]")
	
	GDSync.expose_func(replicate_remote)
	GDSync.expose_func(create_instantiator_remote)
	GDSync.expose_func(multiplayer_queue_free_remote)
	GDSync.client_joined.connect(client_joined)

func lobby_left() -> void:
	lobby_i += 1
	
	for instantiator in instantiator_lib.values():
		if is_instance_valid(instantiator):
			instantiator.queue_free()
	
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
	
	logger.write_log("Creating remote replication requests. <"+str(client_id)+"><"+str(instantiator_path)+"><"+str(settings)+">", "[NodeTracker]")
	
	var sync_starting_changes : bool = settings[ENUMS.NODE_REPLICATION_SETTINGS.SYNC_STARTING_CHANGES]
	var original_properties : Dictionary = settings[ENUMS.NODE_REPLICATION_SETTINGS.ORIGINAL_PROPERTIES]
	var excluded_properties : PackedStringArray = settings[ENUMS.NODE_REPLICATION_SETTINGS.EXCLUDED_PROPERTIES]
	
	var replication_data : Array = []
	
	var replication_counter : int = 0
	while nodes_to_replicate.size() > 0 and replication_counter < 32:
		var node : Node = nodes_to_replicate.pop_front()
		replication_counter += 1
		if !is_instance_valid(node):
			logger.write_error("Failed to create remote replication request, Node was invalid. <"+str(client_id)+"><"+str(instantiator_path)+">", "[NodeTracker]")
			continue
		if !node.is_inside_tree():
			logger.write_error("Failed to create remote replication request, Node is not inside the tree. <"+str(client_id)+"><"+str(instantiator_path)+">", "[NodeTracker]")
			continue
		
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
	
	var tries : int = 0
	var current_lobby_i : int = lobby_i
	while target == null:
		tries += 1
		await get_tree().create_timer(0.6).timeout
		logger.write_error("Remote replication failed, target Node was not found. Trying again. <"+str(settings)+">", "[NodeTracker]")
		target = get_node_or_null(settings[ENUMS.NODE_REPLICATION_SETTINGS.TARGET])
		
		if tries >= 100:
			logger.write_error("Remote replication failed, target Node was not found. <"+str(settings)+">", "[NodeTracker]")
			return
	
	if current_lobby_i != lobby_i:
		return
	
	if instantiator == null:
		logger.write_log("Remote replication did not find the target Instantiator, falling back to the root Instantiator. <"+str(settings)+">", "[NodeTracker]")
		var scene : PackedScene = load(settings[ENUMS.NODE_REPLICATION_SETTINGS.SCENE])
		root_instantiator.scene = scene
		root_instantiator.target = target
		root_instantiator.replicate_settings = settings
		instantiator = root_instantiator
	
	logger.write_log("Replicating Nodes. <"+str(settings)+"><"+str(replication_data)+">", "[NodeTracker]")
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
	
	logger.write_log("Multiplayer Instantiate. <"+settings_key+">", "[NodeTracker]")
	
	var instantiator : Node
	if !instantiator_lib.has(settings_key):
		logger.write_log("Creating Instantiator.", "[NodeTracker]")
		instantiator = INSTANTIATOR_SCENE.new()
		instantiator.name = instantiator_regex.sub(scene.resource_path.to_lower(), "", true)
		instantiator.spawn_type = 1
		instantiator.scene = scene
		instantiator.sync_starting_changes = sync_starting_changes
		instantiator.excluded_properties = excluded_properties
		instantiator.replicate_on_join = replicate_on_join
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
		logger.write_log("Using existing Instantiator.", "[NodeTracker]")
	
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
		logger.write_error("Failed to create remote Instaniator, invalid scene path. <"+scene_path+">", "[NodeTracker]")
		push_error("Remote instantiate failed, invalid scene path.")
		return
	
	var tries : int = 0
	var current_lobby_i : int = lobby_i
	while parent == null:
		tries += 1
		await get_tree().create_timer(0.6).timeout
		logger.write_error("Failed to create remote Instantiator, parent Node not found. Trying again. <"+str(parent_path)+">", "[NodeTracker]")
		
		if tries >= 100:
			logger.write_error("Failed to create remote Instantiator, parent Node not found. <"+str(parent_path)+">", "[NodeTracker]")
			return
	
	if current_lobby_i != lobby_i:
		return
	
	var settings_key : StringName = StringName(
		str(scene_path, sync_starting_changes, excluded_properties, replicate_on_join
	))
	
	logger.write_log("Created remote Instaniator. <"+settings_key+">", "[NodeTracker]")
	
	if !instantiator_lib.has(settings_key):
		var instantiator : Node = INSTANTIATOR_SCENE.new()
		instantiator.name = instantiator_regex.sub(scene_path.to_lower(), "", true)
		instantiator.spawn_type = 1
		instantiator.scene = scene
		instantiator.sync_starting_changes = sync_starting_changes
		instantiator.excluded_properties = excluded_properties
		instantiator.replicate_on_join = replicate_on_join
		add_child(instantiator)
		
		instantiator.target = parent
		instantiator.target_path = str(parent.get_path())
		
		instantiator_lib[settings_key] = instantiator

func multiplayer_queue_free(node : Node) -> void:
	if !is_instance_valid(node) || !node.is_inside_tree(): return
	node.queue_free()
	
	logger.write_log("Creating remote free request. <"+str(node.get_path())+">", "[NodeTracker]")
	GDSync.call_func(multiplayer_queue_free_remote, [node.get_path()])

func multiplayer_queue_free_remote(node_path : NodePath) -> void:
	var node : Node = get_node_or_null(node_path)
	if node == null:
		logger.write_error("Failed to remotely free, Node not found. <"+str(node_path)+">", "[NodeTracker]")
		return
	
	logger.write_log("Remotely freed Node. <"+str(node_path)+">", "[NodeTracker]")
	node.queue_free()
