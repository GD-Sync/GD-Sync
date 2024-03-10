extends Node

var GDSync
var request_processor

var replication_cache : Dictionary = {}
var replication_settings : Dictionary = {}
var root_instantiator

func _ready() -> void:
	name = "SessionController"
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	
	root_instantiator = load("res://addons/GD-Sync/Scripts/Types/NodeInstantiator.gd").new()
	root_instantiator.spawn_type = 1
	add_child(root_instantiator)
	
	GDSync.expose_func(replicate_remote)
	GDSync.client_joined.connect(client_joined)

func client_joined(client_id : int) -> void:
	if client_id == GDSync.get_client_id(): return
	if !GDSync.is_host(): return
	broadcast_replication(client_id)

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

