extends Control

signal logged_in(email)
signal login_failed(email, response_code)

@onready var email_input : LineEdit = %Email
@onready var password_input : LineEdit = %Password
@onready var error_text : Label = %ErrorText

var busy : bool = false

func login() -> void:
	if busy: return
	busy = true
	
	var email : String = email_input.text
	var password : String = password_input.text
	
	var response : Dictionary = await GDSync.login(email, password)
	var response_code : int = response["Code"]
	
	if response_code == ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.SUCCESS:
		error_text.text = ""
		logged_in.emit(email)
	else:
		set_error_text(response_code, response)
		login_failed.emit(email, response_code)
	
	busy = false

func set_error_text(response_code : int, response : Dictionary) -> void:
	match(response_code):
		ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.NO_RESPONSE_FROM_SERVER:
			error_text.text = "No response from server."
		ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.DATA_CAP_REACHED:
			error_text.text = "Data transfer cap has been reached."
		ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.RATE_LIMIT_EXCEEDED:
			error_text.text = "Rate limit exceeded, please wait and try again."
		ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.NO_DATABASE:
			error_text.text = "API key has no linked database."
		ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.EMAIL_OR_PASSWORD_INCORRECT:
			error_text.text = "Email or password incorrect."
		ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.NOT_VERIFIED:
			error_text.text = "The email address has not yet been verified."
		ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE.BANNED:
			var ban_time : int = response["BanTime"]
			
			if ban_time == -1:
				error_text.text = "Account is permanently banned."
			else:
				var ban_time_string : String = Time.get_datetime_string_from_unix_time(ban_time, true)
				error_text.text = "Account is banned until "+ban_time_string+"."
