# SEC-M07: Kernel sysctl Hardening — Specification
**Phase**: 1 — Research & Specification  
**Severity**: Medium  
**Analyst**: Phase 1 Research Agent  
**Date**: 2026-03-19  
**Target file**: `modules/system.nix`

---

## 1. Gap Confirmation

### 1.1 Search Results

A full-text search for `boot.kernel.sysctl` and `sysctl` was executed across every `.nix`
file in the repository. **Zero matches** were found in any production module:

| File | `boot.kernel.sysctl` present? |
|------|-------------------------------|
| `modules/system.nix` | ❌ Not present |
| `modules/kernel.nix` | ❌ Not present |
| `modules/gaming.nix` | ❌ Not present |
| `modules/gpu.nix` | ❌ Not present |
| `modules/gnome.nix` | ❌ Not present |
| `modules/asus.nix` | ❌ Not present |
| `hosts/default/configuration.nix` | ❌ Not present |
| `home/default.nix` | ❌ Not present |
| `flake.nix` | ❌ Not present |

**Finding: The gap is real.** No security-focused kernel sysctl hardening exists anywhere
in the codebase. Several kernel parameters remain at their insecure defaults.

### 1.2 Historical Context

Prior documentation (`package_gaming_asus_spec.md`, `nix_gaming_spec.md`) shows that
`modules/gaming.nix` previously contained a `boot.kernel.sysctl` block with two
*performance* entries (`vm.max_map_count`, `kernel.split_lock_mitigate`). These were
**intentionally removed** and superseded by `nix-gaming.nixosModules.platformOptimizations`
(which is active in `flake.nix`). That transition was purely a performance-tuning
consolidation — it left no security-relevant sysctl settings behind.

---

## 2. Current Configuration Analysis

### 2.1 Active Kernel

`hosts/default/configuration.nix` sets:

```nix
kernel.type = "stock";
```

This resolves to `pkgs.linuxPackages_zen` (NixOS Zen kernel). The Zen kernel carries
**no compile-time sysctl hardening overrides** — all security-relevant parameters are at
the mainline Linux defaults (dmesg_restrict = 0, kptr_restrict = 0, etc.).

### 2.2 Active Modules

The configuration imports all modules in `hosts/default/configuration.nix` and loads the
following NixOS modules via `flake.nix`:

- `inputs.nix-gaming.nixosModules.platformOptimizations` — **active**
- `inputs.nix-gaming.nixosModules.pipewireLowLatency` — active
- `nix-flatpak.nixosModules.nix-flatpak` — active
- `home-manager.nixosModules.home-manager` — active

### 2.3 platformOptimizations Sysctls (No Overlap)

The active `platformOptimizations` module sets exactly the following sysctls:

| Key | Value | Purpose |
|-----|-------|---------|
| `vm.max_map_count` | `2147483642` | Game memory-map headroom (SteamOS default) |
| `kernel.split_lock_mitigate` | `0` | Suppress split-lock performance penalty |
| `kernel.sched_cfs_bandwidth_slice_us` | `3000` | Tighter CFS scheduling |
| `net.ipv4.tcp_fin_timeout` | `5` | Faster TCP teardown |

**None of these overlap with the proposed security sysctl set.** No `mkForce`/`mkDefault`
precedence wrangling is required.

---

## 3. CachyOS Kernel Interaction

### 3.1 Current Kernel (stock / Zen)

No hardening compile-time defaults. All parameters start at mainline defaults (insecure).
We must set every desired value explicitly.

### 3.2 cachyos-hardened Variant

`modules/kernel.nix` supports `kernel.type = "cachyos-hardened"`. The CachyOS hardened
kernel is built with a security-focused Kconfig that applies several compile-time defaults:

| Parameter | cachyos-hardened compile default | NixOS sysctl override? |
|-----------|----------------------------------|------------------------|
| `kernel.dmesg_restrict` | Likely `1` via `CONFIG_SECURITY_DMESG_RESTRICT=y` | Still correct to set explicitly |
| `kernel.kptr_restrict` | Partial (`CONFIG_SECURITY_KPTR_STRICT` affects pointers) | Still correct to set |
| `kernel.unprivileged_bpf_disabled` | Likely `1` in hardened config | Still correct |

**Key architectural decision**: NixOS `boot.kernel.sysctl` settings are **runtime sysctl
values applied at boot** by systemd/sysctl.d. They are always authoritative regardless of
kernel compile-time defaults. Setting them explicitly in NixOS modules has three benefits:

1. **Portability**: Security settings apply regardless of which `kernel.type` is selected
   (stock, cachyos-gaming, cachyos-server, etc.) — not only for cachyos-hardened.
2. **Auditability**: Security posture is visible in the declarative NixOS configuration;
   no need to inspect kernel Kconfig to understand what is enforced.
3. **Reproducibility**: The NixOS configuration is the single source of truth.

**Conclusion**: Configure the sysctl block in `modules/system.nix` without
kernel-variant conditionals. It applies correctly to all kernel variants.

---

## 4. Gaming Compatibility Assessment

### 4.1 Current Gaming Configuration State

`modules/gaming.nix` has Steam, Proton (`proton-ge-bin`), and the nix-gaming cache
**commented out** with the note "Steam blocked on work network". GameMode IS enabled and
active. PipeWire low-latency IS active.

This means currently:
- No Steam process runs on the system
- No Wine/Proton processes exist
- GameMode daemon is active but does not use ptrace

### 4.2 Per-Parameter Gaming Impact Analysis

| Parameter | Value | Gaming Impact | Verdict |
|-----------|-------|---------------|---------|
| `kernel.dmesg_restrict` | `1` | None — games do not read dmesg | ✅ Safe |
| `kernel.kptr_restrict` | `2` | None — games do not read `/proc/kallsyms` | ✅ Safe |
| `kernel.randomize_va_space` | `2` | Already default; occasional very old 32-bit game may crash (pre-2005) | ✅ Safe for modern games |
| `kernel.unprivileged_bpf_disabled` | `1` | None — games do not use eBPF | ✅ Safe |
| `net.core.bpf_jit_harden` | `2` | None — games do not use eBPF JIT | ✅ Safe |
| `kernel.yama.ptrace_scope` | `1` | See §4.3 below | ⚠️ Requires analysis |
| `net.ipv4.conf.all.accept_redirects` | `0` | Negligible — ICMP redirects are not gaming-critical | ✅ Safe |
| `net.ipv4.conf.all.send_redirects` | `0` | This host is not a router; no impact | ✅ Safe |
| `net.ipv4.conf.all.accept_source_route` | `0` | Games do not use source routing | ✅ Safe |
| `net.ipv4.conf.all.log_martians` | `1` | Log-only; no impact on connectivity | ✅ Safe |
| `net.ipv4.conf.all.rp_filter` | `1` | See §4.4 Tailscale note | ✅ Safe (see note) |
| `fs.suid_dumpable` | `0` | No game requires SUID core dumps | ✅ Safe |

### 4.3 ptrace_scope Decision — INCLUDE at = 1

**The question**: Does `kernel.yama.ptrace_scope = 1` break Steam, Wine, Proton, or
GameMode?

**Scope levels**:
- `0` — Any process may ptrace any other user-owned process. **Insecure default**.
- `1` — A process may only ptrace its own descendants, OR processes that explicitly
  granted ptrace access via `prctl(PR_SET_PTRACER, ...)`.
- `2` — Only processes with `CAP_SYS_PTRACE` may ptrace. Breaks Steam overlay.
- `3` — No process may ptrace. Breaks debuggers and introspection entirely.

**Analysis**:

- **Steam**: Steam launches games as direct child processes. The Steam overlay attaches
  to the game process. Since the game is a **child** of the Steam process, the overlay's
  ptrace attach succeeds at scope 1. ✅
- **Proton/Wine**: `wineserver` manages Wine processes. All Wine/Proton processes are
  part of the same process tree forked from the Steam child. `wineserver` only ptrace's
  its own child Windows processes. ✅ at scope 1.
- **GE-Proton** (`proton-ge-bin`): Same architecture as upstream Proton. ✅
- **GameMode**: Does not use ptrace. Changes process niceness and CPU governor only. ✅
- **nix-gaming `platformOptimizations`**: Kernel/scheduler tuning only; no ptrace. ✅
- **Anti-cheat (EAC, BattlEye)**: These run as kernel-mode drivers on Windows but on
  Linux via Proton they use kernel APIs, not user-space ptrace. ✅
- **Escape cases**: Some third-party launchers (Heroic/Legendary for Epic, Lutris) may
  spawn game processes in a separate session (not children of the launcher), then attempt
  to attach via ptrace. This would fail at scope 1. However:
  - Heroic and Lutris are not part of this configuration (no Flatpak entries for them)
  - If added later, the affected launcher can call `prctl(PR_SET_PTRACER, ...)` to
    grant access, or the user can override with `kernel.yama.ptrace_scope = 0` in
    `hardware-configuration.nix` for the specific machine

**Recommendation: INCLUDE `kernel.yama.ptrace_scope = 1`.**  
It is safe for the current configuration (GameMode only) and safe when Steam/Proton are
re-enabled, because both use parent-child ptrace relationships. A comment in the module
will document when to relax to scope 0.

### 4.4 Tailscale and rp_filter

The system uses Tailscale (`services.tailscale.enable = true`). Tailscale uses WireGuard
for encapsulation. When Tailscale is active:

1. Outbound Tailscale traffic is encapsulated as WireGuard UDP packets sent through the
   physical interface (eth0/wlan0). The source IP is the host's real IP → `rp_filter`
   check passes.
2. Inbound Tailscale traffic arrives as WireGuard UDP on the physical interface, then is
   decapsulated and delivered via the `tailscale0` virtual interface. The
   decapsulated packet's source is a `100.x.x.x` Tailscale IP, which is routable via
   `tailscale0` → `rp_filter` on `tailscale0` passes.
3. `rp_filter = 1` on the `all` sysctl applies a **strict** check. Tailscale handles
   routing correctly and this is well-known to work with strict `rp_filter`.

**Conclusion**: `rp_filter = 1` is safe with Tailscale.

---

## 5. NixOS Implementation Best Practice

### 5.1 NixOS Option

The correct NixOS option is:

```nix
boot.kernel.sysctl = {
  "parameter.name" = value;
  # ...
};
```

This is a well-established, stable NixOS option (present since at least NixOS 18.03).
It is processed at boot via `systemd-sysctl` and applied before user session login.
Multiple modules may define `boot.kernel.sysctl` entries; NixOS merges the
attrset — no conflicts unless the same key is defined in multiple places (verified: no
overlap with `platformOptimizations`).

### 5.2 Placement

The sysctl block belongs in **`modules/system.nix`** because:

1. The module already houses cross-cutting system security configuration: SSH hardening,
   Samba host restrictions, firewall rules (nftables), Docker rootless.
2. Kernel security parameters are analogous in scope — system-wide, not
   hardware-specific.
3. No new module is warranted for a single attrset addition (avoids file proliferation).

**Exact location within `modules/system.nix`**: Insert the block after the
`networking.firewall` closing brace (after line ~92) and before `services.printing`.
Both are security-adjacent settings. Grouping them preserves the file's logical flow:
networking/firewall → kernel security → application services.

---

## 6. Final Sysctl Block

The following is the exact Nix code to add to `modules/system.nix`:

```nix
  # Kernel security hardening via sysctl
  # Applied at boot by systemd-sysctl; overrides kernel compile-time defaults.
  # Safe for gaming: Steam/Proton use parent-child ptrace (scope 1 is compatible);
  # games do not use eBPF; ICMP redirect restrictions have negligible network impact.
  boot.kernel.sysctl = {

    # ── Kernel Information Exposure ──────────────────────────────────────────
    # Restrict /dev/kmsg and the dmesg syscall to root.
    # Prevents non-root from reading the kernel ring buffer, which can leak
    # kernel virtual addresses useful for exploit development.
    "kernel.dmesg_restrict"                      = 1;

    # Hide kernel symbol addresses from unprivileged users (/proc/kallsyms,
    # /proc/modules, /sys/kernel/debug/...). Level 2 hides from all users
    # including root, defeating KASLR bypass primitives in most exploits.
    # If root-level kernel profiling is required (perf, bpftrace), temporarily
    # override via: sysctl -w kernel.kptr_restrict=0
    "kernel.kptr_restrict"                       = 2;

    # Full address-space layout randomisation — randomise stack, vdso, and
    # mmap base. This is the Linux default (2) on modern kernels; stated
    # explicitly here for auditability and to catch accidental regression.
    "kernel.randomize_va_space"                  = 2;

    # ── eBPF Hardening ───────────────────────────────────────────────────────
    # Disable creation of eBPF programs by non-privileged users. Unprivileged
    # eBPF is a significant privilege-escalation surface; games do not use it.
    "kernel.unprivileged_bpf_disabled"           = 1;

    # Harden the eBPF JIT compiler: constant blinding (prevents JIT spraying)
    # and suppresses /proc/kallsyms exposure of JIT code. Level 2 = full
    # hardening. No gaming impact.
    "net.core.bpf_jit_harden"                   = 2;

    # ── ptrace Hardening ─────────────────────────────────────────────────────
    # Restrict ptrace to parent-child process relationships (Yama scope 1).
    # Scope 0 (default): any user process may ptrace any other user-owned process.
    # Scope 1: a process may only ptrace its own descendants or processes that
    #          explicitly grant access via prctl(PR_SET_PTRACER).
    # Safe for Steam: Steam launches games as children; the overlay attaches to
    # child game processes. Safe for Proton/Wine: wineserver only ptrace's its
    # own child Windows processes. GameMode does not use ptrace.
    # If third-party launchers (Heroic, Lutris) break, set scope = 0 in
    # hardware-configuration.nix for the specific host.
    "kernel.yama.ptrace_scope"                   = 1;

    # ── Network Hardening ────────────────────────────────────────────────────
    # Ignore inbound ICMP redirect messages. A rogue gateway or on-path
    # attacker can use redirects to manipulate the routing table.
    "net.ipv4.conf.all.accept_redirects"         = 0;
    "net.ipv4.conf.default.accept_redirects"     = 0;

    # Do not send ICMP redirects — this host is not a router.
    "net.ipv4.conf.all.send_redirects"           = 0;
    "net.ipv4.conf.default.send_redirects"       = 0;

    # Reject source-routed packets (rare in practice; disabled by default on
    # most distros but stated explicitly for auditability).
    "net.ipv4.conf.all.accept_source_route"      = 0;
    "net.ipv4.conf.default.accept_source_route"  = 0;

    # Log packets with unroutable (martian) source addresses. Aids detection
    # of spoofed or source-routed traffic on the local segment.
    "net.ipv4.conf.all.log_martians"             = 1;

    # Strict reverse-path filtering: drop packets whose source address is not
    # reachable via the interface they arrived on. Defeats IP spoofing.
    # Safe with Tailscale: WireGuard encapsulation preserves outer-packet
    # routing symmetry; 100.x.x.x addresses are delivered via tailscale0.
    "net.ipv4.conf.all.rp_filter"                = 1;
    "net.ipv4.conf.default.rp_filter"            = 1;

    # ── Filesystem ──────────────────────────────────────────────────────────
    # Disable core dumps for SUID/SGID executables. Prevents a privileged
    # process from leaking memory contents into a world-readable core file.
    # Already the kernel default (0) but stated explicitly for auditability.
    "fs.suid_dumpable"                           = 0;
  };
```

---

## 7. Per-Parameter Justification Table

| Parameter | Value | Justification | Gaming Safe? |
|-----------|-------|---------------|--------------|
| `kernel.dmesg_restrict` | `1` | Blocks non-root dmesg reads; prevents kernel address leakage useful in exploit development | ✅ Yes |
| `kernel.kptr_restrict` | `2` | Hides kernel symbol addresses from all users; defeats most KASLR bypass primitives | ✅ Yes |
| `kernel.randomize_va_space` | `2` | Full ASLR; already the default; stated for auditability | ✅ Yes |
| `kernel.unprivileged_bpf_disabled` | `1` | Eliminates non-root eBPF privilege escalation surface | ✅ Yes |
| `net.core.bpf_jit_harden` | `2` | Prevents JIT spraying via eBPF; suppresses JIT symbol exposure | ✅ Yes |
| `kernel.yama.ptrace_scope` | `1` | Restricts ptrace to parent-child; safe for Steam/Proton architecture | ✅ Yes (see §4.3) |
| `net.ipv4.conf.all.accept_redirects` | `0` | Blocks ICMP routing table manipulation | ✅ Yes |
| `net.ipv4.conf.default.accept_redirects` | `0` | Same, for newly added interfaces | ✅ Yes |
| `net.ipv4.conf.all.send_redirects` | `0` | This host is not a router | ✅ Yes |
| `net.ipv4.conf.default.send_redirects` | `0` | Same, for newly added interfaces | ✅ Yes |
| `net.ipv4.conf.all.accept_source_route` | `0` | Rejects source-routed packets | ✅ Yes |
| `net.ipv4.conf.default.accept_source_route` | `0` | Same, for newly added interfaces | ✅ Yes |
| `net.ipv4.conf.all.log_martians` | `1` | Logs spoofed/unroutable traffic for visibility | ✅ Yes |
| `net.ipv4.conf.all.rp_filter` | `1` | Strict reverse-path filtering; anti-IP-spoofing | ✅ Yes |
| `net.ipv4.conf.default.rp_filter` | `1` | Same, for newly added interfaces | ✅ Yes |
| `fs.suid_dumpable` | `0` | Prevents SUID core dump memory leakage | ✅ Yes |

**Parameters intentionally excluded**:

| Parameter | Reason for Exclusion |
|-----------|----------------------|
| `kernel.perf_event_paranoid = 3` | Would break `perf` for non-root; level 2 (distro default) is sufficient |
| `vm.mmap_rnd_bits = 32` | Can break old 32-bit game binaries; default entropy is adequate |
| `vm.mmap_rnd_compat_bits = 16` | Same concern for 32-bit compatibility |
| `net.ipv6.conf.*` | IPv6 redirect settings omitted; IPv6 state not confirmed; lower-priority |
| `kernel.modules_disabled = 1` | Would block driver loading after boot; breaks dynamic GPU/USB drivers |
| `kernel.sysrq = 0` | Overly restrictive; sysrq is useful for recovery on this desktop system |

---

## 8. ptrace_scope — Explicit Decision Record

**Decision: INCLUDE `kernel.yama.ptrace_scope = 1`**

| Factor | Analysis |
|--------|----------|
| Current gaming state | Steam/Proton/Wine disabled in `gaming.nix` (work network restriction) |
| GameMode | Active; does NOT use ptrace — completely unaffected |
| Steam (when re-enabled) | Launches games as child processes; overlay attaches to children → scope 1 compatible |
| Proton/Wine (when re-enabled) | `wineserver` manages its own child processes only → scope 1 compatible |
| Anti-cheat | EAC/BattlEye on Linux use kernel interfaces; not ptrace-dependent |
| Risk at scope 1 | Third-party launchers that fork-and-attach outside the parent-child tree may break; documented in code comment with override path |
| Security benefit | Prevents process injection attacks between unrelated user processes; significant reduction in local privilege escalation surface |
| Alternative (exclude) | Would leave `ptrace_scope = 0`; any user process can attach a debugger/tracer to any other user-owned process at will — unacceptable for a multi-user-capable system |

**Override path if a specific game/launcher breaks**:  
Add to `hosts/default/hardware-configuration.nix` or a new host-specific override:
```nix
boot.kernel.sysctl."kernel.yama.ptrace_scope" = 0;
```

---

## 9. Implementation Instructions

### 9.1 File to Modify

**`modules/system.nix`** — single file change.

### 9.2 Insertion Point

Insert the `boot.kernel.sysctl` block **after** the `networking.firewall` closing brace
and **before** `services.printing.enable = true`. The logical grouping is:

```
networking.firewall { ... }        ← existing
boot.kernel.sysctl { ... }         ← INSERT HERE
services.printing.enable = true;   ← existing
```

### 9.3 No Other Files Required

- `modules/kernel.nix` — no change; kernel selection is orthogonal to runtime sysctls
- `hosts/default/configuration.nix` — no change; sysctls are in shared module
- `flake.nix` — no change; no new inputs or modules required
- `home/` — no change; userspace settings are unaffected
- `modules/gaming.nix` — no change; platformOptimizations sysctls do not conflict

### 9.4 Verification After Implementation

```bash
# Evaluate the configuration (must not error)
nix eval .#nixosConfigurations.vexos.config.system.build.toplevel --apply builtins.typeOf

# Validate the sysctl attrset merges correctly
nix eval .#nixosConfigurations.vexos.config.boot.kernel.sysctl

# Full flake check
nix flake check
```

---

## 10. Risk Assessment

| Risk | Probability | Severity | Mitigation |
|------|-------------|----------|------------|
| ptrace_scope = 1 breaks a specific game launcher | Low (Steam/Proton safe; current launchers not affected) | Low | Per-host override documented in code comment |
| rp_filter = 1 breaks Tailscale | Very Low | Medium | WireGuard encapsulation is rp_filter-compatible; well-documented upstream |
| kptr_restrict = 2 breaks a root sysadmin tool | Low | Low | Temporary: `sysctl -w kernel.kptr_restrict=0`; not persistent across reboots |
| Conflict with future platformOptimizations update | Very Low | Low | No key overlap; NixOS will error loudly on conflict |
| cachyos-hardened + explicit sysctl = double-setting | None | None | Runtime sysctl always wins; idempotent no-op if kernel compiled with same default |

---

## 11. Summary

### Is This a Real Security Gap?
**Yes.** The kernel is running with all security-relevant sysctl parameters at their
insecure defaults. An unprivileged local user can:
- Read dmesg to discover kernel virtual addresses (`dmesg_restrict = 0`)
- Read `/proc/kallsyms` to find kernel symbol addresses for KASLR bypass (`kptr_restrict = 0`)
- Create eBPF programs to explore privilege escalation primitives (`unprivileged_bpf_disabled = 0`)
- Trace/attach to any other user-owned process (`yama.ptrace_scope = 0`)
- Have routing table manipulated by rogue ICMP redirects (`accept_redirects = 1`)

### Final Recommended Sysctl List (16 entries)

```
kernel.dmesg_restrict                 = 1
kernel.kptr_restrict                  = 2
kernel.randomize_va_space             = 2
kernel.unprivileged_bpf_disabled      = 1
net.core.bpf_jit_harden              = 2
kernel.yama.ptrace_scope              = 1   ← INCLUDED (safe for Steam/Proton, see §4.3)
net.ipv4.conf.all.accept_redirects    = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects      = 0
net.ipv4.conf.default.send_redirects  = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians        = 1
net.ipv4.conf.all.rp_filter           = 1
net.ipv4.conf.default.rp_filter       = 1
fs.suid_dumpable                      = 0
```

### ptrace_scope: INCLUDE at = 1
Steam/Proton/Wine use parent-child ptrace relationships that remain fully functional at
scope 1. GameMode does not use ptrace. Risk of breakage is low and mitigated by a
documented per-host override path.

### Files to be Modified

- **`modules/system.nix`** — add `boot.kernel.sysctl` block after `networking.firewall`

### Spec File Path

`.github/docs/subagent_docs/SEC_M07_sysctl_hardening_spec.md`
