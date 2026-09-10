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
var connection_controller

var active: bool = false
var status: int = ENUMS.MATCHMAKING_STATUS.INACTIVE
var details: Dictionary = {}
var request_id: int = 0
var cancellation_pending: bool = false


func _ready() -> void:
	name = "MatchmakingController"
	request_processor = GDSync._request_processor
	connection_controller = GDSync._connection_controller
	GDSync.disconnected.connect(disconnected)


func start(request: MatchmakingRequest) -> void:
	if !connection_controller.valid_connection():
		return
	if connection_controller.is_local_check():
		GDSync.matchmaking_failed.emit(ENUMS.MATCHMAKING_ERROR.UNSUPPORTED_LOCAL)
		return
	if GDSync.lobby_get_name() != "":
		GDSync.matchmaking_failed.emit(ENUMS.MATCHMAKING_ERROR.ALREADY_IN_LOBBY)
		return
	if request == null or !request._is_valid():
		GDSync.matchmaking_failed.emit(ENUMS.MATCHMAKING_ERROR.INVALID_REQUEST)
		return
	if active:
		request_processor.create_cancel_matchmaking_request(request_id)
	request_id += 1
	cancellation_pending = false
	active = true
	status = ENUMS.MATCHMAKING_STATUS.INACTIVE
	var parameters := request._to_dictionary()
	parameters["RequestId"] = request_id
	request_processor.create_start_matchmaking_request(parameters)


func cancel() -> void:
	if !connection_controller.valid_connection() or !active:
		return
	request_processor.create_cancel_matchmaking_request(request_id)
	cancellation_pending = true
	active = false
	status = ENUMS.MATCHMAKING_STATUS.INACTIVE
	details.clear()


func is_active() -> bool:
	return active


func get_status() -> int:
	return status


func get_status_details() -> Dictionary:
	return details.duplicate(true)


func started(received_request_id: int) -> void:
	if received_request_id != request_id or cancellation_pending:
		return
	active = true
	GDSync.matchmaking_started.emit()


func status_changed(received_request_id: int, new_status: int, new_details: Dictionary) -> void:
	if received_request_id != request_id or cancellation_pending:
		return
	status = new_status
	details = new_details.duplicate(true)
	GDSync.matchmaking_status_changed.emit(status, details)


func match_found(received_request_id: int, lobby_name: String) -> void:
	if received_request_id != request_id or cancellation_pending or !active:
		return
	status = ENUMS.MATCHMAKING_STATUS.JOINING
	GDSync.matchmaking_match_found.emit(lobby_name)
	if received_request_id == request_id and active:
		GDSync.lobby_join(lobby_name)


func remote_match_found(received_request_id: int, lobby_name: String) -> void:
	if received_request_id != request_id or cancellation_pending or !active:
		return
	status = ENUMS.MATCHMAKING_STATUS.JOINING
	GDSync.matchmaking_match_found.emit(lobby_name)


func failed(received_request_id: int, error: int) -> void:
	if received_request_id != request_id:
		return
	cancellation_pending = false
	reset()
	GDSync.matchmaking_failed.emit(error)


func cancelled(received_request_id: int) -> void:
	if received_request_id != request_id:
		return
	cancellation_pending = false
	reset()
	GDSync.matchmaking_cancelled.emit()


func lobby_joined() -> void:
	cancellation_pending = false
	reset()


func lobby_join_failed() -> void:
	if status == ENUMS.MATCHMAKING_STATUS.JOINING:
		failed(request_id, ENUMS.MATCHMAKING_ERROR.JOIN_FAILED)


func disconnected() -> void:
	cancellation_pending = false
	reset()


func reset() -> void:
	active = false
	status = ENUMS.MATCHMAKING_STATUS.INACTIVE
	details.clear()
