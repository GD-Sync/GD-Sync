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

var https_controller
var connection_controller
var session_controller
var GDSync

var login_email : String
var login_token : String
var previous_token : String
var logged_in : bool = false
var safe_quit : bool = false

var status_ping_timer : float = 0.0

func _ready() -> void:
	name = "DataController"
	GDSync = get_node("/root/GDSync")
	https_controller = GDSync._https_controller
	connection_controller = GDSync._connection_controller
	session_controller = GDSync._session_controller
	
	if !DirAccess.dir_exists_absolute("user://GD-Sync"):
		DirAccess.make_dir_absolute("user://GD-Sync")
	
	load_config()

func _process(delta: float) -> void:
	if logged_in:
		status_ping_timer -= delta
		
		if status_ping_timer <= 0.0:
			status_ping_timer = 300
			set_friend_status()

func _notification(what : int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()

func quit() -> void:
	if logged_in:
		GDSync.lobby_leave()
		await set_friend_status()
	
	safe_quit = true
	save_config()
	get_tree().quit()

func log_in() -> void:
	logged_in = true
	safe_quit = false
	get_tree().set_auto_accept_quit(false)

func load_config() -> void:
	var dir = DirAccess.open("user://")
	if !dir.file_exists("user://GD-Sync/DataController.conf"): return
	
	var file = FileAccess.open_encrypted_with_pass("user://GD-Sync/DataController.conf", FileAccess.READ, connection_controller._PRIVATE_KEY)
	if file == null: return
	var data : Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	
	if data.has("LoginEmail"): login_email = data["LoginEmail"]
	if data.has("LoginToken"): previous_token = data["LoginToken"]
	
	safe_quit = true
	if data.has("SafeQuit"):
		if !data["SafeQuit"]:
			push_error("GD-Sync did not close correctly. Please use GD-Sync.quit() instead of get_tree().quit().")
	
	save_config()

func save_config() -> void:
	var file = FileAccess.open_encrypted_with_pass("user://GD-Sync/DataController.conf", FileAccess.WRITE, connection_controller._PRIVATE_KEY)
	file.store_buffer(var_to_bytes({
		"LoginEmail" : login_email,
		"LoginToken" : login_token,
		"SafeQuit" : safe_quit
	}))
	file.close()

func set_friend_status() -> int:
	if !logged_in: return 0
	
	var result : Dictionary = await https_controller.perform_https_request(
		"setfriendstatus",
		{
			"Token" : login_token,
			"Data" : 
				{
					"LobbyName" : session_controller.lobby_name,
					"HasPassword" : session_controller.lobby_password != ""
				}
		}
	)
	
	return result["Code"]

func create_account(email : String, username : String, password : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"createaccount",
		{
			"Email" : email,
			"Username" : username,
			"Password" : password
		}
	)
	
	return result["Code"]

func delete_account(email : String, password : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"deleteaccount",
		{
			"Email" : email,
			"Password" : password
		}
	)
	
	return result["Code"]

func verify_account(email : String, code : String, valid_time : float) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"verifyaccount",
		{
			"Email" : email,
			"Code" : code,
			"ValidTime" : valid_time
		}
	)
	
	login_email = email
	
	if result["Code"] == ENUMS.ACCOUNT_VERIFICATION_RESPONSE_CODE.SUCCESS:
		login_token = result["Result"]
		save_config()
	
	return result["Code"]

func login(email : String, password : String, valid_time : float) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"login",
		{
			"Email" : email,
			"Password" : password,
			"ValidTime" : valid_time
		}
	)
	
	login_email = email
	
	var data : Dictionary = {
		"Code" : result["Code"]
	}
	
	if result["Code"] == ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.SUCCESS:
		login_token = result["Result"]
		log_in()
		save_config()
		GDSync.player_set_username(result["Username"])
	elif result["Code"] == ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.BANNED:
		var ban_time : float = result["BanTime"]
		if ban_time-Time.get_unix_time_from_system() >= 86400000:
			ban_time = -1
		data["BanTime"] = ban_time
	
	return data

func login_from_session(valid_time : int) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"loginfromsession",
		{
			"Email" : login_email,
			"Token" : previous_token,
			"ValidTime" : valid_time
		}
	)
	
	if result["Code"] == ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.SUCCESS:
		login_token = result["Result"]
		log_in()
		GDSync.player_set_username(result["Username"])
	else:
		login_token = ""
	save_config()
	
	return result["Code"]

func resend_verification_code(email : String, password : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"resendverificationcode",
		{
			"Email" : email,
			"Password" : password
		}
	)
	
	return result["Code"]

func is_verified(username : String) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"isverified",
		{
			"Token" : login_token,
			"Username" : username
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else false
	}
	return data

func logout() -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"logout",
		{
			"Email" : login_email,
			"Token" : login_token
		}
	)
	
	login_token = ""
	login_email = ""
	logged_in = false
	save_config()
	
	return result["Code"]

func change_username(new_username : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"changeusername",
		{
			"Token" : login_token,
			"Username" : new_username
		}
	)
	
	return result["Code"]

func change_password(email : String, password : String, new_password : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"changepassword",
		{
			"Email" : email,
			"Password" : password,
			"NewPassword" : new_password
		}
	)
	
	return result["Code"]

func request_password_reset(email : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"requestpasswordreset",
		{
			"Email" : email
		}
	)
	
	return result["Code"]

func reset_password(email : String, reset_code : String, new_password : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"resetpassword",
		{
			"Email" : email,
			"ResetCode" : reset_code,
			"NewPassword" : new_password
		}
	)
	
	return result["Code"]

func set_player_document(path : String, data : Dictionary, externally_visible : bool) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"setplayerdocument",
		{
			"Token" : login_token,
			"Path" : path,
			"Data" : data,
			"ExternallyVisible" : externally_visible
		}
	)
	
	return result["Code"]

func set_external_visible(path : String, externally_visible : bool) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"setexternalvisible",
		{
			"Token" : login_token,
			"Path" : path,
			"ExternallyVisible" : externally_visible
		}
	)
	
	return result["Code"]

func get_player_document(path : String, external_username : String) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"getplayerdocument",
		{
			"Token" : login_token,
			"Path" : path,
			"ExternalUsername" : external_username
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else {}
	}
	return data

func browse_player_collection(path : String, external_username : String) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"browseplayercollection",
		{
			"Token" : login_token,
			"Path" : path,
			"ExternalUsername" : external_username
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 and result["Result"] != null else []
	}
	return data

func has_player_document(path : String, external_username : String) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"hasplayerdocument",
		{
			"Token" : login_token,
			"Path" : path,
			"ExternalUsername" : external_username
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else false
	}
	return data

func delete_player_document(path : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"deleteplayerdocument",
		{
			"Token" : login_token,
			"Path" : path
		}
	)
	
	return result["Code"]

func report_user(user : String, report : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"createreport",
		{
			"Token" : login_token,
			"Against" : user,
			"Report" : report
		}
	)
	
	return result["Code"]

func has_leaderboard(leaderboard : String) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"hasleaderboard",
		{
			"Token" : login_token,
			"Leaderboard" : leaderboard
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else false
	}
	return data

func get_leaderboards() -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"getleaderboardstoken",
		{
			"Token" : login_token
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else []
	}
	return data

func browse_leaderboard(leaderboard : String, page_size : int, page : int) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"browseleaderboardtoken",
		{
			"Token" : login_token,
			"Leaderboard" : leaderboard,
			"Page" : page,
			"PageSize" : page_size
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"FinalPage" : result["FinalPage"] if result.has("FinalPage") else 0,
		"Result" : result["Result"] if result.has("Result") else []
	}
	return data

func get_leaderboard_score(leaderboard : String, username : String) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"getleaderboardscore",
		{
			"Token" : login_token,
			"Leaderboard" : leaderboard,
			"Username" : username
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else {"Rank" : -1, "Score" : 0, "Data" : {}}
	}
	return data

func submit_score(leaderboard : String, score : int, data : Dictionary) -> int:
	if var_to_bytes(data).size() > 2048:
		return ENUMS.LEADERBOARD_SUBMIT_SCORE_RESPONSE_CODE.DATA_TOO_LAGE
	
	var result : Dictionary = await https_controller.perform_https_request(
		"submitscore",
		{
			"Token" : login_token,
			"Leaderboard" : leaderboard,
			"Score" : score,
			"Data" : data
		}
	)
	
	return result["Code"]

func delete_score(leaderboard : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"deletescore",
		{
			"Token" : login_token,
			"Leaderboard" : leaderboard
		}
	)
	
	return result["Code"]

func send_friend_request(friend : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"sendfriendrequest",
		{
			"Token" : login_token,
			"Friend" : friend
		}
	)
	
	return result["Code"]

func get_friend_status(friend : String) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"getfriendstatus",
		{
			"Token" : login_token,
			"Friend" : friend
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else {}
	}
	return data

func get_friends() -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"getfriends",
		{
			"Token" : login_token
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"],
		"Result" : result["Result"] if result.size() > 1 else 0
	}
	return data

func accept_friend_request(friend : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"acceptfriendrequest",
		{
			"Token" : login_token,
			"Friend" : friend
		}
	)
	
	return result["Code"]

func remove_friend(friend : String) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"removefriend",
		{
			"Token" : login_token,
			"Friend" : friend
		}
	)
	
	return result["Code"]

func link_steam_account(auth_ticket : PackedByteArray, app_id : int) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"linksteamaccount",
		{
			"Token" : login_token,
			"AuthTicket" : auth_ticket,
			"AppID" : app_id
		}
	)
	
	return result["Code"]

func unlink_steam_account() -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"unlinksteamaccount",
		{
			"Token" : login_token
		}
	)
	
	return result["Code"]

func steam_login(auth_ticket : PackedByteArray, app_id : int, valid_time : float) -> Dictionary:
	var result : Dictionary = await https_controller.perform_https_request(
		"steamlogin",
		{
			"AuthTicket" : auth_ticket,
			"AppID" : app_id,
			"ValidTime" : valid_time
		}
	)
	
	var data : Dictionary = {
		"Code" : result["Code"]
	}
	
	if result["Code"] == ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.SUCCESS:
		login_token = result["Result"]
		log_in()
		save_config()
		GDSync.player_set_username(result["Username"])
	elif result["Code"] == ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.BANNED:
		var ban_time : float = result["BanTime"]
		if ban_time-Time.get_unix_time_from_system() >= 86400000:
			ban_time = -1
		data["BanTime"] = ban_time
	
	return data

func ban_account(ban_time : float) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"banaccount",
		{
			"Token" : login_token,
			"BanTime" : ban_time
		}
	)
	
	return result["Code"]
