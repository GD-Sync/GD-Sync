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

signal scene_ready

var request_processor
var GDSync

var current_client_id : int = -1
var sender_id : int = -1
var player_data : Dictionary = {}
var lobby_data : Dictionary = {}

var node_path_cache : Dictionary = {}
var node_path_index_cache : Dictionary = {}
var name_cache : Dictionary = {}
var name_index_cache : Dictionary = {}
var resource_reference_cache : Dictionary = {}
var reference_resource_cache : Dictionary = {}

var owner_cache : Dictionary = {}

var lobby_name : String = ""
var lobby_password : String = ""
var own_lobby : bool = false
var connect_time : float = 0
var lobby_switch_pending : bool = false

var synced_time : float = 0.0
var remote_time : float = 0.0
var remote_time_counter : int = 0
var remote_time_latency : float = 0.0
var synced_time_cooldown : float = 0.0
var events : Array[Dictionary] = []

var active_scene_change : String = ""
var scene_ready_list : Array[int] = []

func _ready() -> void:
	name = "SessionController"
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	
	GDSync.expose_func(sync_timer)
	GDSync.expose_func(get_timer_latency)
	GDSync.expose_func(timer_latency_callback)
	GDSync.expose_func(register_event)
	GDSync.expose_func(load_scene)
	GDSync.expose_func(mark_scene_ready)
	GDSync.expose_func(switch_scene_success)
	GDSync.expose_func(switch_scene_failed)
	
	GDSync.client_joined.connect(client_joined)
	GDSync.client_left.connect(client_left)
	GDSync.client_id_changed.connect(client_id_changed)
	
	randomize()
	synced_time = randf_range(0, 1000)

func _process(delta):
	if !GDSync.is_active(): return
	handle_events(delta)

func handle_events(delta : float) -> void:
	synced_time += delta
	remote_time += delta
	
	for event in events:
		if synced_time >= event["Time"]:
			GDSync.synced_event_triggered.emit(event["Name"], event["Parameters"])
			events.erase(event)
	
	if !GDSync.is_active() || !GDSync.is_host(): return
	
	synced_time_cooldown -= delta
	if synced_time_cooldown <= 0.0:
		synced_time_cooldown = 5.0
		GDSync.call_func(sync_timer, [synced_time])

func sync_timer(time : float) -> void:
	remote_time = time
	remote_time_counter = 0
	remote_time_latency = 0.0
	
	if(abs(time - synced_time) > 0.5): synced_time = remote_time
	
	for i in range(5):
		await get_tree().process_frame
		GDSync.call_func_on(GDSync.get_host(), get_timer_latency, [GDSync.get_client_id(), Time.get_unix_time_from_system()])

func get_timer_latency(client : int, timestamp : float) -> void:
	GDSync.call_func_on(client, timer_latency_callback, [timestamp])

func timer_latency_callback(timestamp : float) -> void:
	remote_time_counter += 1
	remote_time_latency += (Time.get_unix_time_from_system()-timestamp)/2.0
	
	if remote_time_counter >= 5:
		synced_time = remote_time + remote_time_latency/remote_time_counter

func register_event(event_name : String, time : float, parameters : Array, local : bool = false) -> void:
	events.append({
		"Name" : event_name,
		"Time" : time,
		"Parameters" : parameters
	})
	
	if local:
		GDSync.call_func(register_event, [event_name, time, parameters])

func client_id_changed(client_id : int) -> void:
	var own_data = null
	if player_data.has(current_client_id):
		own_data = player_data[current_client_id]
		player_data.erase(current_client_id)
	else:
		own_data = {
			"ID" : client_id,
			"Username" : ""
		}
	
	current_client_id = client_id
	player_data[client_id] = own_data

func broadcast_player_data() -> void:
	var own_id : int = GDSync.get_client_id()
	GDSync.player_set_username(get_player_data(own_id, "Username", ""))
	
	var own_data : Dictionary = GDSync.player_get_all_data(own_id)
	for key in own_data:
		if key != "Username":
			GDSync.player_set_data(key, own_data[key])

func set_lobby_data(name : String, password : String) -> void:
	synced_time = 0.0
	lobby_name = name
	lobby_password = password

func lobby_created() -> void:
	own_lobby = true

func lobby_left() -> void:
	var own_id = GDSync.get_client_id()
	
	lobby_data.clear()
	node_path_cache.clear()
	node_path_index_cache.clear()
	name_cache.clear()
	name_index_cache.clear()
	owner_cache.clear()
	events.clear()
	sender_id = -1
	
	lobby_name = ""
	lobby_password = ""
	own_lobby = false
	
	synced_time = 0.0
	
	for id in player_data.keys():
		if id != own_id:
			player_data.erase(id)

func client_joined(client_id : int) -> void:
	if client_id == GDSync.get_client_id(): return
	
	if GDSync.is_host():
		synced_time_cooldown = 0.0
		
		for event in events:
			GDSync.call_func_on(client_id, register_event, [
				event["Name"],
				event["Time"],
				event["Parameters"]
			])
		
		if active_scene_change != "":
			GDSync.call_func(load_scene, [active_scene_change])

func client_left(id : int) -> void:
	if player_data.has(id): player_data.erase(id)

func get_all_clients() -> Array:
	return player_data.keys()

func set_sender_id(id : int) -> void:
	sender_id = id

func get_sender_id() -> int:
	return sender_id

func nodepath_is_cached(node_path : String) -> bool:
	return node_path_cache.has(node_path)

func name_is_cached(name : String) -> bool:
	return name_cache.has(name)

func get_nodepath_index(node_path : String) -> int:
	return node_path_cache[node_path]

func get_name_index(name : String) -> int:
	return name_cache[name]

func get_nodepath_from_index(index : int) -> String:
	return node_path_index_cache[index]

func get_name_from_index(index : int) -> String:
	return name_index_cache[index]

func has_nodepath_from_index(index : int) -> bool:
	return node_path_index_cache.has(index)

func has_name_from_index(index : int) -> bool:
	return name_index_cache.has(index)

func cache_nodepath(node_path : String, index : int) -> void:
	if node_path_index_cache.has(index):
		var oldCachePath : String = node_path_index_cache[index]
		node_path_cache.erase(oldCachePath)
	
	node_path_cache[node_path] = index
	node_path_index_cache[index] = node_path
	
	var node : Node = get_node_or_null(node_path)
	if node:
		await node.tree_exiting
		await get_tree().process_frame
		await get_tree().process_frame
		request_processor.create_erase_nodepath_cache_request(index)

func erase_nodepath_cache(index : int) -> void:
	if node_path_index_cache.has(index):
		var node_path : String = node_path_index_cache[index]
		node_path_cache.erase(node_path)
		node_path_index_cache.erase(index)

func cache_name(name : String, index : int) -> void:
	if name_index_cache.has(index):
		var oldCachePath : String = name_index_cache[index]
		name_cache.erase(oldCachePath)
	
	name_cache[name] = index
	name_index_cache[index] = name

func erase_name_cache(index : int) -> void:
	if name_index_cache.has(index):
		var name : String = name_index_cache[index]
		name_cache.erase(name)
		name_index_cache.erase(index)

func create_resource_reference(resource : Resource, id : String) -> void:
	reference_resource_cache[id] = resource
	resource_reference_cache[resource] = id

func erase_resource_reference(resource : Resource) -> void:
	if resource_reference_cache.has(resource):
		var id : String = resource_reference_cache[resource]
		resource_reference_cache.erase(resource)
		reference_resource_cache.erase(id)

func has_resource_reference(resource : Resource) -> bool:
	print(resource_reference_cache)
	print(reference_resource_cache)
	return resource_reference_cache.has(resource)

func get_resource_reference(resource : Resource) -> String:
	return resource_reference_cache[resource]

func has_resource_by_reference(id : String) -> bool:
	return reference_resource_cache.has(id)

func get_resource_by_reference(id : String) -> Resource:
	return reference_resource_cache[id]

func set_player_data(key : String, value) -> void:
	player_data[GDSync.get_client_id()][key] = value
	player_data_changed(GDSync.get_client_id(), key)

func player_data_changed(client_id : int, key : String) -> void:
	if !player_data.has(client_id): return
	var data : Dictionary = player_data[client_id]
	if data.has(key):
		GDSync.player_data_changed.emit(client_id, key, data[key])
	else:
		GDSync.player_data_changed.emit(client_id, key, null)

func erase_player_data(key : String) -> void:
	if player_data[GDSync.get_client_id()].has(key):
		player_data[GDSync.get_client_id()].erase(key)
		player_data_changed(GDSync.get_client_id(), key)

func get_player_data(client_id : int, key : String, default):
	if player_data.has(client_id):
		var data : Dictionary = player_data[client_id]
		if data.has(key):
			return data[key]
	return default

func get_all_player_data(client_id : int) -> Dictionary:
	if player_data.has(client_id):
		var data : Dictionary = player_data[client_id]
		return data
	return {}

func override_player_data(data : Dictionary) -> void:
	var id = data["ID"]
	data.erase(id)
	if player_data.has(id):
		player_data[id].clear()
	else:
		player_data[id] = {}
	
	for key in data:
		player_data[id][key] = data[key]

func override_lobby_data(data : Dictionary) -> void:
	lobby_data = data

func get_player_limit() -> int:
	if !lobby_data.has("PlayerLimit"): return 0
	return lobby_data["PlayerLimit"]

func lobby_has_password() -> bool:
	if lobby_data.has("HasPassword"):
		return lobby_data["HasPassword"]
	return false

func lobby_data_changed(key : String) -> void:
	if !lobby_data.has("Data"): return
	var data : Dictionary = lobby_data["Data"]
	if !data.has(key):
		GDSync.lobby_data_changed.emit(key, null)
	else:
		GDSync.lobby_data_changed.emit(key, data[key])

func lobby_tags_changed(key : String) -> void:
	if !lobby_data.has("Tags"): return
	var tags : Dictionary = lobby_data["Tags"]
	if !tags.has(key):
		GDSync.lobby_tag_changed.emit(key, null)
	else:
		GDSync.lobby_tag_changed.emit(key, tags[key])

func has_lobby_data(key : String) -> bool:
	if !lobby_data.has("Data"): return false
	var data : Dictionary = lobby_data["Data"]
	return data.has(key)

func has_lobby_tag(key : String) -> bool:
	if !lobby_data.has("Tags"): return false
	var tags : Dictionary = lobby_data["Tags"]
	return tags.has(key)

func get_lobby_data(key : String, default):
	if !lobby_data.has("Data"): return
	var data : Dictionary = lobby_data["Data"]
	if !data.has(key):
		return default
	else:
		return data[key]

func get_lobby_tag(key : String, default):
	if !lobby_data.has("Tags"): return
	var tags : Dictionary = lobby_data["Tags"]
	if !tags.has(key):
		return default
	else:
		return tags[key]

func get_all_lobby_data() -> Dictionary:
	if lobby_data.has("Data"):
		return lobby_data["Data"]
	else:
		return {}

func get_all_lobby_tags() -> Dictionary:
	if lobby_data.has("Tags"):
		return lobby_data["Tags"]
	else:
		return {}

func expose_object(object : Object) -> void:
	object.set_meta("Exposed", true)

func hide_object(object : Object) -> void:
	object.set_meta("Exposed", false)

func object_is_exposed(object : Object) -> bool:
	return object.get_meta("Exposed", false)

func expose_func(function : Callable) -> void:
	var object : Object = function.get_object()
	var functionName : String = function.get_method()
	var exposedArray : Array = object.get_meta("ExposedFunctions", [])
	exposedArray.append(functionName)
	object.set_meta("ExposedFunctions", exposedArray)

func hide_function(function : Callable) -> void:
	var object : Object = function.get_object()
	var functionName : String = function.get_method()
	var exposedArray : Array = object.get_meta("ExposedFunctions", [])
	if exposedArray.has(functionName): exposedArray.erase(functionName)

func function_is_exposed(object : Object, function_name : String) -> bool:
	var exposedArray : Array = object.get_meta("ExposedFunctions", [])
	return exposedArray.has(function_name)

func expose_property(object : Object, property_name : String) -> void:
	var exposedArray : Array = object.get_meta("ExposedProperties", [])
	exposedArray.append(property_name)
	object.set_meta("ExposedProperties", exposedArray)

func hide_property(object : Object, propertyName : String) -> void:
	var exposedArray : Array = object.get_meta("ExposedProperties", [])
	if exposedArray.has(propertyName): exposedArray.erase(propertyName)

func property_is_exposed(object : Object, propertyName : String) -> bool:
	var exposedArray : Array = object.get_meta("ExposedProperties", [])
	return exposedArray.has(propertyName)

func set_gdsync_owner(node : Node, owner) -> void:
	set_mc_owner_remote(node, owner)
	request_processor.set_gdsync_owner(node, owner)

func set_mc_owner_remote(node : Node, owner) -> void:
	var path_string : String = str(node.get_path())
	if owner_cache.has(path_string): owner_cache.erase(path_string)
	
	node.set_meta("mcOwner", owner)
	emit_mc_owner_changed(node, owner)

func set_mc_owner_delayed(node_path : String, owner) -> void:
	owner_cache[node_path] = owner
	
	await get_tree().process_frame
	
	set_from_owner_cache(node_path)

func set_from_owner_cache(node_path : String) -> void:
	if !owner_cache.has(node_path): return
	var owner = owner_cache[node_path]
	var node : Node = get_node_or_null(node_path)
	owner_cache.erase(node_path)
	if node == null: return
	set_mc_owner_remote(node, owner)

func emit_mc_owner_changed(node : Node, owner) -> void:
	if node.has_user_signal("mc_owner_changed"): node.emit_signal("mc_owner_changed", owner)
	for child in node.get_children():
		emit_mc_owner_changed(child, owner)

func get_gdsync_owner(node : Node) -> int:
	var path_string : String = str(node.get_path())
	if owner_cache.has(path_string):
		set_mc_owner_remote(node, owner_cache[path_string])
	
	var ownerID : int = -1
	var p : Node = node
	while p != null and ownerID < 0:
		if p.has_meta("mcOwner"):
			var id = p.get_meta("mcOwner", null)
			if id != null: ownerID = id
		p = p.get_parent()
	return ownerID

func is_gdsync_owner(node : Node) -> bool:
	return get_gdsync_owner(node) == GDSync.get_client_id()

func connect_gdsync_owner_changed(node : Node, callable : Callable) -> void:
	if !node.has_user_signal("mc_owner_changed"):
		node.add_user_signal("mc_owner_changed", ["owner"])
	node.connect("mc_owner_changed", callable)

func disconnect_gdsync_owner_changed(node : Node, callable : Callable) -> void:
	node.disconnect("mc_owner_changed", callable)

func change_scene(scene_path : String) -> void:
	GDSync.call_func(load_scene, [scene_path])
	load_scene(scene_path)

func load_scene(scene_path : String) -> void:
	if active_scene_change != "":
		push_error("Another scene change is already in progress.")
		return
	
	scene_ready_list.clear()
	active_scene_change = scene_path
	GDSync.change_scene_called.emit(scene_path)
	
	var tree : SceneTree = get_tree()
	var packed_scene : PackedScene = await load_resource_threaded(tree, scene_path)
	var new_scene : Node = await instantiate_threaded(tree, packed_scene)
	var old_scene : Node = tree.current_scene
	
	if new_scene == null:
		GDSync.call_func(switch_scene_failed)
		switch_scene_failed()
		return
	
	var own_id : int = GDSync.get_client_id()
	GDSync.call_func(mark_scene_ready, [own_id])
	mark_scene_ready(own_id)
	
	await scene_ready
	if scene_path != active_scene_change: return
	
	new_scene.tree_entered.connect(
		func set_current_scene() -> void:
			tree.current_scene = new_scene
	)
	
	tree.root.add_child(new_scene)
	tree.root.remove_child(old_scene)
	old_scene.free()
	
	tree.current_scene = new_scene
	
	active_scene_change = ""

func mark_scene_ready(client_id : int) -> void:
	scene_ready_list.append(client_id)
	
	if GDSync.is_host():
		var clients : Array = get_all_clients()
		
		for client in scene_ready_list:
			if clients.has(client): clients.erase(client)
		
		if clients.size() == 0:
			GDSync.call_func(switch_scene_success)
			switch_scene_success()

func switch_scene_success() -> void:
	scene_ready_list.clear()
	GDSync.change_scene_success.emit(active_scene_change)
	scene_ready.emit.call_deferred()

func switch_scene_failed() -> void:
	scene_ready_list.clear()
	GDSync.change_scene_failed.emit(active_scene_change)
	active_scene_change = ""

func load_resource_threaded(tree : SceneTree, path : String) -> Resource:
	if ResourceLoader.load_threaded_request(path) == OK:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
			await tree.create_timer(0.05).timeout
		
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path)
	
	return null

func instantiate_threaded(tree : SceneTree, packed_scene : PackedScene) -> Node:
	if packed_scene == null: return null
	
	var thread : Thread = Thread.new()
	
	var callable : Callable = func instantiate(packed_scene : PackedScene):
		return packed_scene.instantiate()
	
	thread.start(
		callable.bind(packed_scene)
	)
	
	while thread.is_alive():
		await tree.create_timer(0.02).timeout
	
	return thread.wait_to_finish()
