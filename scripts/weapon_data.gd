class_name WeaponData
## Weapon configuration — maps weapon name to stats.
## Controllers and skills read from here so range is defined by weapon, not character.

const STATS := {
	"axe":    { "attack_range": 80.0  },
	"book":   { "attack_range": 250.0 },
	"blade":  { "attack_range": 80.0  },
	"shield": { "attack_range": 80.0  },
}


static func get_attack_range(weapon_name: String, fallback: float = 80.0) -> float:
	if STATS.has(weapon_name):
		return float(STATS[weapon_name].get("attack_range", fallback))
	return fallback


## Helper: reads weapon_name from any owner node's animation child
static func get_owner_weapon(owner_node: Node2D) -> String:
	for child in owner_node.get_children():
		if "weapon_name" in child:
			return str(child.get("weapon_name"))
	return ""
