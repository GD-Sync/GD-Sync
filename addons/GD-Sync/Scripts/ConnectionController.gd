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

var GDSync
var request_processor
var https_controller
var local_server
var logger

const API_VERSION : int = 6
const PLUGIN_VERSION : String = "1.0"

const KeyStore = preload("res://addons/GD-Sync/Scripts/KeyStore.gd")

var _PUBLIC_KEY : String = ""
var _PRIVATE_KEY : String = ""
var UNIQUE_USERNAMES : bool = false
var PROTECTED : bool = true

var client : PacketPeer = ENetMultiplayerPeer.new()
var client_id : int = -1
var status : int = ENUMS.CONNECTION_STATUS.DISABLED
var host : int = -1
var connecting : bool = false
var connection_i : int = 0
var _connect_generation : int = 0
var last_poll : float = 0.0
var in_local_lobby : bool = false
var attempt_tcp : bool = false
var is_web_export : bool = false
var web_hub_host : String = ""

var server_ip : String = ""
var reliable_encryptor : AESContext = AESContext.new()
var reliable_decryptor : AESContext = AESContext.new()
var unreliable_encryptor : AESContext = AESContext.new()
var unreliable_decryptor : AESContext = AESContext.new()

var _session_aes_key : PackedByteArray = PackedByteArray()
var _session_crypto_ready : bool = false

var artificial_latency_ms : int = 0

const _LB_TIMEOUT_MS : int = 2000
const _UDP_PING_EARLY_MS : int = 400
const _UDP_PING_CAP_MS : int = 600
const _CONNECT_TIMEOUT_S : float = 4.0
const _SWITCH_CONNECT_TIMEOUT_S : float = 8.0

var load_balancers : PackedStringArray = [
	"lb1.gd-sync.com",
	"lb2.gd-sync.com",
]

var web_servers : PackedStringArray = [
	"ws1.gd-sync.com",
	"ws2.gd-sync.com",
]

func _ready() -> void:
	name = "ConnectionController"
	process_priority = -1000
	
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	https_controller = GDSync._https_controller
	local_server = GDSync._local_server
	logger = GDSync._logger
	is_web_export = OS.has_feature("web")
	
	var keys : Dictionary = KeyStore.load_keys()
	_PUBLIC_KEY = keys["PublicKey"]
	_PRIVATE_KEY = keys["PrivateKey"]
	
	if ProjectSettings.has_setting("GD-Sync/protectedMode"):
		PROTECTED = ProjectSettings.get_setting("GD-Sync/protectedMode")
	if ProjectSettings.has_setting("GD-Sync/uniqueUsername"):
		UNIQUE_USERNAMES = ProjectSettings.get_setting("GD-Sync/uniqueUsername")
	
	logger.register_redacted_value(_PUBLIC_KEY)
	logger.register_redacted_value(_PRIVATE_KEY)
	
	if _PUBLIC_KEY == "" || _PRIVATE_KEY == "":
		logger.write_error("No Public or Private key was entered in the GD-Sync settings. Please add one under Project->Tools->GD-Sync. If you are using local multiplayer only, you can ignore this error.")

func is_active() -> bool:
	return status >= ENUMS.CONNECTION_STATUS.CONNECTING

func is_local() -> bool:
	return status == ENUMS.CONNECTION_STATUS.LOCAL_CONNECTION

func is_local_check() -> bool:
	if status == ENUMS.CONNECTION_STATUS.LOCAL_CONNECTION:
		logger.write_error("Some features are not available when using GD-Sync in local mode.")
		return true
	return false

func valid_connection() -> bool:
	var own_id : int = GDSync.get_client_id()
	if own_id < 0:
		logger.write_error("No valid connection. Please connect using GDSync.start_multiplayer() first")
		return false
	return true

func reset_multiplayer(force_disconnect_signal : bool = false) -> void:
	var emit_disconnect : bool = force_disconnect_signal or status > ENUMS.CONNECTION_STATUS.CONNECTED
	_connect_generation += 1
	
	client.close()
	local_server.reset_multiplayer()
	_reset_session_crypto()
	
	status = ENUMS.CONNECTION_STATUS.DISABLED
	client_id = -1
	host = -1
	in_local_lobby = false
	attempt_tcp = false
	
	if emit_disconnect: GDSync.disconnected.emit()

func reset_session_keep_socket() -> void:
	connection_i += 1
	_reset_session_crypto()
	client_id = -1
	host = -1
	in_local_lobby = false
	status = ENUMS.CONNECTION_STATUS.CONNECTING
	logger.write_log("Reset session crypto for web tunnel handshake.")

func _reset_session_crypto() -> void:
	reliable_encryptor.finish()
	reliable_decryptor.finish()
	unreliable_encryptor.finish()
	unreliable_decryptor.finish()
	_session_crypto_ready = false

func start_multiplayer() -> void:
	logger.write_log("Starting multiplayer.")
	if status != ENUMS.CONNECTION_STATUS.DISABLED:
		logger.write_error("Multiplayer has already been started.")
		return
	
	reset_multiplayer()
	var gen : int = _connect_generation
	last_poll = Time.get_unix_time_from_system()
	
	if is_web_export:
		await _start_web_connect(gen)
	else:
		await _start_native_connect(gen)

func _connect_is_current(gen : int) -> bool:
	return gen == _connect_generation

func _fail_connect(gen : int, error : int, message : String) -> void:
	if !_connect_is_current(gen):
		return
	logger.write_error(message)
	reset_multiplayer()
	GDSync.connection_failed.emit(error)

func _start_native_connect(gen : int) -> void:
	status = ENUMS.CONNECTION_STATUS.FINDING_LB
	var lb_result : Dictionary = await _fetch_game_servers(gen)
	if !_connect_is_current(gen):
		return
	var servers : Array = lb_result.get("servers", [])
	if servers.is_empty():
		if lb_result.get("invalid_key", false):
			_fail_connect(gen, ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY,
				"Load balancer request failed, incorrect public key.")
		else:
			_fail_connect(gen, ENUMS.CONNECTION_FAILED.TIMEOUT, "No response from load balancers.")
		return
	
	status = ENUMS.CONNECTION_STATUS.PINGING_SERVERS
	var ranked : Array = await _rank_game_servers(servers, gen)
	if !_connect_is_current(gen):
		return
	if ranked.is_empty():
		_fail_connect(gen, ENUMS.CONNECTION_FAILED.TIMEOUT, "No pings received from any server.")
		return
	
	status = ENUMS.CONNECTION_STATUS.CONNECTING
	var best : String = ranked[0]
	for server in ranked:
		if !_connect_is_current(gen):
			return
		client.close()
		client = ENetMultiplayerPeer.new()
		if await _try_connect(server, gen, _CONNECT_TIMEOUT_S):
			return
	
	if !_connect_is_current(gen):
		return
	logger.write_log("Attempting TCP connection.")
	attempt_tcp = true
	client.close()
	client = WebSocketMultiplayerPeer.new()
	if await _try_connect(best, gen, _CONNECT_TIMEOUT_S):
		return
	_fail_connect(gen, ENUMS.CONNECTION_FAILED.TIMEOUT, "Connection timeout, server did not respond.")

func _start_web_connect(gen : int) -> void:
	client = WebSocketPeer.new()
	status = ENUMS.CONNECTION_STATUS.PINGING_SERVERS
	var lb_state : Dictionary = { "done": false, "invalid_key": false }
	_resolve_lb_for_web(gen, lb_state)
	var ranked : Array = await _rank_web_servers(gen)
	if !_connect_is_current(gen):
		return
	if ranked.is_empty():
		_fail_connect(gen, ENUMS.CONNECTION_FAILED.TIMEOUT, "No reachable web servers.")
		return
	
	var waited_ms : int = 0
	while !lb_state.done and waited_ms < _LB_TIMEOUT_MS:
		if !_connect_is_current(gen):
			return
		await get_tree().create_timer(0.05).timeout
		waited_ms += 50
	if !_connect_is_current(gen):
		return
	if lb_state.invalid_key:
		_fail_connect(gen, ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY,
			"Load balancer request failed, incorrect public key.")
		return
	
	status = ENUMS.CONNECTION_STATUS.CONNECTING
	for host in ranked:
		if !_connect_is_current(gen):
			return
		client.close()
		client = WebSocketPeer.new()
		web_hub_host = host
		if await _try_connect("wss://"+host, gen, _CONNECT_TIMEOUT_S):
			return
	_fail_connect(gen, ENUMS.CONNECTION_FAILED.TIMEOUT, "Connection timeout, server did not respond.")

func _resolve_lb_for_web(gen : int, lb_state : Dictionary) -> void:
	var lb_result : Dictionary = await _fetch_game_servers(gen)
	if !_connect_is_current(gen):
		lb_state.done = true
		return
	lb_state.invalid_key = lb_result.get("invalid_key", false)
	lb_state.done = true
	if https_controller.active_lb.is_empty() and !lb_state.invalid_key:
		logger.write_error("No load balancer resolved for web HTTPS API.")

func start_local_multiplayer() -> void:
	logger.write_log("Starting local multiplayer.")
	if status != ENUMS.CONNECTION_STATUS.DISABLED: return
	reset_multiplayer()
	status = ENUMS.CONNECTION_STATUS.LOCAL_CONNECTION
	
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	client_id = abs(rng.randi())
	logger.write_log("Local client id generated. <"+str(client_id)+">")
	
	if local_server.start_local_peer():
		logger.write_log("Local multiplayer started.")
		GDSync.client_id_changed.emit.call_deferred(client_id)
		GDSync.connected.emit.call_deferred()
	else:
		logger.write_error("Local multiplayer failed to start, port is in use.")
		reset_multiplayer()
		GDSync.connection_failed.emit.call_deferred(ENUMS.CONNECTION_FAILED.LOCAL_PORT_ERROR)

func stop_multiplayer() -> void:
	logger.write_log("Stopping multiplayer.")
	reset_multiplayer()

func _fetch_game_servers(gen : int) -> Dictionary:
	var result : Dictionary = { "servers": [], "invalid_key": false }
	var lbs : Array = load_balancers.duplicate()
	lbs.shuffle()
	if lbs.is_empty():
		return result
	
	logger.write_log("Requesting servers from load balancers.")
	var winner : Dictionary = { "taken": false }
	var finished : int = 0
	var inflight : Array = []
	
	for address in lbs:
		_query_load_balancer(str(address), gen, result, winner, inflight, func(): finished += 1)
	
	var waited_ms : int = 0
	while waited_ms < _LB_TIMEOUT_MS:
		if !_connect_is_current(gen):
			break
		if result.invalid_key or winner.taken:
			break
		if finished >= lbs.size():
			break
		await get_tree().create_timer(0.05).timeout
		waited_ms += 50
	
	_cancel_http_requests(inflight)
	return result

func _query_load_balancer(
	address : String,
	gen : int,
	result : Dictionary,
	winner : Dictionary,
	inflight : Array,
	on_done : Callable
) -> void:
	logger.write_log("Requesting servers from "+address)
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = _LB_TIMEOUT_MS / 1000.0
	add_child(request)
	inflight.append(request)
	
	var err : Error = request.request(
		"https://"+address+"/connect",
		["Content-Type: text/plain"],
		HTTPClient.METHOD_POST,
		_PUBLIC_KEY)
	if err != OK:
		logger.write_error("Load balancer request failed to start. <"+address+"><"+str(err)+">")
		inflight.erase(request)
		request.queue_free()
		on_done.call()
		return
	
	var completed : Array = await request.request_completed
	inflight.erase(request)
	if is_instance_valid(request):
		request.queue_free()
	if !_connect_is_current(gen):
		on_done.call()
		return
	
	var response_code : int = completed[1]
	logger.write_log("Load balancer completed. <"+address+"><"+str(response_code)+">")
	if response_code == 401:
		if !winner.taken:
			result.invalid_key = true
		on_done.call()
		return
	if response_code != 200:
		logger.write_error("Load balancer request failed. <"+str(response_code)+">")
		on_done.call()
		return
	
	var parsed : Variant = str_to_var(completed[3].get_string_from_ascii())
	if typeof(parsed) != TYPE_ARRAY or parsed.is_empty():
		logger.write_error("Load balancer request did not return any servers. <"+address+">")
		on_done.call()
		return
	if winner.taken:
		on_done.call()
		return
	
	winner.taken = true
	result.servers = parsed
	https_controller.active_lb = "https://"+address
	logger.write_log("Received servers decoded. <"+str(parsed)+">")
	on_done.call()

func _cancel_http_requests(inflight : Array) -> void:
	for request in inflight:
		if request is HTTPRequest and is_instance_valid(request):
			request.cancel_request()

func _rank_game_servers(servers : Array, gen : int) -> Array:
	logger.write_log("Pinging game servers. <"+str(servers)+">")
	var replies : Dictionary = {}
	for server in servers:
		_ping_game_server(str(server), replies, gen)
	
	var waited_ms : int = 0
	while waited_ms < _UDP_PING_CAP_MS:
		if !_connect_is_current(gen):
			return []
		if _all_servers_replied(servers, replies):
			break
		if waited_ms >= _UDP_PING_EARLY_MS and replies.size() > 0:
			break
		await get_tree().create_timer(0.02).timeout
		waited_ms += 20
	
	logger.write_log("Finding best server <"+str(replies)+">")
	if replies.is_empty():
		return []
	
	var ranked : Array = []
	for server in replies:
		ranked.append({ "server": server, "ping": float(replies[server].total) / replies[server].count })
	ranked.sort_custom(func(a, b): return a.ping < b.ping)
	
	var hosts : Array = []
	for entry in ranked:
		hosts.append(entry.server)
		logger.write_log("Game server ping. <"+str(entry.server)+"><"+str(entry.ping)+"ms>")
	return hosts

func _all_servers_replied(servers : Array, replies : Dictionary) -> bool:
	if servers.is_empty():
		return false
	for server in servers:
		if !replies.has(str(server)):
			return false
	return true

func _ping_game_server(server : String, replies : Dictionary, gen : int) -> void:
	logger.write_log("Pinging game server. <"+server+">")
	var peer : PacketPeerUDP = PacketPeerUDP.new()
	peer.connect_to_host(server, 8081)
	
	var total : int = 0
	var count : int = 0
	var sends : int = 0
	var elapsed_ms : int = 0
	while _connect_is_current(gen) and status == ENUMS.CONNECTION_STATUS.PINGING_SERVERS and elapsed_ms < _UDP_PING_CAP_MS:
		if sends < 3 and elapsed_ms >= sends * 50:
			peer.put_var(Time.get_ticks_msec())
			sends += 1
		while peer.get_available_packet_count() > 0:
			var sent_at : Variant = peer.get_var()
			if typeof(sent_at) == TYPE_INT:
				total += Time.get_ticks_msec() - int(sent_at)
				count += 1
				logger.write_log("Ping received. <"+server+">")
		await get_tree().create_timer(0.02).timeout
		elapsed_ms += 20
	peer.close()
	if count > 0 and _connect_is_current(gen):
		replies[server] = { "total": total, "count": count }

func connect_to_server(server : String) -> void:
	logger.write_log("Connecting to server. <"+server+">")
	_begin_client_connect(server)
	last_poll = Time.get_unix_time_from_system()
	connection_i += 1
	var current_i : int = connection_i
	var gen : int = _connect_generation
	if status != ENUMS.CONNECTION_STATUS.LOBBY_SWITCH:
		status = ENUMS.CONNECTION_STATUS.CONNECTING
	server_ip = server
	
	var elapsed : float = 0.0
	while elapsed < _SWITCH_CONNECT_TIMEOUT_S:
		if current_i != connection_i or !_connect_is_current(gen):
			return
		if status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
			return
		if elapsed >= 0.3 and _client_connect_lost():
			break
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	
	if current_i != connection_i or !_connect_is_current(gen):
		return
	if status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
		return
	
	logger.write_error("Connection timeout, server did not respond.")
	if GDSync._server_switch_controller.transport_failed():
		return
	GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.TIMEOUT)
	reset_multiplayer()

func _try_connect(address : String, gen : int, timeout_s : float) -> bool:
	if !_connect_is_current(gen):
		return false
	logger.write_log("Connecting to server. <"+address+">")
	_begin_client_connect(address)
	last_poll = Time.get_unix_time_from_system()
	server_ip = address
	if status != ENUMS.CONNECTION_STATUS.LOBBY_SWITCH:
		status = ENUMS.CONNECTION_STATUS.CONNECTING
	connection_i += 1
	var current_i : int = connection_i
	
	var elapsed : float = 0.0
	while elapsed < timeout_s:
		if !_connect_is_current(gen) or current_i != connection_i:
			return false
		if status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED:
			return true
		if elapsed >= 0.3 and _client_connect_lost():
			return false
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	return _connect_is_current(gen) and current_i == connection_i and status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED

func _client_connect_lost() -> bool:
	if client is MultiplayerPeer:
		return client.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
	if client is WebSocketPeer:
		return client.get_ready_state() == WebSocketPeer.STATE_CLOSED
	return false

func _begin_client_connect(server : String) -> void:
	if client is WebSocketPeer:
		logger.write_log("Connecting using TCP.")
		client.connect_to_url(server)
	elif client is WebSocketMultiplayerPeer:
		logger.write_log("Connecting using TCP multiplayer.")
		client.create_client(server)
	else:
		logger.write_log("Connecting using UDP.")
		client.create_client(server, 8080)

func connect_to_local_server(server : String) -> int:
	logger.write_log("Connecting to local server. <"+server+">")
	
	client.close()
	client = ENetMultiplayerPeer.new()
	return client.create_client(server, 8080)

func _rank_web_servers(gen : int) -> Array:
	logger.write_log("HTTPS pinging web servers. <"+str(web_servers)+">")
	var server_pings : Dictionary = {}
	var tasks_done : int = 0
	var total : int = web_servers.size()
	
	for host in web_servers:
		_ping_web_server(host, server_pings, gen, func(): tasks_done += 1)
	
	var waited_ms : int = 0
	while tasks_done < total and waited_ms < 4500:
		if !_connect_is_current(gen):
			return []
		await get_tree().create_timer(0.05).timeout
		waited_ms += 50
	
	if !_connect_is_current(gen) or server_pings.is_empty():
		logger.write_error("No HTTPS pings received from web servers.")
		return []
	
	var pings : Array = server_pings.keys()
	pings.sort()
	var ranked : Array = []
	for ping in pings:
		ranked.append(server_pings[ping])
		logger.write_log("Web server ping. <"+str(server_pings[ping])+"><"+str(ping)+"ms>")
	logger.write_log("Best web server selected. <"+str(ranked[0])+"><"+str(pings[0])+"ms>")
	return ranked

func _ping_web_server(host : String, server_pings : Dictionary, gen : int, on_done : Callable) -> void:
	var latency_ms : float = await https_controller.ping_https("https://"+host+"/ping", 3.0)
	if !_connect_is_current(gen):
		on_done.call()
		return
	if latency_ms >= 0.0:
		var key : float = latency_ms
		while server_pings.has(key):
			key += 0.001
		server_pings[key] = host
		logger.write_log("Web server ping. <"+host+"><"+str(latency_ms)+"ms>")
	on_done.call()

func switch_server(server: String, use_websocket: bool = false) -> void:
	logger.write_log("Switching server. <"+server+">")
	status = ENUMS.CONNECTION_STATUS.LOBBY_SWITCH
	reset_multiplayer()
	attempt_tcp = false
	if is_web_export:
		client = WebSocketPeer.new()
		var hub := web_hub_host
		if hub.is_empty():
			logger.write_error("Web hub host missing during server switch.")
			connect_to_server("wss://"+server)
			return
		logger.write_log("Reconnecting to web hub. <"+hub+">")
		connect_to_server("wss://"+hub)
		return
	client = WebSocketMultiplayerPeer.new() if use_websocket else ENetMultiplayerPeer.new()
	var destination := server
	if use_websocket and !destination.begins_with("ws://") and !destination.begins_with("wss://"):
		destination = "wss://"+destination
	connect_to_server(destination)

func set_artificial_latency(latency_ms : int) -> void:
	artificial_latency_ms = maxi(latency_ms, 0)

func get_artificial_latency() -> int:
	return artificial_latency_ms

func _await_artificial_latency() -> void:
	if artificial_latency_ms <= 0:
		return
	await get_tree().create_timer(artificial_latency_ms / 1000.0).timeout

func _receive_packet(bytes : PackedByteArray, packet_channel : int) -> void:
	await _await_artificial_latency()
	if status < ENUMS.CONNECTION_STATUS.CONNECTING:
		return
	request_processor.unpack_packet(bytes, packet_channel)

func _send_multiplayer_packet(bytes : PackedByteArray, transfer_mode : int, transfer_channel : int) -> void:
	await _await_artificial_latency()
	if !(client is MultiplayerPeer) or client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	client.transfer_mode = transfer_mode
	client.transfer_channel = transfer_channel
	client.put_packet(bytes)

func _send_websocket_packet(bytes : PackedByteArray) -> void:
	await _await_artificial_latency()
	if !(client is WebSocketPeer) or client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	client.send(bytes)

func _process(delta) -> void:
	if status >= ENUMS.CONNECTION_STATUS.CONNECTED and !is_local() and !is_web_export:
		var current_time : float = Time.get_unix_time_from_system()
		if current_time - last_poll >= 10:
			logger.write_error("Client did not poll for over 10 seconds, disconnect.")
			reset_multiplayer()
		last_poll = current_time
	
	if client is MultiplayerPeer:
		match(client.get_connection_status()):
			MultiplayerPeer.CONNECTION_DISCONNECTED:
				if !is_local() or in_local_lobby:
					if status >= ENUMS.CONNECTION_STATUS.CONNECTED:
						logger.write_error("MultiplayerPeer lost its connection.")
						if GDSync._server_switch_controller.transport_failed():
							return
						reset_multiplayer()
			MultiplayerPeer.CONNECTION_CONNECTING:
				client.poll()
			MultiplayerPeer.CONNECTION_CONNECTED:
				client.poll()
			
				while client.get_available_packet_count() > 0:
					var packet_channel : int = client.get_packet_channel()
					var bytes : PackedByteArray = client.get_packet()
					_receive_packet(bytes, packet_channel)
				
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.SETUP):
					_send_multiplayer_packet(
						request_processor.package_requests(ENUMS.PACKET_CHANNEL.SETUP),
						MultiplayerPeer.TRANSFER_MODE_RELIABLE,
						0
					)
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.SERVER):
					_send_multiplayer_packet(
						request_processor.package_requests(ENUMS.PACKET_CHANNEL.SERVER),
						MultiplayerPeer.TRANSFER_MODE_RELIABLE,
						0
					)
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.RELIABLE):
					_send_multiplayer_packet(
						request_processor.package_requests(ENUMS.PACKET_CHANNEL.RELIABLE),
						MultiplayerPeer.TRANSFER_MODE_RELIABLE,
						0
					)
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.UNRELIABLE):
					_send_multiplayer_packet(
						request_processor.package_requests(ENUMS.PACKET_CHANNEL.UNRELIABLE),
						MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,
						1
					)
	
	elif client is WebSocketPeer:
		match(client.get_ready_state()):
			WebSocketPeer.STATE_CLOSED:
				if !is_local() or in_local_lobby:
					if GDSync._server_switch_controller.is_active():
						logger.write_error("WebSocketPeer lost its connection during server switch.")
						GDSync._server_switch_controller.transport_failed()
					elif status >= ENUMS.CONNECTION_STATUS.CONNECTED:
						logger.write_error("WebSocketPeer lost its connection.")
						reset_multiplayer()
			WebSocketPeer.STATE_CLOSING:
				client.poll()
			WebSocketPeer.STATE_CONNECTING:
				client.poll()
			WebSocketPeer.STATE_OPEN:
				client.poll()
			
				while client.get_available_packet_count() > 0:
					var bytes : PackedByteArray = client.get_packet()
					_receive_packet(bytes, 0)
				
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.SETUP):
					_send_websocket_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.SETUP))
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.SERVER):
					_send_websocket_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.SERVER))
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.RELIABLE):
					_send_websocket_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.RELIABLE))
				if request_processor.has_packets(ENUMS.PACKET_CHANNEL.UNRELIABLE):
					_send_websocket_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.UNRELIABLE))

func set_client_id(client_id : int) -> void:
	logger.write_log("Client id received from server. <"+str(client_id)+">")
	logger.register_profiler_data("client_id", client_id)
	self.client_id = client_id
	GDSync.client_id_changed.emit(client_id)
	status = ENUMS.CONNECTION_STATUS.CONNECTED
	request_processor.validate_public_key()

func set_client_key(client_key: String) -> void:
	logger.write_log("Client key received from server. <" + client_key + ">")
	if client_key.is_empty():
		logger.write_error("Client key was empty or public key invalid.")
		reset_multiplayer()
		GDSync.emit_signal("connection_failed", ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY)
		return
	
	request_processor.apply_settings()
	request_processor.secure_connection()
	
	var key_utf8 : PackedByteArray = _PRIVATE_KEY.to_utf8_buffer()
	var client_utf8 : PackedByteArray = client_key.to_utf8_buffer()
	_session_crypto_ready = false
	unreliable_encryptor.finish()
	unreliable_decryptor.finish()
	
	_session_aes_key = _derive_session_aes_key(key_utf8, client_utf8)
	var iv16 : PackedByteArray = _derive_session_iv(client_utf8)
	reliable_encryptor.finish()
	reliable_decryptor.finish()
	reliable_encryptor.start(AESContext.MODE_CBC_ENCRYPT, _session_aes_key, iv16)
	reliable_decryptor.start(AESContext.MODE_CBC_DECRYPT, _session_aes_key, iv16)
	unreliable_encryptor.start(AESContext.MODE_ECB_ENCRYPT, _session_aes_key)
	unreliable_decryptor.start(AESContext.MODE_ECB_DECRYPT, _session_aes_key)
	_session_crypto_ready = true

func is_session_crypto_ready() -> bool:
	return _session_crypto_ready

func _derive_session_aes_key(key_utf8 : PackedByteArray, client_key_utf8 : PackedByteArray) -> PackedByteArray:
	var ctx : HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(key_utf8)
	ctx.update(client_key_utf8)
	return ctx.finish()

func _derive_session_iv(client_key_utf8 : PackedByteArray) -> PackedByteArray:
	var label : PackedByteArray = "gdsync:v3:aes-cbc:iv".to_utf8_buffer()
	var ctx : HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(label)
	ctx.update(client_key_utf8)
	var h : PackedByteArray = ctx.finish()
	return h.slice(0, 16)

func _pkcs7_pad(blocks : PackedByteArray) -> PackedByteArray:
	var n : int = 16 - (blocks.size() % 16)
	if n == 0:
		n = 16
	var outb : PackedByteArray = blocks.duplicate()
	for i in range(n):
		outb.append(n)
	return outb

func _pkcs7_unpad(blocks : PackedByteArray) -> PackedByteArray:
	if blocks.is_empty() or (blocks.size() % 16) != 0:
		return PackedByteArray()
	var n : int = blocks[blocks.size() - 1]
	if n < 1 or n > 16 or n > blocks.size():
		return PackedByteArray()
	for i in range(n):
		if blocks[blocks.size() - 1 - i] != n:
			return PackedByteArray()
	return blocks.slice(0, blocks.size() - n)

func encrypt_secured_payload(plain : PackedByteArray, reliable_channel : bool) -> PackedByteArray:
	if !_session_crypto_ready:
		logger.write_error("encrypt_secured_payload called before session crypto is ready.")
		return plain
	var padded : PackedByteArray = _pkcs7_pad(plain)
	if reliable_channel:
		return reliable_encryptor.update(padded)
	return unreliable_encryptor.update(padded)

func decrypt_secured_payload(cipher : PackedByteArray, reliable_channel : bool) -> PackedByteArray:
	if !_session_crypto_ready:
		logger.write_error("decrypt_secured_payload called before session crypto is ready.")
		return PackedByteArray()
	if reliable_channel:
		var dec : PackedByteArray = reliable_decryptor.update(cipher)
		return _pkcs7_unpad(dec)
	var dec2 : PackedByteArray = unreliable_decryptor.update(cipher)
	return _pkcs7_unpad(dec2)

func set_host(host : int) -> void:
	logger.write_log("Host changed. <"+str(host)+">")
	self.host = host
	var is_host : bool = host == GDSync.get_client_id()
	logger.register_profiler_data("is_host", is_host)
	logger.register_profiler_data("host", host)
	get_parent().emit_signal("host_changed", is_host, host)
