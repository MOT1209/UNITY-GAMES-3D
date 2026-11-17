class_name ContractOffer
extends RefCounted

## Personal terms offered to a player (new signing or renewal). The player answers with
## `TransferMarket.player_response()`: accept, a counter demand, or a refusal with a reason.

const ROLES: Array[String] = ["star", "starter", "rotation", "backup", "prospect"]
## Wage expectation of each promised role, relative to the player's fair wage.
const ROLE_WAGE := {"star": 1.25, "starter": 1.0, "rotation": 0.9, "backup": 0.8, "prospect": 0.75}

var salary: int = 0                   # per week
var years: int = 3                    # 1-5
var signing_bonus: int = 0
var release_clause: int = 0           # 0 = none
var squad_role: String = "rotation"
var loyalty_bonus: int = 0            # paid at the end of the contract (optional)


static func make(p_salary: int, p_years: int, p_role := "rotation", p_bonus := 0, p_clause := 0, p_loyalty := 0) -> ContractOffer:
	var c := ContractOffer.new()
	c.salary = p_salary
	c.years = p_years
	c.squad_role = p_role if p_role in ROLES else "rotation"
	c.signing_bonus = maxi(0, p_bonus)
	c.release_clause = maxi(0, p_clause)
	c.loyalty_bonus = maxi(0, p_loyalty)
	return c


func to_dict() -> Dictionary:
	return {"salary": salary, "years": years, "signing_bonus": signing_bonus, "release_clause": release_clause,
			"squad_role": squad_role, "loyalty_bonus": loyalty_bonus}


static func from_dict(d: Dictionary) -> ContractOffer:
	return make(int(d.get("salary", 0)), int(d.get("years", 3)), str(d.get("squad_role", "rotation")),
			int(d.get("signing_bonus", 0)), int(d.get("release_clause", 0)), int(d.get("loyalty_bonus", 0)))
