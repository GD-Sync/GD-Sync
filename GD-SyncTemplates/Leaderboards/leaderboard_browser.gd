extends Control

var LABEL_SCENE : PackedScene = preload("res://GD-SyncTemplates/Leaderboards/leaderboard_label.tscn")

@export var leaderboard_name : String = ""
@export var page_size : int = 10

@onready var leaderboard_container : Control = %LeaderboardContainer
@onready var previous_button : Button = %Previous
@onready var next_button : Button = %Next
@onready var page_label : Label = %PageLabel

var current_page : int = 1
var final_page : int = 0

func _ready() -> void:
	update_buttons()
	show_current_page()

func _on_previous_pressed() -> void:
	current_page = max(current_page - 1, 1)
	update_buttons()
	show_current_page()

func _on_next_pressed() -> void:
	current_page = min(current_page + 1, final_page)
	update_buttons()
	show_current_page()

func update_buttons() -> void:
	next_button.disabled = current_page >= final_page
	previous_button.disabled = current_page <= 1

func show_current_page() -> void:
	#Store current page
	var request_page : int = current_page
	
	clear_page()
	page_label.text = str(current_page)+"/"+str(final_page)
	
	var response : Dictionary = await GDSync.browse_leaderboard(leaderboard_name, page_size, current_page)
	var response_code : int = response["Code"]
	
	#If the page changed while doing the request, discard everything
	if request_page != current_page:
		return
	
	if response_code != ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE.SUCCESS:
		show_browse_error(response_code)
	else:
		final_page = response["FinalPage"]
		
		update_buttons()
		page_label.text = str(current_page)+"/"+str(final_page)
		
		populate_page(response["Result"])

func clear_page() -> void:
	for label in leaderboard_container.get_children():
		label.queue_free()

func populate_page(scores : Array) -> void:
	for score_data in scores:
		var label : Node = LABEL_SCENE.instantiate()
		label.set_score_data(score_data)
		leaderboard_container.add_child(label)

func show_browse_error(response_code : int) -> void:
	var error : String = "Browse leaderboard error: "
	
	match(response_code):
		ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE.NO_RESPONSE_FROM_SERVER:
			error += "No response from server."
		ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE.DATA_CAP_REACHED:
			error += "Data transfer cap has been reached."
		ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE.RATE_LIMIT_EXCEEDED:
			error += "Rate limit exceeded, please wait and try again."
		ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE.NO_DATABASE:
			error += "API key has no linked database."
		ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE.NOT_LOGGED_IN:
			error += "Client isn't logged-in."
		ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE.LEADERBOARD_DOESNT_EXIST:
			error += "The leaderboard \""+leaderboard_name+"\" does not exist"
	
	push_error(error)
