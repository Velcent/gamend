# A second script in the same plugin. `class_name` makes it reachable from
# example_gdscript.gd as `Rewards.…` -- Godot's own mechanism, with the call
# checked across files at compile time.
class_name Rewards

const BASE_GOLD = 100
const REFERRAL_BONUS = 50

func starter_gold(referred):
	return BASE_GOLD + REFERRAL_BONUS if referred else BASE_GOLD

func describe(kind, amount):
	return "%s x%d" % [kind, amount]
