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

enum State {
	IDLE,
	CONNECTING_DESTINATION,
	TUNNELING,
	JOINING_DESTINATION,
	ROLLING_BACK,
	TUNNELING_ROLLBACK,
	RESTORING_SOURCE,
}

const _STATE_TIMEOUT_MS : int = 20000

var GDSync
var connection_controller
var request_processor
var session_controller
var matchmaking_controller
var logger

var state: State = State.IDLE
var _state_deadline: int = 0
var _reservation_deadline: int = 0
var source_address: String = ""
var destination_address: String = ""
var reservation_id: String = ""
var proof: String = ""
var lobby_name: String = ""
var connect_time: float = 0.0
var fallback_reservation_id: String = ""
var rollback_error: int = ENUMS.LOBBY_SWITCH_ERROR.DESTINATION_UNREACHABLE
var use_websocket: bool = false
var pending_tunnel_address: String = ""


func _ready() -> void:
	name = "ServerSwitchController"
	connection_controller = GDSync._connection_controller
	request_processor = GDSync._request_processor
	session_controller = GDSync._session_controller
	matchmaking_controller = GDSync._matchmaking_controller
	logger = GDSync._logger


func begin(data: Dictionary) -> void:
	reset()
	source_address = str(data.get("SourceAddress", connection_controller.server_ip))
	destination_address = str(data.get("Address", ""))
	reservation_id = str(data.get("ReservationId", ""))
	proof = str(data.get("Proof", ""))
	lobby_name = str(data.get("LobbyName", ""))
	connect_time = float(data.get("ConnectTime", 0.0))
	fallback_reservation_id = str(data.get("FallbackReservationId", ""))
	use_websocket = (
		connection_controller.client is WebSocketPeer
		or connection_controller.client is WebSocketMultiplayerPeer
		or connection_controller.is_web_export
	)
	if destination_address.is_empty() or reservation_id.is_empty() or proof.is_empty():
		fail_permanently(ENUMS.LOBBY_SWITCH_ERROR.INVALID_RESERVATION)
		return

	var expires_in := maxf(float(data.get("ExpiresIn", 20.0)), 1.0)
	_reservation_deadline = Time.get_ticks_msec() + int(expires_in * 1000.0)
	_set_state(State.CONNECTING_DESTINATION)
	pending_tunnel_address = destination_address
	request_processor.clear_for_server_switch()
	connection_controller.switch_server(destination_address, use_websocket)


func is_active() -> bool:
	return state != State.IDLE


func _process(_delta : float) -> void:
	if state == State.IDLE: return
	
	var now : int = Time.get_ticks_msec()
	
	if _reservation_deadline > 0 and now >= _reservation_deadline:
		_reservation_deadline = 0
		_timed_out(ENUMS.LOBBY_SWITCH_ERROR.RESERVATION_EXPIRED)
		return
	
	if _state_deadline > 0 and now >= _state_deadline:
		_timed_out(ENUMS.LOBBY_SWITCH_ERROR.DESTINATION_UNREACHABLE)


func _set_state(new_state : State) -> void:
	state = new_state
	
	if new_state == State.IDLE:
		_state_deadline = 0
		_reservation_deadline = 0
		return
	
	_refresh_state_deadline()


func _refresh_state_deadline() -> void:
	_state_deadline = Time.get_ticks_msec() + _STATE_TIMEOUT_MS


func _is_rollback_state() -> bool:
	return (
		state == State.ROLLING_BACK
		or state == State.TUNNELING_ROLLBACK
		or state == State.RESTORING_SOURCE
	)


func _timed_out(error : int) -> void:
	logger.write_error("Server switch timed out. <"+str(State.keys()[state])+">")
	
	if _is_rollback_state():
		fail_permanently(ENUMS.LOBBY_SWITCH_ERROR.ROLLBACK_FAILED)
		return
	
	if state == State.JOINING_DESTINATION:
		rollback(ENUMS.LOBBY_SWITCH_ERROR.JOIN_FAILED)
		return
	
	rollback(error)


func _should_web_tunnel() -> bool:
	return connection_controller.is_web_export


func connection_secured() -> bool:
	if state == State.CONNECTING_DESTINATION:
		if _should_web_tunnel():
			_set_state(State.TUNNELING)
			request_processor.create_tunnel_to_request(pending_tunnel_address)
			return true
		_join_destination()
		return true
	if state == State.TUNNELING:
		_join_destination()
		return true
	if state == State.ROLLING_BACK:
		if _should_web_tunnel():
			_set_state(State.TUNNELING_ROLLBACK)
			request_processor.create_tunnel_to_request(pending_tunnel_address)
			return true
		return _restore_source_after_secure()
	if state == State.TUNNELING_ROLLBACK:
		return _restore_source_after_secure()
	return false


func tunnel_ready() -> void:
	if state != State.TUNNELING and state != State.TUNNELING_ROLLBACK:
		return
	request_processor.clear_for_server_switch()
	_refresh_state_deadline()
	connection_controller.reset_session_keep_socket()


func tunnel_local() -> void:
	if state == State.TUNNELING:
		_join_destination()
		return
	if state == State.TUNNELING_ROLLBACK:
		_restore_source_after_secure()


func tunnel_failed() -> void:
	transport_failed()


func transport_failed() -> bool:
	if state == State.CONNECTING_DESTINATION or state == State.JOINING_DESTINATION or state == State.TUNNELING:
		rollback(ENUMS.LOBBY_SWITCH_ERROR.DESTINATION_UNREACHABLE)
		return true
	if state == State.ROLLING_BACK or state == State.TUNNELING_ROLLBACK or state == State.RESTORING_SOURCE:
		fail_permanently(ENUMS.LOBBY_SWITCH_ERROR.ROLLBACK_FAILED)
		return true
	return false


func lobby_joined() -> void:
	if state == State.RESTORING_SOURCE:
		finish_rollback()
		return
	if state != State.JOINING_DESTINATION:
		return
	if !fallback_reservation_id.is_empty():
		request_processor.create_commit_server_switch_request(
			source_address,
			fallback_reservation_id)
	reset()


func lobby_join_failed() -> bool:
	if state == State.RESTORING_SOURCE:
		fail_permanently(ENUMS.LOBBY_SWITCH_ERROR.ROLLBACK_FAILED)
		return true
	if state != State.JOINING_DESTINATION:
		return false
	rollback(ENUMS.LOBBY_SWITCH_ERROR.JOIN_FAILED)
	return true


func rollback(error: int) -> void:
	if state == State.IDLE or _is_rollback_state():
		return
	rollback_error = error
	_reservation_deadline = 0
	_set_state(State.ROLLING_BACK)
	pending_tunnel_address = source_address
	request_processor.clear_for_server_switch()
	connection_controller.switch_server(source_address, use_websocket)


func finish_rollback() -> void:
	var error := rollback_error
	reset()
	GDSync.lobby_switch_failed.emit(error)
	matchmaking_controller.lobby_join_failed()


func fail_permanently(error: int) -> void:
	var was_switching : bool = state != State.IDLE
	reset()
	
	if was_switching:
		connection_controller.reset_multiplayer(true)
	
	GDSync.lobby_switch_failed.emit(error)
	matchmaking_controller.lobby_join_failed()


func _join_destination() -> void:
	_set_state(State.JOINING_DESTINATION)
	session_controller.broadcast_player_data()
	if connect_time > 0.0:
		request_processor.set_connect_time(connect_time)
	request_processor.create_join_lobby_with_ticket_request(reservation_id, proof)


func _restore_source_after_secure() -> bool:
	if !fallback_reservation_id.is_empty():
		_set_state(State.RESTORING_SOURCE)
		request_processor.create_join_lobby_with_ticket_request(fallback_reservation_id, proof)
		return true
	finish_rollback()
	return false


func reset() -> void:
	_set_state(State.IDLE)
	source_address = ""
	destination_address = ""
	reservation_id = ""
	proof = ""
	lobby_name = ""
	connect_time = 0.0
	fallback_reservation_id = ""
	rollback_error = ENUMS.LOBBY_SWITCH_ERROR.DESTINATION_UNREACHABLE
	use_websocket = false
	pending_tunnel_address = ""
