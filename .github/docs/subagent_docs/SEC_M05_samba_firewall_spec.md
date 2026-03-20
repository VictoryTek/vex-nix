# SEC-M05: Samba `openFirewall = true` — Specification

**Phase:** 1 — Research & Specification  
**Severity:** Medium  
**File affected:** `modules/system.nix`  
**Date:** 2026-03-19  

---

## 1. Exact Current Configuration (Verbatim)

```nix
# Enable Samba for file sharing
services.samba = {
  enable = true;
  openFirewall = true;
  settings = {
    global = {
      workgroup = "WORKGROUP";
      "server string" = "VexOS Samba Server";
      "netbios name" = "vexos";
      security = "user";
      "hosts allow" = "192.168. 127.0.0.1 localhost";
      "hosts deny" = "0.0.0.0/0";
      "guest account" = "nobody";
      "map to guest" = "never";  # Fail explicitly on bad credentials; no silent guest fallback
    };
    public = {
      path = "/home/nimda/Public";
      browseable = "yes";
      "read only" = "no";
      "guest ok" = "no";
      "create mask" = "0644";
      "directory mask" = "0755";
    };
  };
};
```

**Confirmed:** `openFirewall = true` is present on line ~57 of `modules/system.nix`.  
**Confirmed:** `hosts allow = "192.168. 127.0.0.1 localhost"` application-layer restriction is present.  
**Confirmed:** `hosts deny = "0.0.0.0/0"` explicit deny-all default is present.

The existing firewall block in `networking.firewall` explicitly leaves `allowedTCPPorts` and
`allowedUDPPorts` as empty lists, delegating Samba port management entirely to `openFirewall`:

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ ];
  allowedUDPPorts = [ ];
  trustedInterfaces = [ "tailscale0" ];
};
```

---

## 2. Mechanism of `openFirewall = true`

`services.samba.openFirewall = true` is a NixOS convenience option. When set, the NixOS
Samba module programmatically inserts the following rules into the kernel firewall
(nftables/iptables depending on NixOS version):

| Protocol | Ports | Purpose |
|----------|-------|---------|
| TCP | 139 (NetBIOS Session), 445 (SMB Direct) | File share connections |
| UDP | 137 (NetBIOS Name Service), 138 (NetBIOS Datagram) | Name browsing |

These rules apply to **all network interfaces** system-wide — there is no interface scoping
in the NixOS Samba module's `openFirewall` implementation.

---

## 3. Hardware Configuration Analysis

`hosts/default/hardware-configuration.nix` is a **template file** — it contains no
real network interface names. There are no `networking.interfaces.*` or
`networking.useDHCP` stanzas with interface names.

**Consequence:** No specific LAN interface name (e.g., `enp3s0`, `wlan0`) is declared
anywhere in the repository. Any fix requiring a hardcoded interface name would break
portability and require per-machine customisation.

---

## 4. Risk Assessment

### 4.1 Threat Model for This Machine

This is a personal ASUS TUF Gaming desktop/laptop running NixOS with:
- Tailscale VPN enabled (`tailscale0` is a trusted interface)
- No indication of direct internet exposure (typical home NAT router setup)
- Samba intended solely for LAN file sharing (`192.168.x.x` subnet)

### 4.2 Defence-in-Depth Layers Currently Present

| Layer | Mechanism | Effective? |
|-------|-----------|------------|
| Kernel firewall | `openFirewall = true` opens TCP 139/445, UDP 137/138 on all interfaces | Opens attack surface |
| Samba application-layer | `hosts allow = "192.168. 127.0.0.1 localhost"` | Rejects non-LAN IPs |
| Samba application-layer | `hosts deny = "0.0.0.0/0"` | Explicit deny-all default |
| Authentication | `security = user`, `guest ok = no`, `map to guest = never` | No anonymous access |

### 4.3 Is `openFirewall = true` + `hosts allow` Sufficient?

**Short answer: Yes, for a home LAN machine — but only marginally, and with an important caveat.**

The key question is: does Samba's `hosts allow` / `hosts deny` check fire **before** any
SMB protocol parsing that could be exploited?

**Linux Samba (smbd) connection flow:**

1. TCP connection accepted by kernel → passed to `smbd`
2. `smbd` checks `hosts allow` / `hosts deny` immediately in `check_access()`, before
   any SMB protocol message is read or parsed
3. If denied → TCP connection is closed immediately with no SMB data exchanged

This means that for unpatched vulnerabilities in the **SMB protocol parser** (pre-auth
remote code execution such as CVE-2017-7494 "SambaCry"), an attacker from outside
`192.168.x.x` would have their TCP connection closed before any malicious SMB payload
is parsed. The `hosts allow` check is a genuine pre-auth barrier in Samba's TCP
connection handling.

**However**, the kernel firewall still accepts and terminates the TCP three-way handshake
before smbd can close the connection. This means:
- Port scans from the internet (or any interface) will show TCP 445 as **open**, not
  filtered — advertising the Samba service to reconnaissance tooling
- The Samba daemon handles the initial TCP socket setup for every inbound connection,
  even those it will immediately reject — marginally increasing daemon load and logging
  noise under port-scan conditions

**EternalBlue (MS17-010) applicability:** EternalBlue targets a Windows SMB1 buffer
overflow in `srv.sys`. Linux `smbd` does not share this code path and has never been
vulnerable to the original EternalBlue. Samba CVEs with similar pre-auth RCE
characteristics (CVE-2017-7494, CVE-2021-44142) have all been patched promptly in
NixOS's tracked Samba package. Risk from known public exploits is low.

**Verdict:** `openFirewall = true` + `hosts allow` + `hosts deny` is **acceptable for a
home LAN** but is architecturally untidy. The ports are openly advertised on all
interfaces. A proper firewall rule scoped to the LAN interface is technically superior.

### 4.4 Why Not Option C (No Ports, Rely Solely on `hosts allow`)?

Setting `openFirewall = false` with no explicit `allowedTCPPorts` would cause NixOS's
firewall to **DROP** incoming SMB connections at the kernel level — including connections
from legitimate LAN clients on `192.168.x.x`. Samba would still listen but no LAN
client could reach it through the firewall. **This breaks functionality.**

Option C is only viable with interface-scoped rules (i.e., open ports only on the LAN
NIC, not on WAN/Tailscale NICs) — which requires knowing the interface name.

---

## 5. Options Considered

### Option A — Explicit Global Open (Recommended)

Replace `openFirewall = true` with `openFirewall = false` and move the Samba ports
explicitly into the `networking.firewall` block. This is **functionally identical** to
the current state (ports open on all interfaces) but removes the implicit side-effect of
`openFirewall`, makes firewall rules visible in one place, and provides a clear scaffold
for future interface scoping.

```nix
# Firewall configuration
networking.firewall = {
  enable = true;
  # Samba ports: open on all interfaces because interface names are not
  # hardcoded in this portable config. Inbound connections from outside
  # 192.168.x.x are rejected at the Samba application layer via
  # "hosts allow" / "hosts deny" before any SMB payload is parsed.
  # TODO: scope these to the LAN NIC once the interface name is known:
  #   networking.firewall.interfaces.<iface>.allowedTCPPorts = [ 139 445 ];
  #   networking.firewall.interfaces.<iface>.allowedUDPPorts = [ 137 138 ];
  allowedTCPPorts = [ 139 445 ];
  allowedUDPPorts = [ 137 138 ];
  trustedInterfaces = [ "tailscale0" ];
};
```

And in the Samba block, set `openFirewall = false`.

**Pros:**
- Firewall intent is explicit and readable in one block
- All port rules live in `networking.firewall`, the canonical location
- Removes implicit/magic behaviour of `openFirewall = true`
- No functional change — same attack surface
- Comment documents the path to a full interface-scoped fix
- Zero portability cost

**Cons:**
- Does not reduce the actual firewall attack surface vs. current state
- Still advertises ports on all interfaces

### Option B — Documentation Only

Keep `openFirewall = true`, add a comment block explaining the risk and the `hosts allow`
mitigation.

**Pros:** Zero risk of regression  
**Cons:** Does not address the architectural problem; leaves implicit magic behaviour

### Option C — Interface-Scoped Rules

`openFirewall = false` + `networking.firewall.interfaces.<iface>.allowedTCPPorts = [139 445]`.

**Pros:** True minimum-privilege firewall — ports only open on the LAN NIC  
**Cons:** Requires hardcoding an interface name; breaks portability of this config;
`hardware-configuration.nix` provides no interface name; would require per-machine
customisation instructions added to the README.

---

## 6. Chosen Fix: Option A

**Rationale:**

1. The hardware configuration is a template with no interface names — Option C is not
   viable without per-machine customisation that cannot be enforced in a portable flake.

2. `openFirewall = true` is a Nix module side-effect that silently injects firewall rules
   outside the `networking.firewall` block, violating the principle of having a single
   source of truth for firewall policy. Moving the ports to `networking.firewall` fixes
   this architectural issue.

3. The `hosts allow` + `hosts deny` combination in Samba's current config is a genuine
   pre-authentication barrier (closes the TCP connection before any SMB data is
   exchanged), making the net risk on a home LAN genuinely low.

4. The TODO comment in the firewall block provides a clear upgrade path to the fully
   scoped solution when the user knows their interface name.

5. This is the **minimal correct change**: it improves code quality, documents intent,
   and introduces no regression risk.

---

## 7. Exact Code Changes

### File: `modules/system.nix`

**Change 1** — Set `openFirewall = false` in the Samba block:

```nix
# Before
services.samba = {
  enable = true;
  openFirewall = true;

# After
services.samba = {
  enable = true;
  openFirewall = false;   # Ports managed explicitly in networking.firewall below
```

**Change 2** — Add Samba ports and explanatory comment to `networking.firewall`:

```nix
# Before
networking.firewall = {
  enable = true;
  # SSH is allowed by default when openssh is enabled
  # Tailscale manages its own firewall rules
  # Samba ports are opened by openFirewall = true above
  allowedTCPPorts = [ ];
  allowedUDPPorts = [ ];
  # Tailscale interface
  trustedInterfaces = [ "tailscale0" ];
};

# After
networking.firewall = {
  enable = true;
  # SSH is allowed by default when openssh is enabled.
  # Tailscale manages its own firewall rules.
  #
  # Samba file-sharing ports. These are intentionally opened on all interfaces
  # because this portable config does not hardcode a NIC name. Connections from
  # outside 192.168.x.x are rejected pre-authentication by Samba's own
  # "hosts allow = 192.168. 127.0.0.1 localhost" / "hosts deny = 0.0.0.0/0"
  # directives, which close the TCP socket before any SMB payload is parsed.
  #
  # To restrict to one NIC (preferred on multi-homed hosts), replace these two
  # lines with the interface-scoped form and update hardware-configuration.nix:
  #   networking.firewall.interfaces.<iface>.allowedTCPPorts = [ 139 445 ];
  #   networking.firewall.interfaces.<iface>.allowedUDPPorts = [ 137 138 ];
  allowedTCPPorts = [ 139 445 ];   # Samba: NetBIOS Session + SMB Direct
  allowedUDPPorts = [ 137 138 ];   # Samba: NetBIOS Name Service + Datagram
  # Tailscale WireGuard interface — fully trusted (VPN peer-authenticated)
  trustedInterfaces = [ "tailscale0" ];
};
```

---

## 8. Files to Be Modified

| File | Change |
|------|--------|
| `modules/system.nix` | `openFirewall = false`; populate `allowedTCPPorts`/`allowedUDPPorts`; update comment |

No other files require modification.

---

## 9. Verification

After applying the fix:

```bash
# Flake validity
nix flake check

# Confirm evaluation succeeds
nix eval .#nixosConfigurations.vexos.config.services.samba.openFirewall
# expected: false

nix eval .#nixosConfigurations.vexos.config.networking.firewall.allowedTCPPorts
# expected: [ 139 445 ]

nix eval .#nixosConfigurations.vexos.config.networking.firewall.allowedUDPPorts
# expected: [ 137 138 ]
```

---

## 10. Summary

| Item | Detail |
|------|--------|
| Bug confirmed | Yes — `openFirewall = true` opens SMB ports on all interfaces at kernel level |
| Truly exploitable? | Low risk on home LAN; `hosts allow`+`hosts deny` is a genuine pre-auth barrier in smbd |
| Chosen fix | Option A: `openFirewall = false` + explicit `allowedTCPPorts`/`allowedUDPPorts` |
| Functional impact | None — identical firewall behaviour, improved explicitness |
| Files modified | `modules/system.nix` (1 file, 2 adjacent hunks) |
| Portability | Fully maintained — no interface name hardcoding |
