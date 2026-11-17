class_name KingControllerNetwork
extends RefCounted

## LAN address selection for the pairing URL (P9.7). The old code took the first 192.168.* address (or the
## first anything), which on a PC with Hyper-V / WSL / VirtualBox / VPN adapters is often a virtual network
## the phone cannot reach. This ranks the addresses of `IP.get_local_interfaces()` instead:
##   * never: loopback, 0.0.0.0, link-local (169.254.*, no DHCP), multicast, IPv6;
##   * ranked down: adapters whose name says virtual / VPN / bridge (vEthernet, VirtualBox, VMware, WSL,
##     docker, tun / tap, Tailscale, ZeroTier, WireGuard, ...), and 100.64.0.0/10 (CGNAT / Tailscale);
##   * preferred: Wi-Fi / Ethernet adapters with a private address (192.168 > 10 > 172.16-31).
## Pure function over a plain data list, so it is tested with the exact adapter names Windows uses.

const VIRTUAL_HINTS: Array[String] = ["vethernet", "virtualbox", "vmware", "hyper-v", "wsl", "docker", "veth",
		"br-", "virbr", "tun", "tap", "tailscale", "zerotier", "wireguard", "wg", "vpn", "utun", "loopback",
		"pseudo", "bluetooth", "vboxnet", "vmnet", "podman", "lxc", "npcap", "teredo", "isatap"]
const PREFERRED_HINTS: Array[String] = ["wi-fi", "wifi", "wlan", "wireless", "wlp", "ethernet", "eth", "en0", "en1", "enp", "eno"]

enum Kind { PRIVATE_LAN, VIRTUAL_OR_VPN, CGNAT, OTHER }


## Classification of one IPv4 address: "" when it can never be a LAN address, else a Kind name.
static func classify(address: String) -> String:
	if address.find(":") >= 0:
		return ""                                  # IPv6: the pairing URL is IPv4
	var p := address.split(".")
	if p.size() != 4:
		return ""
	for part in p:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return ""
	var a := int(p[0])
	var b := int(p[1])
	if a == 127 or a == 0 or a >= 224:
		return ""                                  # loopback, unspecified, multicast / reserved
	if a == 169 and b == 254:
		return ""                                  # link-local: the adapter has no real network (no DHCP)
	if a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31):
		return "private"
	if a == 100 and b >= 64 and b <= 127:
		return "cgnat"
	return "other"


static func looks_virtual(interface_name: String) -> bool:
	var n := interface_name.to_lower()
	for h in VIRTUAL_HINTS:
		if n.contains(h):
			return true
	return false


static func looks_preferred(interface_name: String) -> bool:
	var n := interface_name.to_lower()
	for h in PREFERRED_HINTS:
		if n.contains(h):
			return true
	return false


## `interfaces` = IP.get_local_interfaces() format: [{name, friendly, addresses: [String]}].
## Returns {best, candidates, error, rejected}. candidates: [{address, interface, kind, score, note}] best
## first; `error`: "" | "no_interface" | "only_link_local" | "no_private_address". `best` is "" on error —
## the caller must show a message, not a loopback URL.
static func choose(interfaces: Array) -> Dictionary:
	var cands: Array = []
	var rejected: Array = []
	var saw_link_local := false
	var saw_any_ipv4 := false
	for itf in interfaces:
		var iname := str(itf.get("friendly", itf.get("name", "")))
		if iname == "":
			iname = str(itf.get("name", ""))
		for addr in itf.get("addresses", []):
			var kind := classify(str(addr))
			if str(addr).find(":") < 0:
				saw_any_ipv4 = true
			if str(addr).begins_with("169.254."):
				saw_link_local = true
			if kind == "":
				rejected.append({"address": str(addr), "interface": iname})
				continue
			var score := 0
			var note := ""
			match kind:
				"private":
					score = 100
					var parts := str(addr).split(".")
					if int(parts[0]) == 192:
						score += 20
					elif int(parts[0]) == 10:
						score += 10
				"cgnat":
					score = 30
					note = "vpn_or_cgnat"
				_:
					score = 20
					note = "not_private"
			if looks_virtual(iname):
				score -= 70
				note = "virtual_or_vpn"
			elif looks_preferred(iname):
				score += 15
			cands.append({"address": str(addr), "interface": iname, "kind": kind, "score": score, "note": note})
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["score"] != y["score"]:
			return x["score"] > y["score"]
		return str(x["address"]) < str(y["address"]))
	var out := {"best": "", "candidates": cands, "error": "", "rejected": rejected}
	if cands.is_empty():
		out["error"] = "only_link_local" if saw_link_local else ("no_private_address" if saw_any_ipv4 else "no_interface")
		return out
	# A virtual / VPN adapter is a candidate the user may pick, but never chosen automatically when a real
	# LAN address exists; when it is the only one, it is still better than nothing but flagged.
	out["best"] = str(cands[0]["address"])
	return out


## Live data of this machine in the same format as `choose` expects.
static func local_interfaces() -> Array:
	return IP.get_local_interfaces()
