class_name AerialArbiter
extends Node

## Resolves aerial contests (Phase 2 advanced mechanics). The match adds one (group "aerial_arbiter"); a
## `HeaderSystem` asks it right before its contact. Every other player with a pending header whose head is within
## CONTEST_RADIUS of the ball goes up for it too: the higher score (heading, jumping, strength, height, timing,
## position — see `HeaderSystem._score`) plus a random share NOISE wins. The losers do not touch the ball (their
## request is cancelled) and lose their balance briefly. Deterministic per match (seeded RNG).

const CONTEST_RADIUS := 1.3
const NOISE := 0.3
## A won contest stays decided for this long, so the winner's own contact a tick later is not contested again.
const DECIDED_FOR := 0.35

var rng := RandomNumberGenerator.new()
var contests := 0
var claims := 0
## Last contest: {winner, loser_count} (tests, tuning).
var last := {}
var _decided_winner: Node = null
var _decided_left := 0.0


func _ready() -> void:
	add_to_group(&"aerial_arbiter")


func _physics_process(delta: float) -> void:
	_decided_left = maxf(_decided_left - delta, 0.0)


## True when `claimant` (a FootballActions) may head the ball now.
func claim(claimant: Node, ball: Node3D, score: float) -> bool:
	claims += 1
	if _decided_left > 0.0 and _decided_winner != null and is_instance_valid(_decided_winner):
		return _decided_winner == claimant
	var rivals: Array = []
	for n in get_tree().get_nodes_in_group(&"ball_actions"):
		if n == claimant or not (n is FootballActions):
			continue
		var fa := n as FootballActions
		if fa.header == null or not fa.header.has_request():
			continue
		var host := fa.get_parent() as PlayerController
		if host == null:
			continue
		var head := host.global_position + Vector3(0.0, HeaderSystem.reach_of(fa.attribute_modifiers)[0], 0.0)
		if head.distance_to(ball.global_position) <= CONTEST_RADIUS:
			rivals.append(fa)
	if rivals.is_empty():
		return true
	contests += 1
	var best: Node = claimant
	var best_score := score + rng.randf() * NOISE
	var scores := {claimant: best_score}
	for fa: FootballActions in rivals:
		var host := fa.get_parent() as PlayerController
		var head := host.global_position + Vector3(0.0, HeaderSystem.reach_of(fa.attribute_modifiers)[0], 0.0)
		var s := fa.header.contest_score(host, fa.attribute_modifiers, head.distance_to(ball.global_position)) + rng.randf() * NOISE
		scores[fa] = s
		if s > best_score:
			best_score = s
			best = fa
	for fa: FootballActions in rivals:
		if fa != best:
			fa.header.cancel(true)
			(fa.get_parent() as PlayerController).lose_balance(0.3, 0.7)
	last = {"winner": best, "losers": rivals.size() if best == claimant else rivals.size(), "scores": scores}
	_decided_winner = best
	_decided_left = DECIDED_FOR
	return best == claimant
