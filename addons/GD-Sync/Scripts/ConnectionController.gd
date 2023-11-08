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

var GDSync
var request_processor

var _PUBLIC_KEY : String = ""
var _PRIVATE_KEY : String = ""
var _UNIQUE_USERNAMES : bool = false
var _PROTECTED : bool = true

var client : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var client_id : int = -1
var status : int = ENUMS.CONNECTION_STATUS.DISABLED
var host : int = -1
var connecting : bool = false
var connection_i : int = 0

var server_ip : String = ""
var encryptor : AESContext = AESContext.new()
var decryptor : AESContext = AESContext.new()

var lb_request : HTTPRequest

var load_balancers : PackedStringArray = [
	"lb1.gd-sync.com",
	"lb2.gd-sync.com",
	"lb3.gd-sync.com",
]

func _ready():
	name = "ConnectionController"
	process_priority = -1000
	GDSync = get_node("/root/GDSync")
	request_processor = GDSync._request_processor
	lb_request = HTTPRequest.new()
	add_child(lb_request)
	lb_request.timeout = 2.0
	lb_request.request_completed.connect(lb_request_completed)
	
	if ProjectSettings.has_setting("GD-Sync/publicKey"):
		_PUBLIC_KEY = ProjectSettings.get_setting("GD-Sync/publicKey")
	if ProjectSettings.has_setting("GD-Sync/privateKey"):
		_PRIVATE_KEY = ProjectSettings.get_setting("GD-Sync/privateKey")
	if ProjectSettings.has_setting("GD-Sync/protectedMode"):
		_PROTECTED = ProjectSettings.get_setting("GD-Sync/protectedMode")
	if ProjectSettings.has_setting("GD-Sync/uniqueUsername"):
		_UNIQUE_USERNAMES = ProjectSettings.get_setting("GD-Sync/uniqueUsername")
	
	if _PUBLIC_KEY == "" || _PRIVATE_KEY == "":
		push_error("
		No Public or Private key was entered in the GD-Sync setttings. 
		Please add one under Project->Tools->GD-Sync."
		)

func is_active():
	return status >= ENUMS.CONNECTION_STATUS.CONNECTING

func valid_connection() -> bool:
	var own_id : int = GDSync.get_client_id()
	if own_id < 0:
		push_error("No valid connection. Please connect using GDSync.start_multiplayer() first")
		return false
	return true

func reset_multiplayer():
	client.close()
	encryptor.finish()
	decryptor.finish()
	if status > ENUMS.CONNECTION_STATUS.CONNECTED: GDSync.disconnected.emit()
	status = ENUMS.CONNECTION_STATUS.DISABLED
	client_id = -1
	host = -1

func start_multiplayer():
	if status != ENUMS.CONNECTION_STATUS.DISABLED: return
	reset_multiplayer()
	status = ENUMS.CONNECTION_STATUS.FINDING_LB
	
	var load_balancers : Array = self.load_balancers.duplicate()
	load_balancers.shuffle()
	while load_balancers.size() > 0 and status == ENUMS.CONNECTION_STATUS.FINDING_LB:
		var address = load_balancers[randi() % load_balancers.size()]
		load_balancers.erase(address)
		lb_request.request(
			"http://"+address+":8080/connect",
			[],
			HTTPClient.METHOD_GET,
			_PUBLIC_KEY)
		await get_tree().create_timer(2.1).timeout
	
	if status == ENUMS.CONNECTION_STATUS.FINDING_LB:
		reset_multiplayer()
		GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.TIMEOUT)

func stop_multiplayer():
	reset_multiplayer()

func lb_request_completed(result, response_code, headers, body : PackedByteArray):
	if status != ENUMS.CONNECTION_STATUS.FINDING_LB: return
	if response_code == 401:
		reset_multiplayer()
		GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY)
		return
	if response_code != 200:
		return
	status = ENUMS.CONNECTION_STATUS.PINGING_SERVERS
	var serverPings : Dictionary = {}
	
	ping_game_servers(str_to_var(body.get_string_from_ascii()), serverPings)
	await get_tree().create_timer(1.0).timeout
	find_best_server(serverPings)

func ping_game_servers(servers : Array, serverPings : Dictionary):
	for server in servers:
		ping_game_server(server, serverPings)

func ping_game_server(server : String, serverPings : Dictionary):
	var peer : PacketPeerUDP = PacketPeerUDP.new()
	peer.connect_to_host(server, 8081)
	await get_tree().create_timer(0.1).timeout
	
	listen_for_pings(peer, server, serverPings)
	
	for i in range(5):
		peer.put_var(Time.get_ticks_msec())
		await get_tree().create_timer(0.1).timeout
	
	await get_tree().create_timer(0.2)
	status = ENUMS.CONNECTION_STATUS.CONNECTING

func listen_for_pings(peer, server, serverPings):
	var totalPing : int = 0
	var pings : int = 0
	
	while status == ENUMS.CONNECTION_STATUS.PINGING_SERVERS:
		while peer.get_available_packet_count() > 0:
			totalPing += Time.get_ticks_msec()-peer.get_var()
			pings += 1
		await get_tree().create_timer(0.02).timeout
	
	if pings > 0:
		serverPings[totalPing/pings] = server

func find_best_server(serverPings : Dictionary):
	if serverPings.size() == 0:
		GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.TIMEOUT)
		reset_multiplayer()
		return
	
	var pings : Array = serverPings.keys()
	pings.sort()
	var lowestPing : int = pings[0]
	connect_to_server(serverPings[lowestPing])

func connect_to_server(server : String):
	client.create_client(server, 8080)
	
	connection_i += 1
	var current_i : int = connection_i
	
	if status != ENUMS.CONNECTION_STATUS.LOBBY_SWITCH:
		status = ENUMS.CONNECTION_STATUS.CONNECTING
		server_ip = server
		await get_tree().create_timer(8.0).timeout
		if status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return
		if current_i == connection_i:
			if status >= ENUMS.CONNECTION_STATUS.CONNECTING: GDSync.connection_failed.emit(ENUMS.CONNECTION_FAILED.TIMEOUT)
			reset_multiplayer()
	else:
		await get_tree().create_timer(8.0).timeout
		if status == ENUMS.CONNECTION_STATUS.CONNECTION_SECURED: return
		status = ENUMS.CONNECTION_STATUS.CONNECTING
		connect_to_server(server_ip)

func external_lobby_switch(server : String):
	status = ENUMS.CONNECTION_STATUS.LOBBY_SWITCH
	reset_multiplayer()
	connect_to_server(server)

var timePassed : float = 0.0
func _process(delta):
#	print(ENUMS.CONNECTION_STATUS.keys()[status+1])
	match(client.get_connection_status()):
		MultiplayerPeer.CONNECTION_DISCONNECTED:
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
				client.put_packet(request_processor.package_requests(client_id, ENUMS.PACKET_CHANNEL.SETUP))
			if request_processor.has_packets(ENUMS.PACKET_CHANNEL.SERVER):
				client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
				client.put_packet(request_processor.package_requests(client_id, ENUMS.PACKET_CHANNEL.SERVER))
			if request_processor.has_packets(ENUMS.PACKET_CHANNEL.RELIABLE):
				client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
				client.put_packet(request_processor.package_requests(client_id, ENUMS.PACKET_CHANNEL.RELIABLE))
			if request_processor.has_packets(ENUMS.PACKET_CHANNEL.UNRELIABLE):
				client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
				client.put_packet(request_processor.package_requests(client_id, ENUMS.PACKET_CHANNEL.UNRELIABLE))

func set_client_id(client_id : int):
	self.client_id = client_id
	GDSync.client_id_changed.emit(client_id)
	status = ENUMS.CONNECTION_STATUS.CONNECTED
	request_processor.validate_public_key()

func set_client_key(client_key):
	if client_key == null:
		reset_multiplayer()
		GDSync.emit_signal("connection_failed", ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY)
		return
	
	request_processor.secure_connection()
	
	encryptor.start(AESContext.MODE_ECB_ENCRYPT,(_PRIVATE_KEY+client_key).to_utf8_buffer())
	decryptor.start(AESContext.MODE_ECB_DECRYPT,(_PRIVATE_KEY+client_key).to_utf8_buffer())

func set_host(host : int):
	self.host = host
	get_parent().emit_signal("host_changed", host == GDSync.get_client_id(), host)
