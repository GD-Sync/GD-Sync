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

signal packets_processed

var requestsSETUP : Array = []
var requestsSERV : Array = []
var requestsRUDP : Array = []
var requestsUDP : Array = []

var GDSync
var connection_controller
var session_controller

func _ready():
	name = "RequestProcessor"
	GDSync = get_node("/root/GDSync")
	connection_controller = GDSync._connection_controller
	session_controller = GDSync._session_controller

func has_packets(type : int) -> bool:
	match(type):
		ENUMS.PACKET_CHANNEL.SETUP:
			return requestsSETUP.size() > 0
		ENUMS.PACKET_CHANNEL.SERVER:
			if connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return false
			return requestsSERV.size() > 0
		ENUMS.PACKET_CHANNEL.RELIABLE:
			if connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return false
			return requestsRUDP.size() > 0
		ENUMS.PACKET_CHANNEL.UNRELIABLE:
			if connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return false
			return requestsUDP.size() > 0
	return false

func package_requests(client_id : int, type : int) -> PackedByteArray:
	var message : Dictionary = {}
	
	var requests
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
	
	message[packetType] = requests
	bytes = var_to_bytes(message)
	requests.clear()
	
	var padding = bytes.size()
	if connection_controller.status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
		while padding > 16: padding -= 16
		padding = 16-padding
		for i in range(padding): bytes.append(0)
		bytes = connection_controller.encryptor.update(bytes)
	
	var packet : Array = [padding, bytes.compress(2)]
	emit_signal("packets_processed")
	
	return var_to_bytes(packet)

func unpack_packet(bytes : PackedByteArray):
	var packet : Array = bytes_to_var(bytes)
	var encryptedBytes : PackedByteArray = packet[2].decompress(packet[0], 2)
	var message : Dictionary
	
	if connection_controller.status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
		var requestBytes : PackedByteArray = connection_controller.decryptor.update(encryptedBytes)
		var padding : int = packet[ENUMS.PACKET_VALUE.PADDING]
		requestBytes.resize(requestBytes.size()-packet[1])
		message = bytes_to_var(requestBytes)
	else:
		message = bytes_to_var(encryptedBytes)
	
	var requests : Array = message[ENUMS.PACKET_VALUE.CLIENT_REQUESTS]
	
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

func process_message(request : Array):
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
			GDSync.lobby_created.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_CREATION_FAILED:
			GDSync.lobby_creation_failed.emit(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.ERROR])
		ENUMS.MESSAGE_TYPE.LOBBY_JOINED:
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

func handle_critical_error(error : int):
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

func switch_server(ip : String, connect_time : float):
	session_controller.lobby_switch_pending = true
	session_controller.connect_time = connect_time
	connection_controller.external_lobby_switch(ip)

func set_variable_cached(request : Array):
	if !session_controller.has_nodepath_from_index(request[ENUMS.VAR_DATA.NODE_PATH]): return
	if !session_controller.has_name_from_index(request[ENUMS.VAR_DATA.NAME]): return
	request[ENUMS.VAR_DATA.NODE_PATH] = session_controller.get_nodepath_from_index(request[ENUMS.VAR_DATA.NODE_PATH])
	request[ENUMS.VAR_DATA.NAME] = session_controller.get_name_from_index(request[ENUMS.VAR_DATA.NAME])
	set_variable(request)

func set_variable(request : Array):
	var nodePath : String = request[ENUMS.VAR_DATA.NODE_PATH]
	var propertyName : String = request[ENUMS.VAR_DATA.NAME]
	var node : Node = get_node_or_null(nodePath)
	if node == null:
#		push_error("MC attempted to set property \""+propertyName+"\" on nonexistent Node "+nodePath)
		return
	if connection_controller._PROTECTED:
		if !session_controller.node_is_exposed(node) and !session_controller.property_is_exposed(node, propertyName):
			push_error("MC attempted to set a protected property \""+propertyName+"\" on Node "+nodePath+", please expose it using GDSync.expose_property() or GDSync.expose_node()")
			return
		if !propertyName in node:
			push_error("MC attempted to set nonexistent property \""+propertyName+"\" on Node "+nodePath)
			return
	
	node.set(propertyName, request[ENUMS.VAR_DATA.VALUE])

func call_function_cached(request : Array):
	if !session_controller.has_nodepath_from_index(request[ENUMS.FUNCTION_DATA.NODE_PATH]): return
	if !session_controller.has_name_from_index(request[ENUMS.FUNCTION_DATA.NAME]): return
	request[ENUMS.FUNCTION_DATA.NODE_PATH] = session_controller.get_nodepath_from_index(request[ENUMS.FUNCTION_DATA.NODE_PATH])
	request[ENUMS.FUNCTION_DATA.NAME] = session_controller.get_name_from_index(request[ENUMS.FUNCTION_DATA.NAME])
	call_function(request)

func call_function(request : Array):
	var nodePath : String = request[ENUMS.FUNCTION_DATA.NODE_PATH]
	var functionName : String = request[ENUMS.FUNCTION_DATA.NAME]
	var node : Node = get_node_or_null(nodePath)
	
	if node == null:
#		push_error("MC attempted to call function \""+functionName+"\" on nonexistent Node "+nodePath)
		return
	if connection_controller._PROTECTED:
		if !session_controller.node_is_exposed(node) and !session_controller.function_is_exposed(node, functionName):
			push_error("MC attempted to call a protected function \""+functionName+"\" on Node "+nodePath+", please expose it using GDSync.expose_func() or GDSync.expose_node()")
			return
		if !node.has_method(functionName):
			push_error("MC attempted to call nonexistent function \""+functionName+"\" on Node "+nodePath)
			return
	
	if request.size()-1 >= ENUMS.FUNCTION_DATA.PARAMETERS:
		node.callv(functionName, request[ENUMS.FUNCTION_DATA.PARAMETERS])
	else:
		node.call(functionName)

func set_mc_owner_remote(nodePath : String, owner):
	var node : Node = get_node_or_null(nodePath)
	if node == null: return
	session_controller.set_mc_owner_remote(node, owner)

func validate_public_key():
	var request : Array = [
		ENUMS.REQUEST_TYPE.VALIDATE_KEY,
		connection_controller._PUBLIC_KEY,
		OS.get_unique_id(),
	]
	
	requestsSETUP.append(request)

func secure_connection():
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
		
		GDSync.join_lobby(session_controller.lobby_name, session_controller.lobby_password)
	
	GDSync.emit_signal("connected")

func create_set_var_request(node : Node, variableName : String, client_id : int, reliable : bool):
	var request : Array = []
	var nodePath = String(node.get_path())
	
	var value = null
	if variableName in node:
		value = node.get(variableName)
	
	if session_controller.nodepath_is_cached(nodePath) and session_controller.name_is_cached(variableName):
		request = [
			ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED,
			session_controller.get_nodepath_index(nodePath),
			session_controller.get_name_index(variableName),
			value,
			client_id
		]
	else:
		request = [
			ENUMS.REQUEST_TYPE.SET_VARIABLE,
			nodePath,
			variableName,
			value,
			client_id
		]
		
		create_nodepath_cache(nodePath)
		create_name_cache(variableName)
	
	if reliable:
		requestsRUDP.append(request)
	else:
		requestsUDP.append(request)

func create_function_call_request(function : Callable, parameters, client_id : int, reliable : bool):
	var node : Node = function.get_object()
	var functionName : String = function.get_method()
	var request : Array = []
	var nodePath = String(node.get_path())
	
	if session_controller.nodepath_is_cached(nodePath) and session_controller.name_is_cached(functionName):
		request = [
			ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED,
			session_controller.get_nodepath_index(nodePath),
			session_controller.get_name_index(functionName),
			client_id
		]
	else:
		request = [
			ENUMS.REQUEST_TYPE.CALL_FUNCTION,
			nodePath,
			functionName,
			client_id
		]
		
		create_nodepath_cache(nodePath)
		create_name_cache(functionName)
	
	if parameters != null:
		if parameters is Array:
			request.append(parameters)
		else:
			push_error("Parameters must be put in an array due to an engine limitation.")
			return
	
	if reliable:
		requestsRUDP.append(request)
	else:
		requestsUDP.append(request)

func create_nodepath_cache(nodePath : String):
	var request : Array = [
		ENUMS.REQUEST_TYPE.CACHE_NODE_PATH,
		nodePath
	]
	
	requestsSERV.append(request)

func create_erase_nodepath_cache_request(index : int):
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_NODE_PATH_CACHE,
		index
	]
	
	requestsSERV.append(request)

func create_name_cache(name : String):
	var request : Array = [
		ENUMS.REQUEST_TYPE.CACHE_NAME,
		name
	]
	
	requestsSERV.append(request)

func create_erase_name_cache_request(index : int):
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_NAME_CACHE,
		index
	]
	
	requestsSERV.append(request)

func get_public_lobbies():
	var request : Array = [
		ENUMS.REQUEST_TYPE.GET_PUBLIC_LOBBIES
	]
	
	requestsSERV.append(request)

func create_new_lobby_request(name : String, password : String, public : bool, playerLimit : int, tags : Dictionary, data : Dictionary):
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
			"UniqueUsernames" : connection_controller._UNIQUE_USERNAMES
		}
	]
	
	requestsSERV.append(request)

func create_join_lobby_request(name : String, password : String):
	var request : Array = [
		ENUMS.REQUEST_TYPE.JOIN_LOBBY,
		name,
		password
	]
	
	requestsSERV.append(request)

func create_leave_lobby_request():
	var request : Array = [
		ENUMS.REQUEST_TYPE.LEAVE_LOBBY
	]
	
	requestsSERV.append(request)

func create_open_lobby_request():
	var request : Array = [
		ENUMS.REQUEST_TYPE.OPEN_LOBBY
	]
	
	requestsSERV.append(request)

func create_close_lobby_request():
	var request : Array = [
		ENUMS.REQUEST_TYPE.CLOSE_LOBBY
	]
	
	requestsSERV.append(request)

func create_lobby_visiblity_request(public : bool):
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_VISIBILITY,
		public
	]
	
	requestsSERV.append(request)

func create_set_username_request(name : String):
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_PLAYER_USERNAME,
		name
	]
	
	requestsSERV.append(request)

func create_set_player_data_request(name : String, value):
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_PLAYER_DATA,
		name,
		value
	]
	
	requestsSERV.append(request)

func create_erase_player_data_request(name : String):
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_PLAYER_DATA,
		name
	]
	
	requestsSERV.append(request)

func create_set_lobby_tag_request(name : String, value):
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_TAG,
		name,
		value
	]
	
	requestsSERV.append(request)

func create_erase_lobby_tag_request(name : String):
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_LOBBY_TAG,
		name
	]
	
	requestsSERV.append(request)

func create_set_lobby_data_request(name : String, value):
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_DATA,
		name,
		value
	]
	
	requestsSERV.append(request)

func create_erase_lobby_data_request(name : String):
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_LOBBY_DATA,
		name
	]
	
	requestsSERV.append(request)

func set_mc_owner(node : Node, owner):
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_MC_OWNER,
		String(node.get_path()),
		owner
	]
	
	requestsSERV.append(request)

func set_connect_time(connect_time : float):
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_CONNECT_TIME,
		connect_time
	]
	
	requestsSERV.append(request)
