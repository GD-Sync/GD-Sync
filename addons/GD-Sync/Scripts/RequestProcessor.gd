extends Node

#Copyright (c) 2023-present GD-Sync.
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

var name_cache_temp : Dictionary = {}
var node_path_cache_temp : Dictionary = {}

var GDSync
var connection_controller
var session_controller
var data_controller
var matchmaking_controller
var server_switch_controller
var logger

var settings_applied : bool = false

func _ready() -> void:
	name = "RequestProcessor"
	GDSync = get_node("/root/GDSync")
	connection_controller = GDSync._connection_controller
	session_controller = GDSync._session_controller
	data_controller = GDSync._data_controller
	matchmaking_controller = GDSync._matchmaking_controller
	server_switch_controller = GDSync._server_switch_controller
	logger = GDSync._logger

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

func clear_for_server_switch() -> void:
	requestsSETUP.clear()
	requestsSERV.clear()
	requestsRUDP.clear()
	requestsUDP.clear()
	_seen_unreliable_nonces.clear()
	settings_applied = false

const _WIRE_COMPRESSION : int = FileAccess.COMPRESSION_ZSTD
const _MAX_PLAIN_REQUEST_BATCH_BYTES : int = 20480
const _MAX_DECOMPRESSED_PACKET_BYTES : int = 2097152
const _TARGET_CLIENT_ID_MASK : int = 0x3FFFFFFF
const _TARGET_PERMISSION_SHIFT : int = 30

const _UNRELIABLE_AUTH_KEY : String = "_gdsn"
const _UNRELIABLE_NONCE_WINDOW_MS : int = 10000
var _unreliable_nonce_counter : int = 0
var _seen_unreliable_nonces : Dictionary = {}

func encode_target_client(client_id : int, permission : int) -> int:
	var id_part : int = client_id if client_id >= 0 else _TARGET_CLIENT_ID_MASK
	return (permission << _TARGET_PERMISSION_SHIFT) | (id_part & _TARGET_CLIENT_ID_MASK)

const _CALLER_CLIENT_INDEX : int = 4

func _embed_caller_in_sync_request(parts : Array, trailing = null) -> Array:
	parts.append(GDSync.get_client_id())
	if trailing != null:
		parts.append(trailing)
	return parts

func _request_has_embedded_caller(request : Array, request_type : int) -> bool:
	if request.size() <= _CALLER_CLIENT_INDEX:
		return false
	match request_type:
		ENUMS.REQUEST_TYPE.SET_VARIABLE, ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED:
			return request.size() >= 6 and request[_CALLER_CLIENT_INDEX] is int
		ENUMS.REQUEST_TYPE.CALL_FUNCTION, ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED:
			var slot = request[_CALLER_CLIENT_INDEX]
			return slot is int and not (slot is Array)
	return false

func _request_caller_id(request : Array, request_type : int) -> int:
	if !_request_has_embedded_caller(request, request_type):
		return -1
	return request[_CALLER_CLIENT_INDEX]

func _request_var_value(request : Array, request_type : int):
	if _request_has_embedded_caller(request, request_type):
		return request[5]
	return request[ENUMS.VAR_DATA.VALUE]

func _request_func_parameters(request : Array, request_type : int):
	if _request_has_embedded_caller(request, request_type):
		if request.size() > 5:
			var parameters = request[5]
			if parameters is Dictionary and parameters.has(_UNRELIABLE_AUTH_KEY):
				return null
			return parameters
		return null
	if request.size() - 1 >= ENUMS.FUNCTION_DATA.PARAMETERS:
		var parameters = request[ENUMS.FUNCTION_DATA.PARAMETERS]
		if parameters is Dictionary and parameters.has(_UNRELIABLE_AUTH_KEY):
			return null
		return parameters
	return null

func stamp_caller_id(request : Array, caller_id : int) -> Array:
	var req : Array = request.duplicate()
	var request_type : int = req[ENUMS.DATA.REQUEST_TYPE]
	if request_type not in [
		ENUMS.REQUEST_TYPE.SET_VARIABLE,
		ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED,
		ENUMS.REQUEST_TYPE.CALL_FUNCTION,
		ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED,
	]:
		return req
	if _request_has_embedded_caller(req, request_type):
		req[_CALLER_CLIENT_INDEX] = caller_id
		return req
	match request_type:
		ENUMS.REQUEST_TYPE.SET_VARIABLE, ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED:
			if req.size() >= 5:
				req.insert(_CALLER_CLIENT_INDEX, caller_id)
		ENUMS.REQUEST_TYPE.CALL_FUNCTION, ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED:
			if req.size() == 4:
				req.append(caller_id)
			elif req.size() >= 5:
				req.insert(_CALLER_CLIENT_INDEX, caller_id)
	return req

func _send_channel_is_reliable(channel_type : int) -> bool:
	return channel_type != ENUMS.PACKET_CHANNEL.UNRELIABLE

func _recv_transport_is_reliable(transport_channel : int) -> bool:
	return transport_channel == 0

func _encrypt_outgoing_if_secured(plain : PackedByteArray, channel_type : int) -> PackedByteArray:
	if connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
		return plain
	var reliable : bool = _send_channel_is_reliable(channel_type)
	return connection_controller.encrypt_secured_payload(plain, reliable)

func _wrap_remote_packet(inner : PackedByteArray) -> PackedByteArray:
	var envelope : Array = [inner.size(), 0, inner.compress(_WIRE_COMPRESSION)]
	return var_to_bytes(envelope)

func package_requests(type : int) -> PackedByteArray:
	var requests : Array
	var packet_type : int
	match type:
		ENUMS.PACKET_CHANNEL.SETUP:
			requests = requestsSETUP
			packet_type = ENUMS.PACKET_VALUE.SERVER_REQUESTS
		ENUMS.PACKET_CHANNEL.SERVER:
			requests = requestsSERV
			packet_type = ENUMS.PACKET_VALUE.SERVER_REQUESTS
		ENUMS.PACKET_CHANNEL.RELIABLE:
			requests = requestsRUDP
			packet_type = ENUMS.PACKET_VALUE.CLIENT_REQUESTS
		ENUMS.PACKET_CHANNEL.UNRELIABLE:
			requests = requestsUDP
			packet_type = ENUMS.PACKET_VALUE.CLIENT_REQUESTS
	
	var batch : Array = requests.duplicate()
	if type == ENUMS.PACKET_CHANNEL.UNRELIABLE:
		for request in batch:
			if request is Array:
				_stamp_unreliable_auth(request)
	var message : Dictionary = {packet_type: batch}
	var plain : PackedByteArray = var_to_bytes(message)
	while plain.size() > _MAX_PLAIN_REQUEST_BATCH_BYTES and batch.size() > 1:
		batch = batch.slice(0, ceili(batch.size() / 2.0))
		message = {packet_type: batch}
		plain = var_to_bytes(message)
	for request in batch:
		requests.erase(request)
	
	var payload : PackedByteArray = _encrypt_outgoing_if_secured(plain, type)
	packets_processed.emit()
	
	var return_bytes : PackedByteArray = payload if connection_controller.is_local() else _wrap_remote_packet(payload)
	
	if logger.use_profiler and batch.size() > 0:
		var compressed_packet_size : float = return_bytes.size()
		var total_uncompressed_size : float = 0.0
		var uncompressed_size_table : Dictionary = {}
		for r in batch:
			var uncompressed_size : float = var_to_bytes(r).size()
			total_uncompressed_size += uncompressed_size
			uncompressed_size_table[r] = uncompressed_size
		
		if total_uncompressed_size > 0.0:
			for r in batch:
				var compressed_size_estimate : int = (uncompressed_size_table[r] / total_uncompressed_size) * compressed_packet_size
				var origin_data : Dictionary = get_request_origin_data(r)
				if origin_data.size() > 0:
					logger.register_transfer_usage(origin_data, compressed_size_estimate, true, var_to_str(r))
	
	return return_bytes

func _requests_from_payload_bytes(data : PackedByteArray) -> Array:
	if data.is_empty():
		return []
	return _requests_from_parsed_variant(bytes_to_var(data))

func _requests_from_parsed_variant(parsed : Variant) -> Array:
	if parsed is Dictionary:
		return _requests_from_message_dict(parsed as Dictionary)
	if parsed is Array:
		return parsed as Array
	return []

func _requests_from_message_dict(d : Dictionary) -> Array:
	for key in [ENUMS.PACKET_VALUE.CLIENT_REQUESTS, ENUMS.PACKET_VALUE.SERVER_REQUESTS, ENUMS.PACKET_VALUE.INTERNAL_REQUESTS]:
		if d.has(key):
			var v : Variant = d[key]
			return v if v is Array else []
	return []

func _decompress_remote_envelope(outer : Array) -> PackedByteArray:
	if outer.size() < 3 or !(outer[2] is PackedByteArray):
		return PackedByteArray()
	var uncompressed_size : int = int(outer[0])
	var zstd_blob : PackedByteArray = outer[2] as PackedByteArray
	if uncompressed_size <= 0 or uncompressed_size > _MAX_DECOMPRESSED_PACKET_BYTES:
		logger.write_error("Dropped a packet whose claimed size was not valid. <"+str(uncompressed_size)+">")
		return PackedByteArray()
	if zstd_blob.is_empty() or zstd_blob.size() > _MAX_DECOMPRESSED_PACKET_BYTES:
		return PackedByteArray()
	var body : PackedByteArray = zstd_blob.decompress(uncompressed_size, _WIRE_COMPRESSION)
	if body.size() != uncompressed_size:
		return PackedByteArray()
	return body

func _next_unreliable_nonce() -> int:
	_unreliable_nonce_counter = (_unreliable_nonce_counter + 1) & 0xFFFF
	return (Time.get_ticks_msec() << 16) | _unreliable_nonce_counter

func _unreliable_mac(request : Array, nonce : int) -> PackedByteArray:
	var ctx : HMACContext = HMACContext.new()
	if ctx.start(HashingContext.HASH_SHA256, connection_controller._PRIVATE_KEY.to_utf8_buffer()) != OK:
		return PackedByteArray()
	ctx.update(var_to_bytes(request))
	ctx.update(var_to_bytes(nonce))
	return ctx.finish()

func _stamp_unreliable_auth(request : Array) -> void:
	var nonce : int = _next_unreliable_nonce()
	request.append({_UNRELIABLE_AUTH_KEY: [1, nonce, _unreliable_mac(request, nonce)]})

func _remember_unreliable_nonce(nonce : int) -> bool:
	var now_ms : int = Time.get_ticks_msec()
	var nonce_ms : int = nonce >> 16
	if nonce_ms + _UNRELIABLE_NONCE_WINDOW_MS < now_ms:
		return false
	if nonce_ms > now_ms + 2000:
		return false
	if _seen_unreliable_nonces.has(nonce):
		return false
	
	_seen_unreliable_nonces[nonce] = nonce_ms
	if _seen_unreliable_nonces.size() > 4096:
		var expired : Array = []
		for seen in _seen_unreliable_nonces:
			if int(_seen_unreliable_nonces[seen]) + _UNRELIABLE_NONCE_WINDOW_MS < now_ms:
				expired.append(seen)
		for seen in expired:
			_seen_unreliable_nonces.erase(seen)
	return true

func _macs_equal(left : PackedByteArray, right : PackedByteArray) -> bool:
	if left.size() != right.size():
		return false
	var mismatch : int = 0
	for i in range(left.size()):
		mismatch |= left[i] ^ right[i]
	return mismatch == 0

func _accept_incoming_request(request : Array) -> bool:
	if request.is_empty():
		return false
	var last = request[request.size() - 1]
	if !(last is Dictionary) or !last.has(_UNRELIABLE_AUTH_KEY):
		return true
	
	var auth = last[_UNRELIABLE_AUTH_KEY]
	if !(auth is Array) or auth.size() < 3 or !(auth[2] is PackedByteArray):
		return false
	
	request.resize(request.size() - 1)
	var nonce : int = int(auth[1])
	if !_macs_equal(_unreliable_mac(request, nonce), auth[2]):
		logger.write_error("Dropped a packet whose authentication check failed.")
		return false
	if !_remember_unreliable_nonce(nonce):
		return false
	return true

func _request_min_size(request_type : int) -> int:
	match request_type:
		ENUMS.REQUEST_TYPE.SET_VARIABLE, ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED:
			return 5
		ENUMS.REQUEST_TYPE.CALL_FUNCTION, ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED:
			return 4
		ENUMS.REQUEST_TYPE.MESSAGE:
			return 2
	return 1

func _decrypt_body_if_needed(body : PackedByteArray, transport_channel : int) -> PackedByteArray:
	if connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
		return body
	var reliable : bool = _recv_transport_is_reliable(transport_channel)
	return connection_controller.decrypt_secured_payload(body, reliable)

func _requests_from_packet_bytes(packet_bytes : PackedByteArray, transport_channel : int) -> Array:
	var outer : Variant = bytes_to_var(packet_bytes)
	if connection_controller.is_local():
		if connection_controller.status != ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
			return _requests_from_parsed_variant(outer)
		if !(outer is PackedByteArray):
			return []
		var cipher_local : PackedByteArray = outer as PackedByteArray
		var decrypted_body : PackedByteArray = _decrypt_body_if_needed(cipher_local, transport_channel)
		if decrypted_body.is_empty():
			return []
		return _requests_from_payload_bytes(decrypted_body)
	if !(outer is Array):
		return []
	var body : PackedByteArray = _decompress_remote_envelope(outer as Array)
	if body.is_empty():
		return []
	var decrypted_body : PackedByteArray = _decrypt_body_if_needed(body, transport_channel)
	if decrypted_body.is_empty():
		return []
	return _requests_from_payload_bytes(decrypted_body)

func unpack_packet(bytes : PackedByteArray, transport_channel : int = 0) -> void:
	var requests : Array = _requests_from_packet_bytes(bytes, transport_channel)
	var compressed_packet_size : float = bytes.size()
	
	for r in requests:
		if !(r is Array):
			continue
		var request : Array = r
		if !_accept_incoming_request(request):
			continue
		if request.size() < 1 or !(request[ENUMS.DATA.REQUEST_TYPE] is int):
			continue
		if request.size() < _request_min_size(request[ENUMS.DATA.REQUEST_TYPE]):
			continue
		
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
	
	if logger.use_profiler and requests.size() > 0:
		var total_uncompressed_size : float = 0.0
		var uncompressed_size_table : Dictionary = {}
		for r in requests:
			if !(r is Array):
				continue
			var uncompressed_size : float = var_to_bytes(r).size()
			total_uncompressed_size += uncompressed_size
			uncompressed_size_table[r] = uncompressed_size
		if total_uncompressed_size > 0.0:
			for r in requests:
				if !(r is Array):
					continue
				var compressed_size_estimate : int = (uncompressed_size_table[r] / total_uncompressed_size) * compressed_packet_size
				var origin_data : Dictionary = get_request_origin_data(r)
				if origin_data.size() > 0:
					logger.register_transfer_usage(origin_data, compressed_size_estimate, false, var_to_str(r))

func get_request_origin_data(r : Array) -> Dictionary:
	if r.size() < 1 or !(r[ENUMS.DATA.REQUEST_TYPE] is int):
		return {}
	if r.size() < _request_min_size(r[ENUMS.DATA.REQUEST_TYPE]):
		return {}
	match r[ENUMS.DATA.REQUEST_TYPE]:
		ENUMS.REQUEST_TYPE.SET_VARIABLE:
			var id : String = r[ENUMS.VAR_DATA.NODE_PATH]
			var property_name : String = r[ENUMS.VAR_DATA.NAME]
			return {"type" : "sync_var", "object" : id, "target" : property_name}
		ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED:
			if r[ENUMS.VAR_DATA.NODE_PATH] is int and !session_controller.has_nodepath_from_index(r[ENUMS.VAR_DATA.NODE_PATH]):
				return {}
			if r[ENUMS.VAR_DATA.NAME] is int and !session_controller.has_name_from_index(r[ENUMS.VAR_DATA.NAME]):
				return {}
			var id : String = session_controller.get_nodepath_from_index(r[ENUMS.VAR_DATA.NODE_PATH]) if r[ENUMS.VAR_DATA.NODE_PATH] is int else r[ENUMS.VAR_DATA.NODE_PATH]
			var property_name : String = session_controller.get_name_from_index(r[ENUMS.VAR_DATA.NAME]) if r[ENUMS.VAR_DATA.NAME] is int else r[ENUMS.VAR_DATA.NAME]
			return {"type" : "sync_var optimized", "object" : id, "target" : property_name}
		ENUMS.REQUEST_TYPE.CALL_FUNCTION:
			var id : String = r[ENUMS.FUNCTION_DATA.NODE_PATH]
			var function_name : String = r[ENUMS.FUNCTION_DATA.NAME]
			return {"type" : "call_func", "object" : id, "target" : function_name}
		ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED:
			if r[ENUMS.FUNCTION_DATA.NODE_PATH] is int and !session_controller.has_nodepath_from_index(r[ENUMS.FUNCTION_DATA.NODE_PATH]):
				return {}
			if r[ENUMS.FUNCTION_DATA.NAME] is int and !session_controller.has_name_from_index(r[ENUMS.FUNCTION_DATA.NAME]):
				return {}
			var id : String = session_controller.get_nodepath_from_index(r[ENUMS.FUNCTION_DATA.NODE_PATH]) if r[ENUMS.FUNCTION_DATA.NODE_PATH] is int else r[ENUMS.FUNCTION_DATA.NODE_PATH]
			var function_name : String = session_controller.get_name_from_index(r[ENUMS.FUNCTION_DATA.NAME]) if r[ENUMS.FUNCTION_DATA.NAME] is int else r[ENUMS.FUNCTION_DATA.NAME]
			return {"type" : "call_func optimized", "object" : id, "target" : function_name}
		ENUMS.REQUEST_TYPE.MESSAGE:
			return {"type" : "internal", "object" : "GD-Sync", "target" : "Internal Message ("+ENUMS.MESSAGE_TYPE.keys()[r[ENUMS.MESSAGE_DATA.TYPE]].capitalize()+")"}
	return {}

func process_message(request : Array) -> void:
	if request.size() <= ENUMS.MESSAGE_DATA.TYPE or !(request[ENUMS.MESSAGE_DATA.TYPE] is int):
		return
	var message : int = request[ENUMS.MESSAGE_DATA.TYPE]
	
	if OS.is_debug_build() and message != ENUMS.MESSAGE_TYPE.SET_SENDER_ID:
		logger.write_log("Message received. <"+str(ENUMS.MESSAGE_TYPE.keys()[message])+"><"+str(request)+">")
	
	match(message):
		ENUMS.MESSAGE_TYPE.CRITICAL_ERROR:
			if request.size() <= ENUMS.MESSAGE_DATA.ERROR: return
			handle_critical_error(request[ENUMS.MESSAGE_DATA.ERROR])
		ENUMS.MESSAGE_TYPE.CLIENT_ID_RECEIVED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			connection_controller.set_client_id(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.CLIENT_KEY_RECEIVED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			connection_controller.set_client_key(String(request[ENUMS.MESSAGE_DATA.VALUE]))
		ENUMS.MESSAGE_TYPE.INVALID_PUBLIC_KEY:
			logger.write_error("Client key was empty or public key invalid.")
			connection_controller.reset_multiplayer()
			GDSync.emit_signal("connection_failed", ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY)
		ENUMS.MESSAGE_TYPE.SET_NODE_PATH_CACHE:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE2: return
			session_controller.cache_nodepath(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.ERASE_NODE_PATH_CACHE:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.erase_nodepath_cache(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.SET_NAME_CACHE:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE2: return
			session_controller.cache_name(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.ERASE_NAME_CACHE:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.erase_nodepath_cache(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.SET_GDSYNC_OWNER:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			set_gdsync_owner_remote(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2] if request.size() > ENUMS.MESSAGE_DATA.VALUE2 else null)
		ENUMS.MESSAGE_TYPE.HOST_CHANGED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			connection_controller.set_host(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_CREATED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.lobby_created()
			data_controller.set_friend_status()
			GDSync.lobby_created.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_CREATION_FAILED:
			if request.size() <= ENUMS.MESSAGE_DATA.ERROR: return
			GDSync.lobby_creation_failed.emit(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.ERROR])
		ENUMS.MESSAGE_TYPE.LOBBY_JOINED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			data_controller.set_friend_status()
			await get_tree().process_frame
			server_switch_controller.lobby_joined()
			matchmaking_controller.lobby_joined()
			GDSync.lobby_joined.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_JOIN_FAILED:
			if request.size() <= ENUMS.MESSAGE_DATA.ERROR: return
			server_switch_controller.lobby_join_failed()
			matchmaking_controller.lobby_join_failed()
			GDSync.lobby_join_failed.emit(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.ERROR])
		ENUMS.MESSAGE_TYPE.CLIENT_JOINED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			GDSync.client_joined.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.CLIENT_LEFT:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			GDSync.client_left.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBIES_RECEIVED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			GDSync.lobbies_received.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_DATA_RECEIVED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.override_lobby_data(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_DATA_CHANGED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.lobby_data_changed(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_TAGS_CHANGED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.lobby_tags_changed(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.PLAYER_DATA_RECEIVED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.override_player_data(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.PLAYER_DATA_CHANGED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE2: return
			session_controller.player_data_changed(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.SET_SENDER_ID:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			session_controller.set_sender_id(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.KICKED:
			var kick_reason : String = ""
			if request.size() > ENUMS.MESSAGE_DATA.VALUE:
				kick_reason = str(request[ENUMS.MESSAGE_DATA.VALUE])
			GDSync.kicked.emit(kick_reason)
			GDSync.lobby_leave()
		ENUMS.MESSAGE_TYPE.LOBBY_RECEIVED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			GDSync.lobby_received.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_NAME_CHANGED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			GDSync.lobby_name_changed.emit(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.LOBBY_NAME_CHANGE_FAILED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE2: return
			GDSync.lobby_name_change_failed.emit(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.MATCHMAKING_STARTED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			matchmaking_controller.started(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.MATCHMAKING_STATUS_CHANGED:
			if request.size() < 5: return
			matchmaking_controller.status_changed(request[2], request[3], request[4])
		ENUMS.MESSAGE_TYPE.MATCHMAKING_MATCH_FOUND:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE2: return
			matchmaking_controller.match_found(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.MATCHMAKING_FAILED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE2: return
			matchmaking_controller.failed(request[ENUMS.MESSAGE_DATA.VALUE], request[ENUMS.MESSAGE_DATA.VALUE2])
		ENUMS.MESSAGE_TYPE.MATCHMAKING_CANCELLED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE: return
			matchmaking_controller.cancelled(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.SWITCH_SERVER_PREPARED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE or !(request[ENUMS.MESSAGE_DATA.VALUE] is Dictionary): return
			server_switch_controller.begin(request[ENUMS.MESSAGE_DATA.VALUE])
		ENUMS.MESSAGE_TYPE.MATCHMAKING_SWITCH_PREPARED:
			if request.size() <= ENUMS.MESSAGE_DATA.VALUE or !(request[ENUMS.MESSAGE_DATA.VALUE] is Dictionary): return
			var switch_data: Dictionary = request[ENUMS.MESSAGE_DATA.VALUE]
			matchmaking_controller.remote_match_found(
				switch_data.get("MatchmakingRequestId", 0),
				str(switch_data.get("LobbyName", "")))
			server_switch_controller.begin(switch_data)
		ENUMS.MESSAGE_TYPE.TUNNEL_READY:
			server_switch_controller.tunnel_ready()
		ENUMS.MESSAGE_TYPE.TUNNEL_FAILED:
			server_switch_controller.tunnel_failed()
		ENUMS.MESSAGE_TYPE.TUNNEL_LOCAL:
			server_switch_controller.tunnel_local()

func handle_critical_error(error : int) -> void:
	if error < 0 or error >= ENUMS.CRITICAL_ERROR.keys().size():
		logger.write_error("CRITICAL ERROR. <"+str(error)+">")
		return
	logger.write_error("CRITICAL ERROR. <"+str(ENUMS.CRITICAL_ERROR.keys()[error])+">")
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
		ENUMS.CRITICAL_ERROR.OBJECT_IN_REQUEST:
			push_error("
			CRITICAL ERROR: 
			A request was discarded because it contained an Object or Node reference. 
			GD-Sync cannot serialize Objects. Sync IDs, paths, or plain data instead of Node/Object references.
			")

func set_variable_cached(request : Array) -> void:
	if !session_controller.has_nodepath_from_index(request[ENUMS.VAR_DATA.NODE_PATH]):
		logger.write_error("Set variable cached was called but the indexed NodePath was not found. <"+str(request[ENUMS.VAR_DATA.NODE_PATH]+">"))
		return
	if !session_controller.has_name_from_index(request[ENUMS.VAR_DATA.NAME]):
		logger.write_error("Set variable cached was called but the indexed name was not found. <"+str(request[ENUMS.VAR_DATA.NAME])+">")
		return
	
	request[ENUMS.VAR_DATA.NODE_PATH] = session_controller.get_nodepath_from_index(request[ENUMS.VAR_DATA.NODE_PATH])
	request[ENUMS.VAR_DATA.NAME] = session_controller.get_name_from_index(request[ENUMS.VAR_DATA.NAME])
	set_variable(request)

func set_variable(request : Array) -> void:
	var request_type : int = request[ENUMS.DATA.REQUEST_TYPE]
	var caller_id : int = _request_caller_id(request, request_type)
	session_controller.begin_incoming_request(caller_id)
	
	var id : String = request[ENUMS.VAR_DATA.NODE_PATH]
	var property_name : String = request[ENUMS.VAR_DATA.NAME]
	
	var object : Object
	if session_controller.has_resource_by_reference(id):
		object = session_controller.get_resource_by_reference(id)
	else:
		object = get_node_or_null(id)
	
	if object == null:
		session_controller.end_incoming_request()
		logger.write_error("Set variable failed since the target Node or Resource was not found. <"+id+"><"+property_name+">")
		return
	if connection_controller.PROTECTED:
		if !session_controller.object_is_exposed(object) and !session_controller.property_is_exposed(object, property_name):
			session_controller.end_incoming_request()
			logger.write_error("Set variable failed since the object or variable was not exposed. <"+id+"><"+property_name+">")
			push_error("Attempted to set a protected property \""+property_name+"\" on "+id+", please expose it using GDSync.expose_property() or GDSync.expose_node()/GDSync.expose_resource().")
			return
	if !session_controller.object_is_exposed(object):
		if !session_controller.is_caller_permitted(session_controller.get_property_permission(object, property_name)):
			session_controller.end_incoming_request()
			return
	if !property_name in object:
		session_controller.end_incoming_request()
		logger.write_error("Set variable failed since the Node or Resource does not contain the specified variable. <"+id+"><"+property_name+">")
		push_error("Attempted to set nonexistent property \""+property_name+"\" on "+id)
		return
	
	object.set(property_name, _request_var_value(request, request_type))
	session_controller.end_incoming_request()

func call_function_cached(request : Array) -> void:
	if !session_controller.has_nodepath_from_index(request[ENUMS.FUNCTION_DATA.NODE_PATH]):
		logger.write_error("Call function cached was called but the indexed NodePath was not found. <"+str(request[ENUMS.FUNCTION_DATA.NODE_PATH])+">")
		return
	if !session_controller.has_name_from_index(request[ENUMS.FUNCTION_DATA.NAME]):
		logger.write_error("Call function cached was called but the indexed name was not found. <"+str(request[ENUMS.FUNCTION_DATA.NAME])+">")
		return
	request[ENUMS.FUNCTION_DATA.NODE_PATH] = session_controller.get_nodepath_from_index(request[ENUMS.FUNCTION_DATA.NODE_PATH])
	request[ENUMS.FUNCTION_DATA.NAME] = session_controller.get_name_from_index(request[ENUMS.FUNCTION_DATA.NAME])
	call_function(request)

func call_function(request : Array) -> void:
	var request_type : int = request[ENUMS.DATA.REQUEST_TYPE]
	var caller_id : int = _request_caller_id(request, request_type)
	session_controller.begin_incoming_request(caller_id)
	
	var id : String = request[ENUMS.FUNCTION_DATA.NODE_PATH]
	var function_name : String = request[ENUMS.FUNCTION_DATA.NAME]
	
	var object : Object
	if session_controller.has_resource_by_reference(id):
		object = session_controller.get_resource_by_reference(id)
	else:
		object = get_node_or_null(id)
	
	if object == null:
		session_controller.end_incoming_request()
		logger.write_error("Call function failed since the target Node or Resource was not found. <"+id+"><"+function_name+">")
		return
	if connection_controller.PROTECTED:
		if !session_controller.object_is_exposed(object) and !session_controller.function_is_exposed(object, function_name):
			session_controller.end_incoming_request()
			logger.write_error("Call function failed since the object or function was not exposed. <"+id+"><"+function_name+">")
			push_error("Attempted to call a protected function \""+function_name+"\" on "+id+", please expose it using GDSync.expose_func() or GDSync.expose_node()/GDSync.expose_resource().")
			return
	if !session_controller.object_is_exposed(object):
		if !session_controller.is_caller_permitted(session_controller.get_function_permission(object, function_name)):
			session_controller.end_incoming_request()
			return
	if !object.has_method(function_name):
		session_controller.end_incoming_request()
		logger.write_error("Call function failed since the Node or Resource does not contain the specified function. <"+id+"><"+function_name+">")
		push_error("Attempted to call nonexistent function \""+function_name+"\" on "+id)
		return
	
	var parameters = _request_func_parameters(request, request_type)
	if parameters != null:
		object.callv(function_name, parameters)
	else:
		object.call(function_name)
	session_controller.end_incoming_request()

func set_gdsync_owner_remote(node_path : String, owner) -> void:
	if get_tree().current_scene != null:
		var node : Node = get_node_or_null(node_path)
		if node == null: return
		session_controller.set_gdsync_owner_remote(node, owner)
	else:
		session_controller.set_gdsync_owner_delayed(node_path, owner)

func validate_public_key() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.VALIDATE_KEY,
		connection_controller._PUBLIC_KEY,
		OS.get_unique_id(),
		true,
		connection_controller.API_VERSION,
		connection_controller.PLUGIN_VERSION,
		OS.get_name(),
		Engine.is_editor_hint(),
	]
	
	requestsSETUP.append(request)
	logger.write_log("Validating public key.")

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
	
	requestsSERV.append(api_version_request)
	
	settings_applied = true
	logger.write_log("Applying settings.")

func secure_connection() -> void:
	var connection_generation : int = connection_controller.connection_i
	var request : Array = [
		ENUMS.REQUEST_TYPE.SECURE_CONNECTION
	]
	
	requestsSETUP.append(request)
	
	await self.packets_processed
	if connection_generation != connection_controller.connection_i:
		return
	await get_tree().create_timer(0.5).timeout
	if connection_generation != connection_controller.connection_i:
		return
	connection_controller.status = ENUMS.CONNECTION_STATUS.CONNECTION_SECURED

	if server_switch_controller.connection_secured():
		return
	
	GDSync.emit_signal("connected")

func create_set_var_request(object : Object, variable_name : String, client_id : int, reliable : bool) -> void:
	var request : Array = []
	var id : String
	
	if object is Node:
		id = String(object.get_path())
		
		for i in range(10):
			if object.has_meta("PauseSync"):
				await get_tree().process_frame
	elif object is RefCounted:
		if !session_controller.has_resource_reference(object):
			logger.write_error("Creating set variable request failed, the Resource was not registered. <"+str(object)+"><"+variable_name+">")
			push_error("Resource must be registered using GDSync.register_resource()")
			return
		
		id = session_controller.get_resource_reference(object)
	else:
		return
	
	var permission : int = session_controller.get_property_permission(object, variable_name)
	
	var value = null
	if variable_name in object:
		value = object.get(variable_name)
	
	var encoded_target : int = encode_target_client(client_id, permission)
	
	if !connection_controller.is_local() and session_controller.nodepath_is_cached(id) and session_controller.name_is_cached(variable_name):
		request = _embed_caller_in_sync_request([
			ENUMS.REQUEST_TYPE.SET_VARIABLE_CACHED,
			session_controller.get_nodepath_index(id),
			session_controller.get_name_index(variable_name),
			encoded_target,
		], value)
	else:
		request = _embed_caller_in_sync_request([
			ENUMS.REQUEST_TYPE.SET_VARIABLE,
			id,
			variable_name,
			encoded_target,
		], value)
		
		create_nodepath_cache(id, variable_name)
		create_name_cache(id, variable_name)
	
	_queue_client_request(request, reliable)

func _queue_client_request(request : Array, reliable : bool) -> void:
	if connection_controller.is_web_export:
		reliable = true
	if reliable:
		requestsRUDP.append(request)
	else:
		requestsUDP.append(request)

func create_function_call_request(function : Callable, parameters : Array, client_id : int, reliable : bool, permission_override : int = -1) -> void:
	var object : Object = function.get_object()
	var function_name : String = function.get_method()
	var request : Array = []
	var id : String
	
	if object is Node:
		id = String(object.get_path())
		
		for i in range(10):
			if object.has_meta("PauseSync"):
				await get_tree().process_frame
	elif object is GDScript:
		id = object.resource_path
	elif object is RefCounted:
		if !session_controller.has_resource_reference(object):
			logger.write_error("Creating call function request failed, the Resource was not registered. <"+str(object)+"><"+function_name+">")
			push_error("Resource must be registered using GDSync.register_resource()")
			return
		
		id = session_controller.get_resource_reference(object)
	else:
		return
	
	var permission : int = permission_override if permission_override >= 0 else session_controller.get_function_permission(object, function_name)
	
	var encoded_target : int = encode_target_client(client_id, permission)
	
	if !connection_controller.is_local() and session_controller.nodepath_is_cached(id) and session_controller.name_is_cached(function_name):
		request = _embed_caller_in_sync_request([
			ENUMS.REQUEST_TYPE.CALL_FUNCTION_CACHED,
			session_controller.get_nodepath_index(id),
			session_controller.get_name_index(function_name),
			encoded_target
		], parameters if parameters.size() > 0 else null)
	else:
		request = _embed_caller_in_sync_request([
			ENUMS.REQUEST_TYPE.CALL_FUNCTION,
			id,
			function_name,
			encoded_target
		], parameters if parameters.size() > 0 else null)
		
		create_nodepath_cache(id, function_name)
		create_name_cache(id, function_name)
	
	_queue_client_request(request, reliable)

func create_nodepath_cache(node_path : String, name : String) -> void:
	if connection_controller.is_local(): return
	
	var key : String = node_path+name
	if !node_path_cache_temp.has(key):
		node_path_cache_temp[key] = null
		await get_tree().create_timer(30.0).timeout
		node_path_cache_temp.erase(key)
		return
	
	var request : Array = [
		ENUMS.REQUEST_TYPE.CACHE_NODE_PATH,
		node_path
	]
	
	requestsSERV.append(request)
	logger.write_log("Creating NodePath cache. <"+node_path+">")

func create_erase_nodepath_cache_request(index : int) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_NODE_PATH_CACHE,
		index
	]
	
	requestsSERV.append(request)

func create_name_cache(node_path : String, name : String) -> void:
	if connection_controller.is_local(): return
	
	var key : String = node_path+name
	if !name_cache_temp.has(key):
		name_cache_temp[key] = null
		await get_tree().create_timer(30.0).timeout
		name_cache_temp.erase(key)
		return
	
	var request : Array = [
		ENUMS.REQUEST_TYPE.CACHE_NAME,
		name
	]
	
	requestsSERV.append(request)
	logger.write_log("Creating name cache. <"+name+">")

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
	logger.write_log("Getting public lobbies.")

func create_start_matchmaking_request(parameters: Dictionary) -> void:
	var request: Array = [
		ENUMS.REQUEST_TYPE.START_MATCHMAKING,
		parameters
	]
	requestsSERV.append(request)
	logger.write_log("Starting matchmaking. <"+str(parameters)+">")

func create_cancel_matchmaking_request(request_id: int) -> void:
	requestsSERV.append([ENUMS.REQUEST_TYPE.CANCEL_MATCHMAKING, request_id])
	logger.write_log("Cancelling matchmaking.")

func get_public_lobby(lobby_name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.GET_PUBLIC_LOBBY,
		lobby_name
	]
	
	requestsSERV.append(request)
	logger.write_log("Getting public lobby. <"+str(lobby_name)+">")

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
			"UniqueUsernames" : connection_controller.UNIQUE_USERNAMES,
			"Editor" : Engine.is_editor_hint(),
		}
	]
	
	requestsSERV.append(request)
	logger.write_log("Create lobby. <"+str(request[1])+">")

func create_join_lobby_request(name : String, password : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.JOIN_LOBBY,
		name,
		password
	]
	
	requestsSERV.append(request)
	logger.write_log("Join lobby. <"+str(name)+">")

func create_join_lobby_with_ticket_request(reservation_id: String, proof: String) -> void:
	requestsSERV.append([
		ENUMS.REQUEST_TYPE.JOIN_LOBBY_WITH_TICKET,
		reservation_id,
		proof
	])
	logger.write_log("Joining lobby with reservation.")

func create_tunnel_to_request(destination_address: String) -> void:
	requestsSERV.append([
		ENUMS.REQUEST_TYPE.TUNNEL_TO,
		destination_address
	])
	logger.write_log("Requesting web tunnel. <"+destination_address+">")

func create_commit_server_switch_request(source_address: String, fallback_reservation_id: String) -> void:
	requestsSERV.append([
		ENUMS.REQUEST_TYPE.COMMIT_SERVER_SWITCH,
		source_address,
		fallback_reservation_id
	])

func create_leave_lobby_request() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.LEAVE_LOBBY
	]
	
	requestsSERV.append(request)
	logger.write_log("Leave lobby.")

func create_open_lobby_request() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.OPEN_LOBBY
	]
	
	requestsSERV.append(request)
	logger.write_log("Opening the lobby.")

func create_close_lobby_request() -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.CLOSE_LOBBY
	]
	
	requestsSERV.append(request)
	logger.write_log("Closing the lobby.")

func create_lobby_visiblity_request(public : bool) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_VISIBILITY,
		public
	]
	
	requestsSERV.append(request)
	logger.write_log("Changing lobby visibility. <"+str(public)+">")

func create_change_lobby_password_request(password : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.CHANGE_PASSWORD,
		password
	]
	
	requestsSERV.append(request)
	logger.write_log("Changing lobby password. <"+str(password)+">")

func create_lobby_name_change_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.CHANGE_LOBBY_NAME,
		name
	]
	
	requestsSERV.append(request)
	logger.write_log("Changing lobby name. <"+str(name)+">")

func create_set_host_request(client_id : int) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_HOST,
		client_id
	]
	
	requestsSERV.append(request)
	logger.write_log("Changing lobby host. <"+str(client_id)+">")

func create_set_username_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_PLAYER_USERNAME,
		name
	]
	
	requestsSERV.append(request)
	logger.write_log("Setting username. <"+str(name)+">")

func create_set_player_data_request(name : String, value) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_PLAYER_DATA,
		name,
		value
	]
	
	requestsSERV.append(request)
	logger.write_log("Setting player data. <"+str(name)+"><"+str(value)+">")

func create_erase_player_data_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_PLAYER_DATA,
		name
	]
	
	requestsSERV.append(request)
	logger.write_log("Erasing player data. <"+str(name)+">")

func create_set_lobby_tag_request(name : String, value) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_TAG,
		name,
		value
	]
	
	requestsSERV.append(request)
	logger.write_log("Setting lobby tag. <"+str(name)+"><"+str(value)+">")

func create_erase_lobby_tag_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_LOBBY_TAG,
		name
	]
	
	requestsSERV.append(request)
	logger.write_log("Erasing lobby tag. <"+str(name)+">")

func create_set_lobby_data_request(name : String, value) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_LOBBY_DATA,
		name,
		value
	]
	
	requestsSERV.append(request)
	logger.write_log("Setting lobby data. <"+str(name)+"><"+str(value)+">")

func create_erase_lobby_data_request(name : String) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.ERASE_LOBBY_DATA,
		name
	]
	
	requestsSERV.append(request)
	logger.write_log("Erasing lobby data. <"+str(name)+">")

func set_gdsync_owner(node : Node, owner) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_GDSYNC_OWNER,
		String(node.get_path()),
		owner
	]
	
	requestsSERV.append(request)
	logger.write_log("Setting ownership. <"+str(node.get_path())+"><"+str(owner)+">")

func set_connect_time(connect_time : float) -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.SET_CONNECT_TIME,
		connect_time
	]
	
	requestsSERV.append(request)

func kick_player(client_id : int, reason : String = "") -> void:
	var request : Array = [
		ENUMS.REQUEST_TYPE.KICK_PLAYER,
		client_id
	]
	if !reason.is_empty():
		request.append(reason)
	
	requestsSERV.append(request)
	logger.write_log("Kicking player. <"+str(client_id)+"> Reason: <"+reason+">")
