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

var request_processor
var GDSync

var current_client_id : int = -1
var player_data : Dictionary = {}
var lobby_data : Dictionary = {}

var node_path_cache : Dictionary = {}
var node_path_index_cache : Dictionary = {}
var name_cache : Dictionary = {}
var name_index_cache : Dictionary = {}

var lobby_name : String = ""
var lobby_password : String = ""
var connect_time : float = 0
var lobby_switch_pending : bool = false

func _ready():
	name = "SessionController"
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	
	GDSync.client_left.connect(client_left)
	GDSync.client_id_changed.connect(client_id_changed)

func client_id_changed(client_id : int):
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

func broadcast_player_data():
	var own_id : int = GDSync.get_client_id()
	GDSync.set_player_username(get_player_data(own_id, "Username", ""))
	
	var own_data : Dictionary = GDSync.get_all_player_data(own_id)
	for key in own_data:
		if key != "Username":
			GDSync.set_player_data(key, own_data[key])

func set_lobby_data(name : String, password : String):
	lobby_name = name
	lobby_password = password

func lobby_left():
	var own_id = GDSync.get_client_id()
	
	lobby_data.clear()
	node_path_cache.clear()
	node_path_index_cache.clear()
	name_cache.clear()
	name_index_cache.clear()
	
	for id in player_data.keys():
		if id != own_id:
			player_data.erase(id)

func client_left(id : int):
	if player_data.has(id): player_data.erase(id)

func get_all_clients() -> Array:
	return player_data.keys()

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

func cache_nodepath(node_path : String, index : int):
	if node_path_index_cache.has(index):
		var oldCachePath : String = node_path_index_cache[index]
		node_path_cache.erase(oldCachePath)
	
	node_path_cache[node_path] = index
	node_path_index_cache[index] = node_path
	
	var node : Node = get_node_or_null(node_path)
	if node:
		await node.tree_exiting
		request_processor.create_erase_nodepath_cache_request(index)

func erase_nodepath_cache(index : int):
	if node_path_index_cache.has(index):
		var node_path : String = node_path_index_cache[index]
		node_path_cache.erase(node_path)
		node_path_index_cache.erase(index)

func cache_name(name : String, index : int):
	if name_index_cache.has(index):
		var oldCachePath : String = name_index_cache[index]
		name_cache.erase(oldCachePath)
	
	name_cache[name] = index
	name_index_cache[index] = name

func erase_name_cache(index : int):
	if name_index_cache.has(index):
		var name : String = name_index_cache[index]
		name_cache.erase(name)
		name_index_cache.erase(index)

func set_player_data(key : String, value):
	player_data[GDSync.get_client_id()][key] = value
	player_data_changed(GDSync.get_client_id(), key)

func player_data_changed(client_id : int, key : String):
	if !player_data.has(client_id): return
	var data : Dictionary = player_data[client_id]
	if data.has(key):
		GDSync.player_data_changed.emit(client_id, key, data[key])
	else:
		GDSync.player_data_changed.emit(client_id, key, null)

func erase_player_data(key : String):
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

func override_player_data(data : Dictionary):
	var id = data["ID"]
	data.erase(id)
	if player_data.has(id):
		player_data[id].clear()
	else:
		player_data[id] = {}
	
	for key in data:
		player_data[id][key] = data[key]

func override_lobby_data(data : Dictionary):
	lobby_data = data

func get_player_limit() -> int:
	if !lobby_data.has("PlayerLimit"): return 0
	return lobby_data["PlayerLimit"]

func lobby_data_changed(key : String):
	if !lobby_data.has("Data"): return
	var data : Dictionary = lobby_data["Data"]
	if !data.has(key):
		GDSync.lobby_data_changed.emit(key, null)
	else:
		GDSync.lobby_data_changed.emit(key, data[key])

func lobby_tags_changed(key : String):
	if !lobby_data.has("Tags"): return
	var tags : Dictionary = lobby_data["Tags"]
	if !tags.has(key):
		GDSync.lobby_tags_changed.emit(key, null)
	else:
		GDSync.lobby_tags_changed.emit(key, tags[key])

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

func get_lobby_tags(key : String, default):
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

func expose_node(node : Node):
	node.set_meta("Exposed", true)

func hide_node(node : Node):
	node.set_meta("Exposed", false)

func node_is_exposed(node : Node):
	return node.get_meta("Exposed", false)

func expose_func(function : Callable):
	var node : Node = function.get_object()
	var functionName : String = function.get_method()
	var exposedArray : Array = node.get_meta("ExposedFunctions", [])
	exposedArray.append(functionName)
	node.set_meta("ExposedFunctions", exposedArray)

func hide_function(function : Callable):
	var node : Node = function.get_object()
	var functionName : String = function.get_method()
	var exposedArray : Array = node.get_meta("ExposedFunctions", [])
	if exposedArray.has(functionName): exposedArray.erase(functionName)

func function_is_exposed(node : Node, function_name : String):
	var exposedArray : Array = node.get_meta("ExposedFunctions", [])
	return exposedArray.has(function_name)

func expose_property(node : Node, property_name : String):
	var exposedArray : Array = node.get_meta("ExposedProperties", [])
	exposedArray.append(property_name)
	node.set_meta("ExposedProperties", exposedArray)

func hide_property(node : Node, propertyName : String):
	var exposedArray : Array = node.get_meta("ExposedProperties", [])
	if exposedArray.has(propertyName): exposedArray.erase(propertyName)

func property_is_exposed(node : Node, propertyName : String):
	var exposedArray : Array = node.get_meta("ExposedProperties", [])
	return exposedArray.has(propertyName)

func set_mc_owner(node : Node, owner):
	set_mc_owner_remote(node, owner)
	request_processor.set_mc_owner(node, owner)

func set_mc_owner_remote(node : Node, owner):
	node.set_meta("mcOwner", owner)
	emit_mc_owner_changed(node, owner)

func emit_mc_owner_changed(node : Node, owner):
	if node.has_user_signal("mc_owner_changed"): node.emit_signal("mc_owner_changed", owner)
	for child in node.get_children():
		emit_mc_owner_changed(child, owner)

func get_mc_owner(node : Node):
	var ownerID = null
	var p : Node = node
	while p != null and ownerID == null:
		if p.has_meta("mcOwner"):
			var id = p.get_meta("mcOwner", null)
			if id != null: ownerID = id
		p = p.get_parent()
	return ownerID

func is_mc_owner(node : Node) -> bool:
	return get_mc_owner(node) == GDSync.get_client_id()

func connect_mc_owner_changed(node : Node, callable : Callable):
	node.add_user_signal("mc_owner_changed", ["owner"])
	node.connect("mc_owner_changed", callable)

func disconnect_mc_owner_changed(node : Node, callable : Callable):
	node.disconnect("mc_owner_changed", callable)
