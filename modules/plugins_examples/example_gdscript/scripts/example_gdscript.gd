# Example Gamend hooks, written in GDScript.

# Constants and enums fold into the code that uses them, so they cost nothing.
enum Rank { NEWCOMER, REGULAR = 10, VETERAN }

# A signal any hook in this plugin can emit, and any other can await.
signal player_joined(user_id, tier)

#
# `mix gamend.gdscript.compile` turns this into gen/gamend/modules/example_gdscript.ex,
# which `mix plugin.bundle` compiles into an ordinary OTP plugin. Nothing is
# interpreted at run time.

func after_user_register(user):
	# `Rewards` is the other script in this plugin, reached by its class_name.
	var bonus = Rewards.starter_gold(user.metadata)
	var tier = "referred" if user.metadata else "standard"

	player_joined.emit(user.id, tier)

	# `opts({...})` is how a keyword list is spelled. It has to be explicit:
	# a trailing Dictionary is a payload map elsewhere (see the notification
	# below), so inferring options from position would corrupt that call.
	Economy.grant(user.id, "gold", bonus, opts({
		"reason": "gdscript_starter_kit",
		"idempotency_key": "gd_starter:" + user.id,
	}))

	Notifications.admin_create_notification(user.id, user.id, {
		"title": "Welcome!",
		"content": greeting(user.username, bonus),
		"metadata": {"type": "example_gdscript_welcome", "tier": tier},
	})

func after_user_logged_in(user):
	KV.put("example_gdscript_last_login", {"username": user.username})

# A plain func is callable as an RPC, and from the hooks above.
func greeting(name, gold):
	if name == "":
		return "Welcome! You start with " + str(gold) + " gold."
	return "Welcome, " + name + "! You start with " + str(gold) + " gold."

# Declaring a notification code is just a func returning a Dictionary -- the
# server rejects any code no plugin declared.
func notification_types():
	return {"example_gdscript_welcome": "Sent to a new account by the GDScript example"}

# A loop with an early exit. `break` and `continue` work at any depth -- they
# throw the loop's accumulator out, so the generated fold picks it up.
func grant_bundle(user_id, items):
	var granted = 0

	for item in items:
		if item == "":
			continue
		if granted >= 3:
			break
		Inventory.grant_item(user_id, item, 1, opts({"reason": "gdscript_bundle"}))
		granted += 1

	return granted

# `match`, plus two independent lookups running concurrently. `spawn` starts a
# lambda on its own BEAM process; `await` collects it.
func account_summary(user_id, kind):
	var gold = spawn(func(): return Economy.balance(user_id, "gold"))
	var gems = spawn(func(): return Economy.balance(user_id, "gems"))

	var tier = "standard"
	match kind:
		"vip", "founder":
			tier = "premium"
		"banned":
			tier = "restricted"
		var other:
			tier = "standard:" + str(other)

	return {"tier": tier, "gold": await gold, "gems": await gems}

# Arrays and Dictionaries are reference types, as in Godot: `tally` is built in
# place, and `bump` mutates the caller's Dictionary rather than a copy.
func bump(counts, key):
	if counts.has(key):
		counts[key] += 1
	else:
		counts[key] = 1

func tally_items(items):
	var counts = {}

	for item in items:
		if item.strip_edges().is_empty():
			continue
		bump(counts, item)

	return counts

# `match` destructuring, a ternary and a rank constant in one place.
func describe_reward(reward):
	match reward:
		{"kind": "gold", "amount": var amount}:
			return "%d gold" % [amount]
		{"kind": "item", ..}:
			return "an item"
		[var first, ..]:
			return "a bundle starting with " + str(first)
		_:
			return "nothing" if reward == null else str(reward)

func rank_for(logins):
	return Rank.VETERAN if logins > 100 else Rank.NEWCOMER

# Waits for the signal above. Subscribing happens at function entry, so a
# player registering right after this call is still seen.
func await_next_join():
	return await player_joined

# An inner class. Instances are Dictionaries underneath, so one crosses back to
# gamend as plain data -- and `extends` inherits fields, `_init` and methods.
class Reward:
	var kind = "gold"
	var amount = 0

	func _init(k, a):
		kind = k
		amount = a

	func describe():
		return "%s x%d" % [kind, amount]

	func bump(by):
		amount += by

class BonusReward extends Reward:
	func describe():
		return "bonus " + kind

func reward_summary(kind, amount, bonus):
	var r = BonusReward.new(kind, amount) if bonus else Reward.new(kind, amount)
	r.bump(1)
	return [r.describe(), r.amount]
