extends Node

var https_controller
var connection_controller
var GDSync

var login_email : String
var login_token : String
var previous_token : String

func _ready() -> void:
	name = "SessionController"
	GDSync = get_node("/root/GDSync")
	https_controller = GDSync._https_controller
	connection_controller = GDSync._connection_controller
	
	if !DirAccess.dir_exists_absolute("user://GD-Sync"):
		DirAccess.make_dir_absolute("user://GD-Sync")
	
	load_config()

func load_config() -> void:
	var dir = DirAccess.open("user://")
	if !dir.file_exists("user://GD-Sync/DataController.conf"): return
	
	var file = FileAccess.open_encrypted_with_pass("user://GD-Sync/DataController.conf", FileAccess.READ, connection_controller._PRIVATE_KEY)
	var data : Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	
	if data.has("LoginEmail"): login_email = data["LoginEmail"]
	if data.has("LoginToken"): previous_token = data["LoginToken"]

func save_config() -> void:
	var file = FileAccess.open_encrypted_with_pass("user://GD-Sync/DataController.conf", FileAccess.WRITE, connection_controller._PRIVATE_KEY)
	file.store_buffer(var_to_bytes({
		"LoginEmail" : login_email,
		"LoginToken" : login_token
	}))
	file.close()

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
	
	if result["Code"] == ENUMS.LOGIN_RESPONSE_CODE.SUCCESS:
		login_token = result["Result"]
		save_config()
		GDSync.set_player_username(result["Username"])
	elif result["Code"] == ENUMS.LOGIN_RESPONSE_CODE.BANNED:
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
	
	if result["Code"] == ENUMS.LOGIN_RESPONSE_CODE.SUCCESS:
		login_token = result["Result"]
		GDSync.set_player_username(result["Username"])
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
		"Result" : result["Result"] if result.size() > 1 else {"Rank" : -1, "Score" : 0}
	}
	return data

func submit_score(leaderboard : String, score : int) -> int:
	var result : Dictionary = await https_controller.perform_https_request(
		"submitscore",
		{
			"Token" : login_token,
			"Leaderboard" : leaderboard,
			"Score" : score
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
