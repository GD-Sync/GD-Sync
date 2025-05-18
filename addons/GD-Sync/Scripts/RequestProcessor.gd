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

signal packets_processed

var requestsSETUP : Array = []
var requestsSERV : Array = []
var requestsRUDP : Array = []
var requestsUDP : Array = []

var GDSync
var connection_controller
var session_controller
var data_controller

var settings_applied : bool = false

func _ready() -> void:
	name = "RequestProcessor"
	GDSync = get_node("/root/GDSync")
	connection_controller = GDSync._connection_controller
	session_controller = GDSync._session_controller
	data_controller = GDSync._data_controller

func has_packets(type : int) -> bool:
	match(type):
		ENUMS.PACKET_CHANNEL.SETUP:
			return requestsSETUP.size() > 0
		ENUMS.PACKET_CHANNEL.SERVER:
			if !connection_controller.is_local() and connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return false
			return requestsSERV.size() > 0
		ENUMS.PACKET_CHANNEL.RELIABLE:
			if !connection_controller.is_local() and connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return false
			return requestsRUDP.size() > 0
		ENUMS.PACKET_CHANNEL.UNRELIABLE:
			if !connection_controller.is_local() and connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return false
			return requestsUDP.size() > 0
	return false

func package_requests(type : int) -> PackedByteArray:
	var message : Dictionary = {}
	
	var requests : Array
	var packetType : int
	var bytes : PackedByteArray
	
	match(type):
		ENUMS.PACKET_CHANNEL.SETUP:
			requests = requestsSETUP
			packetType = ENUMS.PACKET_VALUE.SERVER_REQUESTS
		ENUMS.PACKET_CHANNEL.SERVER:
			requests = requestsSERV
			packetType = ENUMS.PACKET_VALUE.SERVER_REQUESTS
		ENUMS.PACKET_CHANNEL.RELIABLE:
			requests = requestsRUDP
			packetType = ENUMS.PACKET_VALUE.CLIENT_REQUESTS
		ENUMS.PACKET_CHANNEL.UNRELIABLE:
			requests = requestsUDP
			packetType = ENUMS.PACKET_VALUE.CLIENT_REQUESTS
	
	var safe_requests : Array = check_request_size_safety(requests.duplicate())
	message[packetType] = safe_requests
	bytes = var_to_bytes(message)
	
	for request in safe_requests:
		requests.erase(request)
	
	var padding : int = bytes.size()
	if connection_controller.status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
		while padding > 16: padding -= 16
		padding = 16-padding
		for i in range(padding): bytes.append(0)
		connection_controller.refresh_encryptor()
		bytes = connection_controller.encryptor.update(bytes)
	
	packets_processed.emit()
	if connection_controller.is_local():
		return bytes
	else:
		var packet : Array = [padding, bytes.compress(2)]
		return var_to_bytes(packet)

func check_request_size_safety(requests : Array) -> Array:
	var size : int = var_to_bytes(requests).size()
	if size > 20480 and requests.size() > 1:
		return check_request_size_safety(requests.slice(0, ceili(requests.size()/2.0)))
	else:
		return requests

func unpack_packet(bytes : PackedByteArray) -> void:
	var packet : Array = bytes_to_var(bytes)
	var encryptedBytes : PackedByteArray
	var requests : Array
	
	if connection_controller.is_local():
		encryptedBytes = packet
	else:
		encryptedBytes = packet[2].decompress(packet[0], 2)
	
	if connection_controller.status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
		connection_controller.refresh_decryptor()
		var requestBytes : PackedByteArray = connection_controller.decryptor.update(encryptedBytes)
		var padding : int = packet[ENUMS.PACKET_VALUE.PADDING]
		requestBytes.resize(requestBytes.size()-packet[1])
		
		if !settings_applied:
			var message : Dictionary = bytes_to_var(requestBytes)
			requests = message[ENUMS.PACKET_VALUE.CLIENT_REQUESTS]
		else:
			requests = bytes_to_var(requestBytes)
	else:
		if !connection_controller.is_local():
			var message : Dictionary = bytes_to_var(encryptedBytes)
			requests = message[ENUMS.PACKET_VALUE.CLIENT_REQUESTS]
		else:
			requests = packet
	
	for r in requests:
		var request : Array = r
		
		match request[ENUMS.DATA.REQUEST_TYPE]:
			ENUMS.REQUEST_TYPE.SET_VARIABLE:
				set_variable(request)
			ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED:
				set_variable_cached(request)
			ENUMS.REQUEST_TYPE.CALL_FUNCTION:
				call_function(request)
			ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED:
				call_function_cached(request)
			ENUMS.REQUEST_TYPE.MESSAGE:
				process_message(request)

func process_message(request : Array) -> void:
	var message : int = request[ENUMS.MESSAGE_DATA.TYPE]
	
	match(message):
		ENUMS.MESSAGE_TYPE.CRITICAL_ERROR:
			handle_critical_error(request[ENUMS.MESSAGE_DATA.ERROR])
		ENUMS.MESSAGE_TYPE.CLIENT_ID_RECEIVED:
			connection_controller.set_client_id(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.CLIENT_KEY_RECEIVED:
			connection_controller.set_client_key(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.INVALID_PUBLIC_KEY:
			connection_controller.set_client_key(null)
		ENUMS.MESSAGE_TYPE.SET_NODE_PATH_CACHE:
			session_controller.cache_nodepath(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.ERASE_NODE_PATH_CACHE:
			session_controller.erase_nodepath_cache(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.SET_NAME_CACHE:
			session_controller.cache_name(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.ERASE_NAME_CACHE:
			session_controller.erase_nodepath_cache(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.SET_MC_OWNER:
			set_mc_owner_remote(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2] if request.size() >= 4 else null)
		ENUMS.MESSAGE_TYPE.HOST_CHANGED:
			connection_controller.set_host(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_CREATED:
			session_controller.lobby_created()
			GDSync.lobby_created.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_CREATION_FAILED:
			GDSync.lobby_creation_failed.emit(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.ERROR])
		ENUMS.MESSAGE_TYPE.LOBBY_JOINED:
			data_controller.set_friend_status()
			await get_tree().process_frame
			GDSync.lobby_joined.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_JOIN_FAILED:
			GDSync.lobby_join_failed.emit(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.ERROR])
		ENUMS.MESSAGE_TYPE.CLIENT_JOINED:
			GDSync.client_joined.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.CLIENT_LEFT:
			GDSync.client_left.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBIES_RECEIVED:
			GDSync.lobbies_received.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_DATA_RECEIVED:
			session_controller.override_lobby_data(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_DATA_CHANGED:
			session_controller.lobby_data_changed(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_TAGS_CHANGED:
			session_controller.lobby_tags_changed(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.PLAYER_DATA_RECEIVED:
			session_controller.override_player_data(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.PLAYER_DATA_CHANGED:
			session_controller.player_data_changed(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.SWITCH_SERVER:
			switch_server(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.SET_SENDER_ID:
			session_controller.set_sender_id(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.KICKED:
			GDSync.kicked.emit()
			GDSync.lobby_leave()
		ENUMS.MESSAGE_TYPE.LOBBY_RECEIVED:
			GDSync.lobby_received.emit(request[ENUMS.MESSAGE_DATA.VALUE])

func handle_critical_error(error : int) -> void:
	match error:
		ENUMS.CRITICAL_ERROR.LOBBY_DATA_FULL:
			push_error("
			CRITICAL ERROR: 
			You tried to add or change lobby data, but the data has reached its maximum capacity. 
			Please remove existing keys or input smaller values.
			")
		ENUMS.CRITICAL_ERROR.LOBBY_TAGS_FULL:
			push_error("
			CRITICAL ERROR: 
			You tried to add or change lobby tags, but the tag list has reached its maximum capacity. 
			Please remove existing keys or input smaller values.
			")
		ENUMS.CRITICAL_ERROR.PLAYER_DATA_FULL:
			push_error("
			CRITICAL ERROR: 
			You tried to add or change player data, but the data has reached its maximum capacity. 
			Please remove existing keys or input smaller values.
			")
		ENUMS.CRITICAL_ERROR.REQUEST_TOO_LARGE:
			push_error("
			CRITICAL ERROR: 
			One or multiple requests have been discarded due to being too large. 
			Please reduce the amount of data each frame or send smaller requests and values.
			")

func switch_server(ip : String, connect_time : float) -> void:
	session_controller.lobby_switch_pending = true
	session_controller.connect_time = connect_time
	connection_controller.external_lobby_switch(ip)

func set_variable_cached(request : Array) -> void:
	if !session_controller.has_nodepath_from_index(request[ENUMS.VAR_DATA.NODE_PATH]): return
	if !session_controller.has_name_from_index(request[ENUMS.VAR_DATA.NAME]): return
	request[ENUMS.VAR_DATA.NODE_PATH] = session_controller.get_nodepath_from_index(request[ENUMS.VAR_DATA.NODE_PATH])
	request[ENUMS.VAR_DATA.NAME] = session_controller.get_name_from_index(request[ENUMS.VAR_DATA.NAME])
	set_variable(request)

func set_variable(request : Array) -> void:
	var id : String = request[ENUMS.VAR_DATA.NODE_PATH]
	var propertyName : String = request[ENUMS.VAR_DATA.NAME]
	
	var object : Object
	if session_controller.has_resource_by_reference(id):
		object = session_controller.get_resource_by_reference(id)
	else:
		object = get_node_or_null(id)
	
	if object == null:
		return
	if connection_controller.PROTECTED:
		if !session_controller.object_is_exposed(object) and !session_controller.property_is_exposed(object, propertyName):
			push_error("Attempted to set a protected property \""+propertyName+"\" on "+id+", please expose it using GDSync.expose_property() or GDSync.expose_node()/GDSync.expose_resource().")
			return
		if !propertyName in object:
			push_error("Attempted to set nonexistent property \""+propertyName+"\" on "+id)
			return
	
	object.set(propertyName, request[ENUMS.VAR_DATA.VALUE])

func call_function_cached(request : Array) -> void:
	if !session_controller.has_nodepath_from_index(request[ENUMS.FUNCTION_DATA.NODE_PATH]): return
	if !session_controller.has_name_from_index(request[ENUMS.FUNCTION_DATA.NAME]): return
	request[ENUMS.FUNCTION_DATA.NODE_PATH] = session_controller.get_nodepath_from_index(request[ENUMS.FUNCTION_DATA.NODE_PATH])
	request[ENUMS.FUNCTION_DATA.NAME] = session_controller.get_name_from_index(request[ENUMS.FUNCTION_DATA.NAME])
	call_function(request)

func call_function(request : Array) -> void:
	var id : String = request[ENUMS.FUNCTION_DATA.NODE_PATH]
	var functionName : String = request[ENUMS.FUNCTION_DATA.NAME]
	
	var object : Object
	if session_controller.has_resource_by_reference(id):
		object = session_controller.get_resource_by_reference(id)
	else:
		object = get_node_or_null(id)
	
	if object == null:
		return
	if connection_controller.PROTECTED:
		if !session_controller.object_is_exposed(object) and !session_controller.function_is_exposed(object, functionName):
			push_error("Attempted to call a protected function \""+functionName+"\" on "+id+", please expose it using GDSync.expose_func() or GDSync.expose_node()/GDSync.expose_resource().")
			return
		if !object.has_method(functionName):
			push_error("Attempted to call nonexistent function \""+functionName+"\" on "+id)
			return
	
	if request.size()-1 >= ENUMS.FUNCTION_DATA.PARAMETERS:
		object.callv(functionName, request[ENUMS.FUNCTION_DATA.PARAMETERS])
	else:
		object.call(functionName)

func set_mc_owner_remote(node_path : String, owner) -> void:
	if get_tree().current_scene != null:
		var node : Node = get_node_or_null(node_path)
		if node == null: return
		session_controller.set_mc_owner_remote(node, owner)
	else:
		session_controller.set_mc_owner_delayed(node_path, owner)

func validate_public_key() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.VALIDATE_KEY,
		connection_controller._PUBLIC_KEY,
		OS.get_unique_id(),
		true,
	]
	
	requestsSETUP.append(request)

func send_client_id() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_CLIENT_ID,
		GDSync.get_client_id()
	]
	
	requestsSERV.append(request)

func apply_settings() -> void:
	var api_version_request : Array = [
		ENUMS.REQUEST_TYPE.SET_SETTING,
		ENUMS.SETTING.API_VERSION,
		connection_controller.API_VERSION
	]
	var use_sender_id_request : Array = [
		ENUMS.REQUEST_TYPE.SET_SETTING,
		ENUMS.SETTING.USE_SENDER_ID,
		connection_controller.USE_SENDER_ID
	]
	
	requestsSERV.append(api_version_request)
	requestsSERV.append(use_sender_id_request)
	
	settings_applied = true

func secure_connection() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SECURE_CONNECTION
	]
	
	requestsSETUP.append(request)
	
	await self.packets_processed
	await get_tree().create_timer(0.5).timeout
	connection_controller.status = ENUMS.CONNECTION_STATUS.CONNECTION_SECURED
	
	if session_controller.lobby_switch_pending:
		session_controller.lobby_switch_pending = false
		session_controller.broadcast_player_data()
		if session_controller.connect_time > 0:
			set_connect_time(session_controller.connect_time)
			session_controller.connect_time = 0
		
		GDSync.lobby_join(session_controller.lobby_name, session_controller.lobby_password)
	
	GDSync.emit_signal("connected")

func create_set_var_request(object : Object, variable_name : String, client_id : int, reliable : bool) -> void:
	var request : Array = []
	var id : String
	
	if object is Node:
		id = String(object.get_path())
	elif object is RefCounted:
		if !session_controller.has_resource_reference(object):
			push_error("Resource must be registered using GDSync.register_resource()")
			return
		
		id = session_controller.get_resource_reference(object)
	else:
		return
	
	var value = null
	if variable_name in object:
		value = object.get(variable_name)
	
	if !connection_controller.is_local() and session_controller.nodepath_is_cached(id) and session_controller.name_is_cached(variable_name):
		request = [
			ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED,
			session_controller.get_nodepath_index(id),
			session_controller.get_name_index(variable_name),
			client_id,
			value,
		]
	else:
		request = [
			ENUMS.REQUEST_TYPE.SET_VARIABLE,
			id,
			variable_name,
			client_id,
			value,
		]
		
		create_nodepath_cache(id)
		create_name_cache(variable_name)
	
	if reliable:
		requestsRUDP.append(request)
	else:
		requestsUDP.append(request)

func create_function_call_request(function : Callable, parameters : Array, client_id : int, reliable : bool) -> void:
	var object : Object = function.get_object()
	var functionName : String = function.get_method()
	var request : Array = []
	var id : String
	
	if object is Node:
		id = String(object.get_path())
	elif object is RefCounted:
		if !session_controller.has_resource_reference(object):
			push_error("Resource must be registered using GDSync.register_resource()")
			return
		
		id = session_controller.get_resource_reference(object)
	else:
		return
	
	if !connection_controller.is_local() and session_controller.nodepath_is_cached(id) and session_controller.name_is_cached(functionName):
		request = [
			ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED,
			session_controller.get_nodepath_index(id),
			session_controller.get_name_index(functionName),
			client_id
		]
	else:
		request = [
			ENUMS.REQUEST_TYPE.CALL_FUNCTION,
			id,
			functionName,
			client_id
		]
		
		create_nodepath_cache(id)
		create_name_cache(functionName)
	
	if parameters.size() > 0:
		request.append(parameters)
	
	if reliable:
		requestsRUDP.append(request)
	else:
		requestsUDP.append(request)

func create_nodepath_cache(node_path : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.CACHE_NODE_PATH,
		node_path
	]
	
	requestsSERV.append(request)

func create_erase_nodepath_cache_request(index : int) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_NODE_PATH_CACHE,
		index
	]
	
	requestsSERV.append(request)

func create_name_cache(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.CACHE_NAME,
		name
	]
	
	requestsSERV.append(request)

func create_erase_name_cache_request(index : int) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_NAME_CACHE,
		index
	]
	
	requestsSERV.append(request)

func get_public_lobbies() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.GET_PUBLIC_LOBBIES
	]
	
	requestsSERV.append(request)

func get_public_lobby(lobby_name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.GET_PUBLIC_LOBBY,
		lobby_name
	]
	
	requestsSERV.append(request)

func create_new_lobby_request(name : String, password : String, public : bool, playerLimit : int, tags : Dictionary, data : Dictionary) -> void:
	if var_to_bytes(tags).size() > 2048:
		process_message.call_deferred([
			ENUMS.MESSAGE_TYPE.LOBBY_CREATION_FAILED,
			ENUMS.LOBBY_CREATION_ERROR.TAGS_TOO_LARGE
		])
		return
	if var_to_bytes(data).size() > 2048:
		process_message.call_deferred([
			ENUMS.MESSAGE_TYPE.LOBBY_CREATION_FAILED,
			ENUMS.LOBBY_CREATION_ERROR.DATA_TOO_LARGE
		])
		return
	
	var request : Array = [
		ENUMS.REQUEST_TYPE.CREATE_LOBBY,
		{
			"Name" : name,
			"Password" : password,
			"Public" : public,
			"PlayerLimit" : playerLimit,
			"Tags" : tags,
			"Data" : data,
			"UniqueUsernames" : connection_controller.UNIQUE_USERNAMES
		}
	]
	
	requestsSERV.append(request)

func create_join_lobby_request(name : String, password : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.JOIN_LOBBY,
		name,
		password
	]
	
	requestsSERV.append(request)

func create_leave_lobby_request() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.LEAVE_LOBBY
	]
	
	requestsSERV.append(request)

func create_open_lobby_request() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.OPEN_LOBBY
	]
	
	requestsSERV.append(request)

func create_close_lobby_request() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.CLOSE_LOBBY
	]
	
	requestsSERV.append(request)

func create_lobby_visiblity_request(public : bool) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_VISIBILITY,
		public
	]
	
	requestsSERV.append(request)

func create_change_lobby_password_request(password : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.CHANGE_PASSWORD,
		password
	]
	
	requestsSERV.append(request)

func create_set_username_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_PLAYER_USERNAME,
		name
	]
	
	requestsSERV.append(request)

func create_set_player_data_request(name : String, value) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_PLAYER_DATA,
		name,
		value
	]
	
	requestsSERV.append(request)

func create_erase_player_data_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_PLAYER_DATA,
		name
	]
	
	requestsSERV.append(request)

func create_set_lobby_tag_request(name : String, value) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_TAG,
		name,
		value
	]
	
	requestsSERV.append(request)

func create_erase_lobby_tag_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_LOBBY_TAG,
		name
	]
	
	requestsSERV.append(request)

func create_set_lobby_data_request(name : String, value) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_DATA,
		name,
		value
	]
	
	requestsSERV.append(request)

func create_erase_lobby_data_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_LOBBY_DATA,
		name
	]
	
	requestsSERV.append(request)

func set_gdsync_owner(node : Node, owner) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_MC_OWNER,
		String(node.get_path()),
		owner
	]
	
	requestsSERV.append(request)

func set_connect_time(connect_time : float) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_CONNECT_TIME,
		connect_time
	]
	
	requestsSERV.append(request)

func kick_player(client_id : int) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.KICK_PLAYER,
		client_id
	]
	
	requestsSERV.append(request)
