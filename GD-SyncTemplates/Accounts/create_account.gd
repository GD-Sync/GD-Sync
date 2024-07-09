extends Control

signal account_created(email, username, password)
signal account_creation_failed(email, username, password, response_code)

@onready var email_input : LineEdit = %Email
@onready var username_input : LineEdit = %Username
@onready var password_input : LineEdit = %Password
@onready var error_text : Label = %ErrorText

var busy : bool = false

func create_account() -> void:
	if busy: return
	busy = true
	
	var email : String = email_input.text
	var username : String = username_input.text
	var password : String = password_input.text
	
	var response_code : int = await GDSync.create_account(email, username, password)
	
	if response_code == ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.SUCCESS:
		error_text.text = ""
		account_created.emit(email, username, password)
	else:
		set_error_text(response_code)
		account_creation_failed.emit(email, username, password, response_code)
	
	busy = false

func set_error_text(response_code : int) -> void:
	match(response_code):
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.NO_RESPONSE_FROM_SERVER:
			error_text.text = "No response from server."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.DATA_CAP_REACHED:
			error_text.text = "Data transfer cap has been reached."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.RATE_LIMIT_EXCEEDED:
			error_text.text = "Rate limit exceeded, please wait and try again."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.NO_DATABASE:
			error_text.text = "API key has no linked database."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.STORAGE_FULL:
			error_text.text = "Database is full."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.INVALID_EMAIL:
			error_text.text = "Invalid email address."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.INVALID_USERNAME:
			error_text.text = "Username contains illegal characters."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.EMAIL_ALREADY_EXISTS:
			error_text.text = "An account with this email address already exists."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.USERNAME_ALREADY_EXISTS:
			error_text.text = "An account with this username address already exists."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.USERNAME_TOO_SHORT:
			error_text.text = "Username is too short."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.USERNAME_TOO_LONG:
			error_text.text = "Username is too long."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.PASSWORD_TOO_SHORT:
			error_text.text = "Password is too short."
		ENUMS.ACCOUNT_CREATION_RESPONSE_CODE.PASSWORD_TOO_LONG:
			error_text.text = "Password is too long."
