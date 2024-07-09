extends HBoxContainer

func set_score_data(data : Dictionary):
	%Rank.text = str(data["Rank"])
	%Username.text = data["Username"]
	%Score.text = str(data["Score"])
