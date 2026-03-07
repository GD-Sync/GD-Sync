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

var GDSync
var data_controller
var session_controller

var steam_integration_enabled : bool = false
var steam

var steam_lobby_id : int = 0

func _ready() -> void:
	name = "Steam"
	GDSync = get_node("/root/GDSync")
	data_controller = GDSync._data_controller
	session_controller = GDSync._session_controller
	
	steam_integration_enabled = Engine.has_singleton("Steam")
	if steam_integration_enabled: init_steam()

func init_steam() -> void:
	steam = Engine.get_singleton("Steam")
	
	steam.join_requested.connect(_on_lobby_join_requested)
	
	GDSync.lobby_joined.connect(lobby_joined)

func steam_initialized() -> bool:
	return steam_integration_enabled and steam.loggedOn()

func _process(delta: float) -> void:
	if steam_integration_enabled:
		steam.run_callbacks()

func link_steam_account() -> int:
	if !steam_initialized():
		return ENUMS.LINK_STEAM_ACCOUNT_RESPONSE_CODE.STEAM_ERROR
	
	var ticket_code : int = steam.getAuthTicketForWebApi("gdsync")
	
	if ticket_code == 0:
		return ENUMS.LINK_STEAM_ACCOUNT_RESPONSE_CODE.STEAM_ERROR
	
	var ticket : Array = await steam.get_ticket_for_web_api
	
	if ticket.size() == 0:
		return ENUMS.LINK_STEAM_ACCOUNT_RESPONSE_CODE.STEAM_ERROR
	
	var rawTicket : PackedByteArray = ticket[3]
	var result : int = await data_controller.link_steam_account(rawTicket, steam.getAppID())
	
	steam.cancelAuthTicket(ticket_code)
	
	return result

func unlink_steam_account() -> int:
	if !steam_initialized():
		return ENUMS.UNLINK_STEAM_ACCOUNT_RESPONSE_CODE.STEAM_ERROR
	
	return await data_controller.unlink_steam_account()

func steam_login(valid_time : float) -> Dictionary:
	if !steam_initialized():
		return {"Code" : ENUMS.STEAM_LOGIN_RESPONSE_CODE.STEAM_ERROR}
	
	var ticket_code : int = steam.getAuthTicketForWebApi("gdsync")
	
	if ticket_code == 0:
		return {"Code" : ENUMS.STEAM_LOGIN_RESPONSE_CODE.STEAM_ERROR}
	
	var ticket : Array = await steam.get_ticket_for_web_api
	
	if ticket.size() == 0:
		return {"Code" : ENUMS.STEAM_LOGIN_RESPONSE_CODE.STEAM_ERROR}
	
	var rawTicket : PackedByteArray = ticket[3]
	var result : Dictionary = await data_controller.steam_login(rawTicket, steam.getAppID(), valid_time)
	
	steam.cancelAuthTicket(ticket_code)
	
	return result

func create_steam_lobby() -> void:
	if !steam_initialized(): return
	steam.createLobby(steam.LOBBY_TYPE_FRIENDS_ONLY, 250)
	
	var result : Array = await steam.lobby_created
	
	if result[0] == 1:
		steam_lobby_id = result[1]
		
		steam.setLobbyJoinable(steam_lobby_id, true)
		steam.setLobbyData(steam_lobby_id, "gdsyncid", session_controller.lobby_name)
		steam.setLobbyData(steam_lobby_id, "haspassword", str(session_controller.lobby_password != ""))

func leave_steam_lobby() -> void:
	if !steam_initialized(): return
	steam.leaveLobby(steam_lobby_id)
	steam_lobby_id = 0

func _on_lobby_join_requested(lobby_id: int, friend_id: int) -> void:
	var owner_name : String = steam.getFriendPersonaName(friend_id)
	
	steam.requestLobbyData(lobby_id)
	await steam.lobby_data_update
	
	var lobby_name : String = steam.getLobbyData(lobby_id, "gdsyncid")
	var has_password : bool = steam.getLobbyData(lobby_id, "haspassword") == "true"
	
	GDSync.steam_join_request.emit(lobby_name, has_password)

func lobby_joined(lobby_name : String) -> void:
	if session_controller.own_lobby:
		create_steam_lobby()
