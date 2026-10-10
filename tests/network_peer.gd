extends SceneTree

var session: Node
var role: String = "host"
var failures: int = 0
var began: int = 0
var stage: int = 0
var stage_time: int = 0
var remote_id: int = 0
var seen: Dictionary = {}
var first_client_x: float = 0.0
var first_host_x: float = 0.0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("%s: %s" % [role, description])

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "client":
			role = "client"
	call_deferred("run")

func run() -> void:
	session = root.get_node("Session")
	session.changed.connect(func(): print("%s phase=%s roster=%s message=%s" % [role, session.phase, session.roster, session.message]))
	began = Time.get_ticks_msec()
	if role == "host":
		check(session.host_game("Host", 27849) == OK, "Create ENet room")
		check(not session.start_game(), "Network lobby refuses one participant")
	else:
		check(session.join_game("127.0.0.1", 27849, "Client") == OK, "Connect ENet client")
	while Time.get_ticks_msec() - began < 25000:
		await physics_frame
		await process_frame
		if role == "host":
			if host_tick():
				finish()
				return
		else:
			if client_tick():
				finish()
				return
	check(false, "Timed out at stage %d, phase %s, observations %s" % [stage, session.phase, seen])
	finish()

func advance(next: int) -> void:
	stage = next
	stage_time = Time.get_ticks_msec()

func age() -> int:
	return Time.get_ticks_msec() - stage_time

func host_tick() -> bool:
	if stage == 0:
		if session.roster.size() == 2:
			for id in session.roster:
				if id != 1:
					remote_id = id
			if not seen.has("unready"):
				seen.unready = true
				check(not session.can_start(), "Host cannot start before participant is ready")
			if session.ready_states.get(remote_id, false):
				check(session.start_game(), "Host starts with two independent ready peers")
				place_for_test()
				advance(1)
		return false
	if stage == 7:
		if session.phase == "lobby" and session.can_start():
			check(session.confirmed.is_empty(), "Shared return to lobby clears confirmations")
			check(session.start_game(), "Network rematch starts after participant is ready again")
			place_for_test()
			advance(8)
		return false
	var arena: FightArena = session.arena
	var host: Fighter = arena.fighters[0]
	var client: Fighter = arena.fighters[1]
	if stage == 1 and age() > 1200:
		check(client.position.x > 900, "Client input moves its own fighter")
		check(is_equal_approx(host.position.x, 320), "Client input cannot move host fighter")
		host.position = Vector2(400, 514)
		host.velocity = Vector2.ZERO
		client.position = Vector2(455, 514)
		client.velocity = Vector2.ZERO
		host.facing = 1
		session.submit_local_input(16)
		advance(2)
	elif stage == 2:
		if age() > 100:
			session.submit_local_input(0)
		if age() > 600:
			check(client.percent == 12.0 and host.percent == 0.0, "Server-authoritative attack and victim-only increment")
			client.position = Vector2(2000, 0)
			advance(3)
	elif stage == 3 and age() > 250:
		check(client.stocks == 2 and client.percent == 0.0, "Network ring-out subtracts exactly one and resets percent")
		check(client.life_state == Fighter.LifeState.WAITING, "Network respawn waits")
		advance(4)
	elif stage == 4 and client.life_state == Fighter.LifeState.ACTIVE:
		check(client.invulnerability_left > 2.8, "Network respawn has protection")
		check(not client.receive_hit(AttackData.new(), Vector2.RIGHT), "Server blocks protected attack")
		advance(5)
	elif stage == 5 and age() > 500:
		client.stocks = 1
		client.position = Vector2(2000, 0)
		advance(6)
	elif stage == 6 and age() > 700:
		check(session.phase == "result" and arena.result == "P1 WINS", "Host receives final winner")
		check(host.kills == 1 and host.dealt_percent == 12.0, "Host credited with kills and dealt percent")
		session.confirm_result()
		advance(7)
	elif stage == 8:
		if session.roster.size() == 1:
			check(session.phase == "result" and session.arena.result == "P1 WINS", "Disconnect forfeits remote participant")
			return true
	return false

## Skips the start countdown and uses fixed starts so movement checks are deterministic.
func place_for_test() -> void:
	var arena: FightArena = session.arena
	arena.countdown_left = 0.0
	arena.fighters[0].position = Vector2(320, 334)
	arena.fighters[1].position = Vector2(830, 334)

func client_tick() -> bool:
	if session.phase == "playing" and is_instance_valid(session.arena):
		var arena: FightArena = session.arena
		var host: Fighter = arena.fighters[0]
		var client: Fighter = arena.fighters[1]
		if not seen.has("initial"):
			seen.initial = true
			first_client_x = client.position.x
			first_host_x = host.position.x
			check(client.player_id == session.multiplayer.get_unique_id() and host.player_id == 1, "Clients agree on player ownership")
			check(client.stocks == 3 and client.percent == 0.0, "Initial client stocks/percent")
			check(not arena.authoritative, "Client cannot simulate combat authority")
			advance(1)
		session.submit_local_input(2 if age() < 650 and session.generation == 1 else 0)
		if client.position.x > first_client_x + 70.0 and session.generation == 1:
			seen.moved = true
		if client.percent == 12.0:
			seen.hit = true
		if client.stocks == 2 and client.life_state == Fighter.LifeState.WAITING:
			seen.waiting = true
			check(client.percent == 0.0, "Client observes reset percent during wait")
		if client.stocks == 2 and client.invulnerability_left > 0.0:
			seen.protected = true
		if session.generation == 2:
			check(client.stocks == 3 and client.percent == 0.0 and host.stocks == 3, "Client sees reset rematch")
			for expected in ["initial", "moved", "hit", "waiting", "protected", "winner", "lobby"]:
				check(seen.has(expected), "Observed synchronized %s" % expected)
			session.leave()
			return true
	elif session.phase == "result":
		if not seen.has("winner"):
			seen.winner = true
			check(session.arena.result == "P1 WINS" and session.arena.fighters[1].stocks == 0, "Client receives same final winner and elimination")
			check(session.arena.winner_id == 1 and session.arena.fighters[0].kills == 1, "Client receives result statistics")
			session.confirm_result()
	elif session.phase == "lobby":
		if seen.has("winner"):
			seen.lobby = true
		if not session.ready_states.get(session.multiplayer.get_unique_id(), false):
			session.set_ready(true)
	return false

func finish() -> void:
	print("Network %s checks complete: %d failures" % [role, failures])
	session.leave()
	quit(1 if failures > 0 else 0)
