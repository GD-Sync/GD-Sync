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

var min_port_range : int = 42354
var max_port_range : int = min_port_range + 20

var GDSync
var connection_controller
var request_processor
var session_controller
var logger

var local_lobby_name : String = ""
var local_lobby_password : String = ""
var local_lobby_public : bool = false
var local_lobby_open : bool = true
var local_lobby_player_limit : int = 0

var local_lobby_data : Dictionary = {}
var local_lobby_tags : Dictionary = {}
var local_owner_cache : Dictionary = {}

var local_server : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var local_peer : PacketPeerUDP = PacketPeerUDP.new()
var local_lobby_timer : Timer = Timer.new()

var found_lobbies : Dictionary = {}

var peer_client_table : Dictionary = {}
var lobby_client_table : Dictionary = {}

class Client extends RefCounted:
	var valid : bool = false
	var client_id : int = -1
	var peer_id : int = -1
	var peer : ENetPacketPeer
	var username : String
	var player_data : Dictionary = {}
	
	var requests_RUDP : Array = []
	var requests_UDP : Array = []
	var lobby_targets : Array = []
	
	func construct_lobby_targets(clients : Dictionary) -> void:
		lobby_targets = clients.values()
		lobby_targets.erase(self)
	
	func collect_player_data() -> Dictionary:
		var data : Dictionary = player_data.duplicate()
		data["ID"] = client_id
		data["Username"] = username
		return data

func _ready() -> void:
	GDSync = get_node("/root/GDSync")
	name = "LocalServer"
	connection_controller = GDSync._connection_controller
	request_processor = GDSync._request_processor
	session_controller = GDSync._session_controller
	logger = GDSync._logger
	
	local_server.peer_connected.connect(peer_connected)
	local_server.peer_disconnected.connect(peer_disconnected)
	
	local_lobby_timer.wait_time = 0.5
	local_lobby_timer.timeout.connect(perform_local_scan)
	add_child(local_lobby_timer)
	
	set_process(false)

func reset_multiplayer() -> void:
	logger.write_log("Closing local multiplayer.", "[LocalServer]")
	local_peer.close()
	local_lobby_timer.stop()
	set_process(false)
	
	found_lobbies.clear()
	
	clear_lobby_data()

func clear_lobby_data() -> void:
	logger.write_log("Clear lobby data.", "[LocalServer]")
	local_lobby_name = ""
	local_lobby_password = ""
	
	local_lobby_data.clear()
	local_lobby_tags.clear()
	local_owner_cache.clear()
	peer_client_table.clear()
	lobby_client_table.clear()
	local_server.close()

func start_local_peer() -> bool:
	logger.write_log("Starting local peer.", "[LocalServer]")
	for port in range(min_port_range, max_port_range):
		var bind_error : int = local_peer.bind(port)
		if bind_error == OK:
			logger.write_log("Local peer binded to port. <"+str(port)+">", "[LocalServer]")
			local_lobby_timer.start()
			return true
	
	logger.write_error("Local peer war unable to bind to a port.", "[LocalServer]")
	return false

func create_local_lobby(name : String, password : String = "", public : bool = true, player_limit : int = 0, tags : Dictionary = {}, data : Dictionary = {}) -> void:
	logger.write_log("Creating local lobby.", "[LocalServer]")
	var result : int = -1
	
	local_peer.set_broadcast_enabled(true)
	
	var server_error : int = local_server.create_server(8080)
	if server_error != OK: result = ENUMS.LOBBY_CREATION_ERROR.LOCAL_PORT_ERROR
	
	if name.length() < 3: result = ENUMS.LOBBY_CREATION_ERROR.NAME_TOO_SHORT
	if name.length() > 32: result = ENUMS.LOBBY_CREATION_ERROR.NAME_TOO_LONG
	if password.length() > 16: result = ENUMS.LOBBY_CREATION_ERROR.PASSWORD_TOO_LONG
	if var_to_bytes(tags).size() > 2048: result = ENUMS.LOBBY_CREATION_ERROR.TAGS_TOO_LARGE
	if var_to_bytes(data).size() > 2048: result = ENUMS.LOBBY_CREATION_ERROR.DATA_TOO_LARGE
	
	if result == -1:
		local_lobby_name = name
		local_lobby_password = password
		local_lobby_public = public
		local_lobby_player_limit = player_limit
		local_lobby_tags = tags
		local_lobby_data = data
		
		var lobby_dict : Dictionary = get_lobby_dictionary()
		lobby_dict["IP"] = "127.0.0.1"
		found_lobbies[local_lobby_name] = lobby_dict
		
		set_process(true)
		GDSync.lobby_created.emit.call_deferred(name)
	else:
		GDSync.lobby_creation_failed.emit.call_deferred(name, result)

func join_lobby(name : String, password : String) -> void:
	logger.write_log("Joining local lobby. <"+name+">", "[LocalServer]")
	
	var tries : int = 0
	while !found_lobbies.has(name) and tries < 5:
		logger.write_error("Local lobby not found. <"+name+">", "[LocalServer]")
		tries += 1
		await get_tree().create_timer(1.0).timeout
	
	if found_lobbies.has(name):
		var lobby_data : Dictionary = found_lobbies[name]
		var connect_err : int = connection_controller.connect_to_local_server(lobby_data["IP"])
		
		if connect_err == OK:
			logger.write_log("Connected to local lobby host.", "[LocalServer]")
			connection_controller.in_local_lobby = true
			request_processor.send_client_id()
			session_controller.broadcast_player_data()
			request_processor.create_join_lobby_request(name, password)
			return
		else:
			logger.write_error("Unable to connect to discovered lobby. <"+str(lobby_data["IP"])+">", "[LocalServer]")
	
	GDSync.lobby_join_failed.emit.call_deferred(name, ENUMS.LOBBY_JOIN_ERROR.LOBBY_DOES_NOT_EXIST)

func get_public_lobbies() -> void:
	var lobbies : Array = []
	for lobby_data in found_lobbies.values():
		if lobby_data["Public"]:
			lobbies.append(lobby_data)
	
	GDSync.lobbies_received.emit.call_deferred(lobbies)

func get_public_lobby(lobby_name : String) -> void:
	for lobby_data in found_lobbies.values():
		if lobby_data["Public"] and lobby_data["Name"] == lobby_name:
			GDSync.lobby_received.emit.call_deferred(lobby_data)
			return
	
	GDSync.lobby_received.emit.call_deferred({})

func perform_local_scan() -> void:
	local_lobby_timer.start()
	
	while local_peer.get_available_packet_count() > 0:
		var server_ip : String = local_peer.get_packet_ip()
		var port : int = local_peer.get_packet_port()
		var bytes : PackedByteArray = local_peer.get_packet()
		
		if server_ip != '' and port > 0:
			var lobby_data : Dictionary = bytes_to_var(bytes)
			if !found_lobbies.has(lobby_data["Name"]):
				logger.write_log("Discovered local lobby. <"+server_ip+"><"+lobby_data["Name"]+">", "[LocalServer]")
			lobby_data["IP"] = server_ip
			lobby_data["DetectionTime"] = Time.get_unix_time_from_system()
			found_lobbies[lobby_data["Name"]] = lobby_data
	
	for lobby_data in found_lobbies.values():
		if !lobby_data.has("DetectionTime"): continue
		if Time.get_unix_time_from_system() - lobby_data["DetectionTime"] > 2.0:
			found_lobbies.erase(lobby_data["Name"])
			logger.write_log("Local lobby lost. <"+lobby_data["Name"]+">", "[LocalServer]")
	
	if local_lobby_name != "":
		for port in range(min_port_range, max_port_range):
			var bind_error : int = local_peer.set_dest_address("255.255.255.255", port)
			if bind_error == OK:
				local_peer.put_packet(var_to_bytes(get_lobby_dictionary()))

func is_local_server() -> bool:
	return local_lobby_name != ""

func peer_connected(id : int) -> void:
	logger.write_log("Peer connected.", "[LocalServer]")
	var client : Client = Client.new()
	client.peer = local_server.get_peer(id)
	client.peer_id = id
	peer_client_table[id] = client

func peer_disconnected(id : int) -> void:
	logger.write_log("Peer disconnected.", "[LocalServer]")
	if peer_client_table.has(id):
		var client : Client = peer_client_table[id]
		leave_lobby_request(client)

func _process(delta: float) -> void:
	match(local_server.get_connection_status()):
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			logger.write_log("Peer lost its connection.", "[LocalServer]")
			connection_controller.reset_multiplayer()
		MultiplayerPeer.CONNECTION_CONNECTING:
			local_server.poll()
		MultiplayerPeer.CONNECTION_CONNECTED:
			local_server.poll()
			
			for peer in peer_client_table:
				var client : Client = peer_client_table[peer]
				if client.requests_RUDP.size() > 0:
					local_server.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
					local_server.set_target_peer(client.peer_id)
					local_server.put_packet(var_to_bytes(client.requests_RUDP))
					client.requests_RUDP.clear()
				if client.requests_UDP.size() > 0:
					local_server.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
					local_server.set_target_peer(client.peer_id)
					local_server.put_packet(var_to_bytes(client.requests_UDP))
					client.requests_UDP.clear()
			
			while local_server.get_available_packet_count() > 0:
				var channel : int = local_server.get_packet_channel()
				var peer_id : int = local_server.get_packet_peer()
				var bytes : PackedByteArray = local_server.get_packet()
				
				if !peer_client_table.has(peer_id):
					continue
				
				var from : Client = peer_client_table[peer_id]
				var message : Dictionary = bytes_to_var(bytes)
				
				if message.has(ENUMS.PACKET_VALUE.SERVER_REQUESTS):
					for request in message[ENUMS.PACKET_VALUE.SERVER_REQUESTS]:
						var request_type : int = request[ENUMS.DATA.REQUEST_TYPE]
						logger.write_log("Received server request. <"+str(from.client_id)+"><"+str(ENUMS.REQUEST_TYPE.keys()[request_type])+"><"+str(request)+">", "[LocalServer]")
						match(request_type):
							ENUMS.REQUEST_TYPE.SET_CLIENT_ID:
								from.client_id = request[ENUMS.DATA.NAME]
							ENUMS.REQUEST_TYPE.JOIN_LOBBY:
								join_lobby_request(from, request)
							ENUMS.REQUEST_TYPE.LEAVE_LOBBY:
								leave_lobby_request(from)
							ENUMS.REQUEST_TYPE.OPEN_LOBBY:
								open_lobby_request(from, request)
							ENUMS.REQUEST_TYPE.CLOSE_LOBBY:
								close_lobby_request(from, request)
							ENUMS.REQUEST_TYPE.SET_GDSYNC_OWNER:
								set_owner_request(from, request)
							ENUMS.REQUEST_TYPE.SET_LOBBY_TAG:
								set_lobby_tag_request(from, request)
							ENUMS.REQUEST_TYPE.ERASE_LOBBY_TAG:
								erase_lobby_tag_request(from, request)
							ENUMS.REQUEST_TYPE.SET_LOBBY_DATA:
								set_lobby_data_request(from, request)
							ENUMS.REQUEST_TYPE.ERASE_LOBBY_DATA:
								erase_lobby_data_request(from, request)
							ENUMS.REQUEST_TYPE.SET_LOBBY_VISIBILITY:
								set_lobby_visibility_request(from, request)
							ENUMS.REQUEST_TYPE.SET_PLAYER_USERNAME:
								set_player_username_request(from, request)
							ENUMS.REQUEST_TYPE.SET_PLAYER_DATA:
								set_player_data_request(from, request)
							ENUMS.REQUEST_TYPE.ERASE_PLAYER_DATA:
								erase_player_data_request(from, request)
							ENUMS.REQUEST_TYPE.KICK_PLAYER:
								kick_player(from, request)
							ENUMS.REQUEST_TYPE.CHANGE_PASSWORD:
								change_password(from, request)
							ENUMS.REQUEST_TYPE.CHANGE_LOBBY_NAME:
								change_lobby_name(from, request)
				
				if message.has(ENUMS.PACKET_VALUE.CLIENT_REQUESTS):
					for request in message[ENUMS.PACKET_VALUE.CLIENT_REQUESTS]:
						broadcast_request(request, from, channel == 0)

func broadcast_request(request : Array, from : Client, reliable : bool) -> void:
	if !from.valid: return
	
	var peers : Array = get_target_peers(request, from)
	for client in peers:
		if connection_controller.USE_SENDER_ID: set_sender_id(from, client, reliable)
		put_request(request, client, reliable)

func get_target_peers(request : Array, from : Client) -> Array:
	var targets : Array = []
	if from.valid:
		var target_client : int = int(request[int(ENUMS.DATA.TARGET_CLIENT)])
		if target_client >= 0:
			if lobby_client_table.has(target_client):
				targets.append(lobby_client_table[target_client])
		else:
			return from.lobby_targets
	return targets

func set_sender_id(from : Client, client : Client, reliable : bool) -> void:
	if !connection_controller.USE_SENDER_ID: return
	
	put_request([
		int(ENUMS.REQUEST_TYPE.MESSAGE),
		int(ENUMS.MESSAGE_TYPE.SET_SENDER_ID),
		from.client_id
	], client, reliable)

func send_message(message : int, client : Client, value = null, value2 = null, value3 = null) -> void:
	if client == null:
		return
	if value3 != null:
		put_request([
			int(ENUMS.REQUEST_TYPE.MESSAGE),
			message,
			value,
			value2,
			value3
		], client, true)
	elif value2 != null:
		put_request([
			int(ENUMS.REQUEST_TYPE.MESSAGE),
			message,
			value,
			value2
		], client, true)
	elif value != null:
		put_request([
			int(ENUMS.REQUEST_TYPE.MESSAGE),
			message,
			value
		], client, true)
	else:
		put_request([
			int(ENUMS.REQUEST_TYPE.MESSAGE),
			message
		], client, true)

func put_request(request : Array, client : Client, reliable : bool) -> void:
	if reliable:
		client.requests_RUDP.append(request)
	else:
		client.requests_UDP.append(request)

func join_lobby_request(from : Client, request : Array) -> void:
	if local_lobby_name == "": return
	
	if !local_lobby_open:
		send_message(ENUMS.MESSAGE_TYPE.LOBBY_JOIN_FAILED, from, local_lobby_name, ENUMS.LOBBY_JOIN_ERROR.LOBBY_IS_CLOSED)
		return
	if local_lobby_player_limit > 0 and lobby_client_table.size() >= local_lobby_player_limit:
		send_message(ENUMS.MESSAGE_TYPE.LOBBY_JOIN_FAILED, from, local_lobby_name, ENUMS.LOBBY_JOIN_ERROR.LOBBY_IS_FULL)
		return
	
	var password : String = request[ENUMS.LOBBY_DATA.PASSWORD]
	if local_lobby_password != "" and password != local_lobby_password:
		send_message(ENUMS.MESSAGE_TYPE.LOBBY_JOIN_FAILED, from, local_lobby_name, ENUMS.LOBBY_JOIN_ERROR.INCORRECT_PASSWORD)
		return
	
	if connection_controller.UNIQUE_USERNAMES:
		for client in lobby_client_table.values():
			if client.username == from.username:
				send_message(ENUMS.MESSAGE_TYPE.LOBBY_JOIN_FAILED, from, local_lobby_name, ENUMS.LOBBY_JOIN_ERROR.DUPLICATE_USERNAME)
				return
	
	from.valid = true
	lobby_client_table[from.client_id] = from
	
	send_message(ENUMS.MESSAGE_TYPE.LOBBY_JOINED, from, local_lobby_name)
	send_message(ENUMS.MESSAGE_TYPE.HOST_CHANGED, from, GDSync.get_client_id())
	send_message(ENUMS.MESSAGE_TYPE.LOBBY_DATA_RECEIVED, from, get_lobby_dictionary(true))
	
	for client_id in lobby_client_table:
		var client : Client = lobby_client_table[client_id]
		client.construct_lobby_targets(lobby_client_table)
		
		if client != from:
			send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_RECEIVED, client, from.collect_player_data())
			send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_RECEIVED, from, client.collect_player_data())
			send_message(ENUMS.MESSAGE_TYPE.CLIENT_JOINED, client, from.client_id)
		
		send_message(ENUMS.MESSAGE_TYPE.CLIENT_JOINED, from, client.client_id)
	
	for node_path in local_owner_cache:
		send_message(ENUMS.MESSAGE_TYPE.SET_GDSYNC_OWNER, from, node_path, local_owner_cache[node_path])

func leave_lobby_request(from : Client) -> void:
	logger.write_log(" <"+str(from.client_id)+">", "[LocalServer]")
	if lobby_client_table.has(from.client_id):
		lobby_client_table.erase(from.client_id)
		
		if from.client_id != GDSync.get_client_id():
			for client_id in lobby_client_table:
				var other_client : Client = lobby_client_table[client_id]
				other_client.construct_lobby_targets(lobby_client_table)
				
				if other_client != from:
					send_message(ENUMS.MESSAGE_TYPE.CLIENT_LEFT, other_client, from.client_id)
		else:
			for client_id in lobby_client_table:
				var other_client : Client = lobby_client_table[client_id]
				if other_client != from:
					send_message(ENUMS.MESSAGE_TYPE.KICKED, other_client)
			clear_lobby_data()
	
	if peer_client_table.has(from.peer_id):
		peer_client_table.erase(from.peer_id)
	
	if local_server.get_peer(from.peer_id) != null:
		local_server.disconnect_peer(from.peer_id)

func open_lobby_request(from : Client, request : Array) -> void:
	if !from.valid: return
	local_lobby_open = true

func close_lobby_request(from : Client, request : Array) -> void:
	if !from.valid: return
	local_lobby_open = false

func set_owner_request(from : Client, request : Array) -> void:
	if !from.valid: return
	
	var node_path = request[ENUMS.DATA.NAME]
	var owner = request[ENUMS.DATA.VALUE]
	if owner == null or owner == -1:
		if local_owner_cache.has(owner):
			local_owner_cache.erase(owner)
	else:
		local_owner_cache[node_path] = owner
	
	for client_id in lobby_client_table:
		send_message(ENUMS.MESSAGE_TYPE.SET_GDSYNC_OWNER, lobby_client_table[client_id], node_path, owner)

func set_lobby_tag_request(from : Client, request : Array) -> void:
	var key = request[ENUMS.LOBBY_DATA.NAME]
	var value = request[ENUMS.LOBBY_DATA.VALUE]
	
	local_lobby_tags[key] = value
	
	for client in lobby_client_table.values():
		send_message(ENUMS.MESSAGE_TYPE.LOBBY_DATA_RECEIVED, client, get_lobby_dictionary(true))
		send_message(ENUMS.MESSAGE_TYPE.LOBBY_TAGS_CHANGED, client, key)

func erase_lobby_tag_request(from : Client, request : Array) -> void:
	var key = request[ENUMS.LOBBY_DATA.NAME]
	
	if local_lobby_tags.has(key):
		local_lobby_tags.erase(key)
		for client in lobby_client_table.values():
			send_message(ENUMS.MESSAGE_TYPE.LOBBY_DATA_RECEIVED, client, get_lobby_dictionary(true))
			send_message(ENUMS.MESSAGE_TYPE.LOBBY_TAGS_CHANGED, client, key)

func set_lobby_data_request(from : Client, request : Array) -> void:
	var key = request[ENUMS.LOBBY_DATA.NAME]
	var value = request[ENUMS.LOBBY_DATA.VALUE]
	
	local_lobby_data[key] = value
	
	for client in lobby_client_table.values():
		send_message(ENUMS.MESSAGE_TYPE.LOBBY_DATA_RECEIVED, client, get_lobby_dictionary(true))
		send_message(ENUMS.MESSAGE_TYPE.LOBBY_DATA_CHANGED, client, key)

func erase_lobby_data_request(from : Client, request : Array) -> void:
	var key = request[ENUMS.LOBBY_DATA.NAME]
	
	if local_lobby_data.has(key):
		local_lobby_data.erase(key)
		for client in lobby_client_table.values():
			send_message(ENUMS.MESSAGE_TYPE.LOBBY_DATA_RECEIVED, client, get_lobby_dictionary(true))
			send_message(ENUMS.MESSAGE_TYPE.LOBBY_DATA_CHANGED, client, key)

func set_lobby_visibility_request(from : Client, request : Array) -> void:
	local_lobby_public = request[ENUMS.LOBBY_DATA.VISIBILITY]

func set_player_username_request(from : Client, request : Array) -> void:
	from.username = request[ENUMS.DATA.NAME]
	
	for client in from.lobby_targets:
		send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_RECEIVED, client, from.collect_player_data())
		send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_CHANGED, client, from.client_id, "Username")

func set_player_data_request(from : Client, request : Array) -> void:
	var key = request[ENUMS.DATA.NAME]
	from.player_data[key] = request[ENUMS.DATA.VALUE]
	
	for client in from.lobby_targets:
		send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_RECEIVED, client, from.collect_player_data())
		send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_CHANGED, client, from.client_id, key)

func erase_player_data_request(from : Client, request : Array) -> void:
	var key = request[ENUMS.DATA.NAME]
	
	if from.player_data.has(key):
		from.player_data.erase(key)
		
		for client in from.lobby_targets:
			send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_RECEIVED, from, from.collect_player_data())
			send_message(ENUMS.MESSAGE_TYPE.PLAYER_DATA_CHANGED, from, from.client_id, key)

func kick_player(from : Client, request : Array) -> void:
	var client_id : int = request[ENUMS.DATA.NAME]
	
	if(from.client_id != GDSync.get_client_id()): return
	
	var kicked_client : Client = lobby_client_table.get(client_id, null)
	if kicked_client == null: return
	
	lobby_client_table.erase(client_id)
	send_message(ENUMS.MESSAGE_TYPE.KICKED, kicked_client)
	await get_tree().process_frame
	await get_tree().process_frame
	kicked_client.peer.peer_disconnect()

func change_password(from : Client, request : Array) -> void:
	if(from.client_id != GDSync.get_client_id()): return
	var password : String = request[ENUMS.DATA.NAME]
	local_lobby_password = password

func change_lobby_name(from : Client, request : Array) -> void:
	if(from.client_id != GDSync.get_client_id()): return
	var name : String = request[ENUMS.DATA.NAME]
	local_lobby_name = name

func get_lobby_dictionary(with_data : bool = false) -> Dictionary:
	var dict : Dictionary = {
		"Name" : local_lobby_name,
		"PlayerCount" : GDSync.lobby_get_all_clients().size(),
		"PlayerLimit" : local_lobby_player_limit,
		"Public" : local_lobby_public,
		"Open" : local_lobby_open,
		"Tags" : local_lobby_tags,
		"HasPassword" : local_lobby_password != "",
		"Host" : GDSync.player_get_data(GDSync.get_client_id(), "Username", "")
	}
	
	if with_data:
		dict["Data"] = local_lobby_data
	
	return dict
