class_name CountryData
extends Resource

## Country record (Phase 2 of the database system). `country_id` is the stable key;
## `country_name` is the name stored in TeamData.country / PlayerData.nationality
## (kept as text for backward compatibility with existing data and saves).

const PATH := "res://data/countries.json"
const STATUSES: Array[String] = ["REAL_VERIFIED", "REAL_PARTIAL", "FICTIONAL", "PLANNED"]

@export var country_id: String = ""
@export var country_name: String = ""
@export var country_code: String = ""
@export var nationality_name: String = ""
@export var flag_asset: String = ""      # "" = no flag asset yet
@export var region: String = ""
@export var database_status: String = "PLANNED"


func validate() -> Array[String]:
	var errors: Array[String] = []
	if country_id.strip_edges() == "":
		errors.append("country has empty id")
	if country_name.strip_edges() == "":
		errors.append("country '%s' has empty name" % country_id)
	if country_code.length() != 3:
		errors.append("country '%s' code must be 3 letters" % country_id)
	if not (database_status in STATUSES):
		errors.append("country '%s' has unknown status '%s'" % [country_id, database_status])
	if flag_asset != "" and not ResourceLoader.exists(flag_asset) and not FileAccess.file_exists(flag_asset):
		errors.append("country '%s' flag asset missing: %s" % [country_id, flag_asset])
	return errors


func to_dict() -> Dictionary:
	return {"country_id": country_id, "country_name": country_name, "country_code": country_code,
			"nationality_name": nationality_name, "flag_asset": flag_asset, "region": region,
			"database_status": database_status}


static func from_dict(d: Dictionary) -> CountryData:
	var c := CountryData.new()
	c.country_id = str(d.get("country_id", ""))
	c.country_name = str(d.get("country_name", ""))
	c.country_code = str(d.get("country_code", ""))
	c.nationality_name = str(d.get("nationality_name", ""))
	c.flag_asset = str(d.get("flag_asset", ""))
	c.region = str(d.get("region", ""))
	c.database_status = str(d.get("database_status", "PLANNED"))
	return c
