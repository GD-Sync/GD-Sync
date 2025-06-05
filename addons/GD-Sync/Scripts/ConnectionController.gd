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

var GDSync
var request_processor
var https_controller
var local_server

const API_VERSION : int = 2

var _PUBLIC_KEY : String = ""
var _PRIVATE_KEY : String = ""
var UNIQUE_USERNAMES : bool = false
var PROTECTED : bool = true
var USE_SENDER_ID : bool = true

var client : MultiplayerPeer = ENetMultiplayerPeer.new()
var client_id : int = -1
var status : int = ENUMS.CONNECTION_STATUS.DISABLED
var host : int = -1
var connecting : bool = false
var connection_i : int = 0
var last_poll : float = 0.0

var server_ip : String = ""
var encryptor : AESContext = AESContext.new()
var decryptor : AESContext = AESContext.new()

var cbc_key : PackedByteArray
var cbc_iv : PackedByteArray

var lb_request : HTTPRequest

var load_balancers : PackedStringArray = [
	"lb1.gd-sync.com",
	"lb2.gd-sync.com",
	"lb3.gd-sync.com",
]

func _ready() -> void:
	name = "ConnectionController"
	process_priority = -1000
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	https_controller = GDSync._https_controller
	local_server = GDSync._local_server
	lb_request = HTTPRequest.new()
	add_child(lb_request)
	lb_request.timeout = 4.0
	lb_request.request_completed.connect(lb_request_completed)
	
	if OS.has_feature("web"):
		client = WebSocketMultiplayerPeer.new()
	
	if ProjectSettings.has_setting("GD-Sync/publicKey"):
		_PUBLIC_KEY = ProjectSettings.get_setting("GD-Sync/publicKey")
	if ProjectSettings.has_setting("GD-Sync/privateKey"):
		_PRIVATE_KEY = ProjectSettings.get_setting("GD-Sync/privateKey")
	if ProjectSettings.has_setting("GD-Sync/protectedMode"):
		PROTECTED = ProjectSettings.get_setting("GD-Sync/protectedMode")
	if ProjectSettings.has_setting("GD-Sync/uniqueUsername"):
		UNIQUE_USERNAMES = ProjectSettings.get_setting("GD-Sync/uniqueUsername")
	if ProjectSettings.has_setting("GD-Sync/useSenderID"):
		USE_SENDER_ID = ProjectSettings.get_setting("GD-Sync/useSenderID")
	
	if _PUBLIC_KEY == "" || _PRIVATE_KEY == "":
		push_error("
		No Public or Private key was entered in the GD-Sync setttings. 
		Please add one under Project->Tools->GD-Sync."
		)

func is_active() -> bool:
	return status >= ENUMS.CONNECTION_STATUS.CONNECTING

func is_local() -> bool:
	return status == ENUMS.CONNECTION_STATUS.LOCAL_CONNECTION

func is_local_check() -> bool:
	if status == ENUMS.CONNECTION_STATUS.LOCAL_CONNECTION:
		push_error("Some features are not available when using GD-Sync in local mode.")
		return true
	return false

func valid_connection() -> bool:
	var own_id : int = GDSync.get_client_id()
	if own_id < 0:
		push_error("No valid connection. Please connect using GDSync.start_multiplayer() first")
		return false
	return true

func reset_multiplayer() -> void:
	var emit_disconnect : bool = status > ENUMS.CONNECTION_STATUS.CONNECTED
	
	client.close()
	local_server.reset_multiplayer()
	
	encryptor.finish()
	decryptor.finish()
	
	status = ENUMS.CONNECTION_STATUS.DISABLED
	client_id = -1
	host = -1
	
	if emit_disconnect: GDSync.disconnected.emit()

func start_multiplayer() -> void:
	if status != ENUMS.CONNECTION_STATUS.DISABLED: return
	reset_multiplayer()
	status = ENUMS.CONNECTION_STATUS.FINDING_LB
	
	last_poll = Time.get_unix_time_from_system()
	
	var load_balancers : Array = self.load_balancers.duplicate()
	load_balancers.shuffle()
	while load_balancers.size() > 0 and status == ENUMS.CONNECTION_STATUS.FINDING_LB:
		var address : String = load_balancers[randi() % load_balancers.size()]
		var complete_url : String = "https://"+address
		https_controller.active_lb = complete_url
		load_balancers.erase(address)
		lb_request.request(
			complete_url+"/connect",
			[],
			HTTPClient.METHOD_GET,
			_PUBLIC_KEY)
		await get_tree().create_timer(4.1).timeout
		lb_request.cancel_request()
	
	if status == ENUMS.CONNECTION_STATUS.FINDING_LB:
		reset_multiplayer()
		GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.TIMEOUT)

func start_local_multiplayer() -> void:
	if status != ENUMS.CONNECTION_STATUS.DISABLED: return
	reset_multiplayer()
	status = ENUMS.CONNECTION_STATUS.LOCAL_CONNECTION
	
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	client_id = abs(rng.randi())
	
	if local_server.start_local_peer():
		GDSync.client_id_changed.emit.call_deferred(client_id)
		GDSync.connected.emit.call_deferred()
	else:
		reset_multiplayer()
		GDSync.connection_failed.emit.call_deferred(ENUMS.CONNECTION_FAILED.LOCAL_PORT_ERROR)

func stop_multiplayer() -> void:
	reset_multiplayer()

func lb_request_completed(result, response_code, headers, body : PackedByteArray) -> void:
	if status != ENUMS.CONNECTION_STATUS.FINDING_LB: return
	if response_code == 401:
		reset_multiplayer()
		GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY)
		return
	if response_code != 200:
		return
	var servers : Array = str_to_var(body.get_string_from_ascii())
	
	if servers.size() == 0:
		return
	status = ENUMS.CONNECTION_STATUS.PINGING_SERVERS
	var serverPings : Dictionary = {}
	
	ping_game_servers(servers, serverPings)
	await get_tree().create_timer(1.0).timeout
	find_best_server(serverPings)

func ping_game_servers(servers : Array, serverPings : Dictionary) -> void:
	for server in servers:
		ping_game_server(server, serverPings)

func ping_game_server(server : String, serverPings : Dictionary) -> void:
	var peer : PacketPeerUDP = PacketPeerUDP.new()
	peer.connect_to_host(server, 8081)
	await get_tree().create_timer(0.1).timeout
	
	listen_for_pings(peer, server, serverPings)
	
	for i in range(5):
		peer.put_var(Time.get_ticks_msec())
		await get_tree().create_timer(0.1).timeout
	
	await get_tree().create_timer(0.2)
	status = ENUMS.CONNECTION_STATUS.CONNECTING

func listen_for_pings(peer, server, serverPings) -> void:
	var totalPing : int = 0
	var pings : int = 0
	
	while status == ENUMS.CONNECTION_STATUS.PINGING_SERVERS:
		while peer.get_available_packet_count() > 0:
			totalPing += Time.get_ticks_msec()-peer.get_var()
			pings += 1
		await get_tree().create_timer(0.02).timeout
	
	if pings > 0:
		serverPings[totalPing/pings] = server

func find_best_server(serverPings : Dictionary) -> void:
	if serverPings.size() == 0:
		GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.TIMEOUT)
		reset_multiplayer()
		return
	
	var pings : Array = serverPings.keys()
	pings.sort()
	var lowestPing : int = pings[0]
	connect_to_server(serverPings[lowestPing])

func connect_to_server(server : String) -> void:
	if OS.has_feature("web"):
		client.create_client("ws://"+server+":8090")
	else:
		client.create_client(server, 8080)
	last_poll = Time.get_unix_time_from_system()
	
	connection_i += 1
	var current_i : int = connection_i
	
	if status != ENUMS.CONNECTION_STATUS.LOBBY_SWITCH:
		status = ENUMS.CONNECTION_STATUS.CONNECTING
		server_ip = server
		await get_tree().create_timer(8.0).timeout
		if status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return
		if current_i == connection_i:
			if status >= ENUMS.CONNECTION_STATUS.CONNECTING:
				GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.TIMEOUT)
			reset_multiplayer()
	else:
		await get_tree().create_timer(8.0).timeout
		if status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return
		status = ENUMS.CONNECTION_STATUS.CONNECTING
		connect_to_server(server_ip)

func connect_to_local_server(server : String) -> int:
	client.close()
	return client.create_client(server, 8080)

func external_lobby_switch(server : String) -> void:
	status = ENUMS.CONNECTION_STATUS.LOBBY_SWITCH
	reset_multiplayer()
	connect_to_server(server)

func _process(delta) -> void:
	if status == ENUMS.CONNECTION_STATUS.CONNECTED:
		var current_time : float = Time.get_unix_time_from_system()
		if current_time - last_poll >= 5:
			reset_multiplayer()
		last_poll = current_time
	
	match(client.get_connection_status()):
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			if is_local():
				pass
			else:
				if status >= ENUMS.CONNECTION_STATUS.CONNECTED: reset_multiplayer()
		MultiplayerPeer.CONNECTION_CONNECTING:
			client.poll()
		MultiplayerPeer.CONNECTION_CONNECTED:
			client.poll()
		
			while client.get_available_packet_count() > 0:
				var bytes : PackedByteArray = client.get_packet()
				request_processor.unpack_packet(bytes)
			
			if request_processor.has_packets(ENUMS.PACKET_CHANNEL.SETUP):
				client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
				client.transfer_channel = 0
				client.put_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.SETUP))
			if request_processor.has_packets(ENUMS.PACKET_CHANNEL.SERVER):
				client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
				client.transfer_channel = 0
				client.put_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.SERVER))
			if request_processor.has_packets(ENUMS.PACKET_CHANNEL.RELIABLE):
				client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
				client.transfer_channel = 0
				client.put_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.RELIABLE))
			if request_processor.has_packets(ENUMS.PACKET_CHANNEL.UNRELIABLE):
				client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
				client.transfer_channel = 1
				client.put_packet(request_processor.package_requests(ENUMS.PACKET_CHANNEL.UNRELIABLE))

func set_client_id(client_id : int) -> void:
	self.client_id = client_id
	GDSync.client_id_changed.emit(client_id)
	status = ENUMS.CONNECTION_STATUS.CONNECTED
	request_processor.validate_public_key()

func set_client_key(client_key) -> void:
	if client_key == null:
		reset_multiplayer()
		GDSync.emit_signal("connection_failed", ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY)
		return
	
	request_processor.apply_settings()
	request_processor.secure_connection()
	
	cbc_key = _PRIVATE_KEY.to_utf8_buffer()
	cbc_iv = client_key.to_utf8_buffer()
	
	refresh_encryptor()
	refresh_decryptor()

func refresh_encryptor() -> void:
	encryptor.finish()
	encryptor.start(AESContext.MODE_CBC_ENCRYPT, cbc_key, cbc_iv)

func refresh_decryptor() -> void:
	decryptor.finish()
	decryptor.start(AESContext.MODE_CBC_DECRYPT, cbc_key, cbc_iv)

func set_host(host : int) -> void:
	self.host = host
	get_parent().emit_signal("host_changed", host == GDSync.get_client_id(), host)
