# BUG-02 Specification: Docker Group Privilege Escalation → Rootless Docker

**Severity:** High  
**Status:** Specification Draft  
**Affects:** `modules/system.nix`, `modules/users.nix`  
**Possibly Affects:** `home/default.nix`

---

## 1. Current Configuration Analysis

### `modules/system.nix` (lines ~107–109)

```nix
# Docker
virtualisation.docker.enable = true;
virtualisation.docker.enableOnBoot = true;
```

This starts a **system-wide Docker daemon running as root**, with its socket at
`/run/docker.sock`. The socket is owned by `root:docker` with mode `0660`.

### `modules/users.nix` (lines ~9–14)

```nix
extraGroups = [
  "networkmanager"
  "wheel"
  "audio"
  "video"
  "docker"      # ← THE BUG
  "libvirtd"
  "gamemode"
];
```

User `nimda` is a member of the `docker` group, granting read-write access to
`/run/docker.sock`.

### `home/default.nix`

No Docker-related environment variables are present. `home.sessionVariables`
currently contains only Wayland/Qt variables.

---

## 2. Problem Definition

### Privilege Escalation Path

The Docker daemon runs as root. Its UNIX socket `/run/docker.sock` is
group-writable (`srw-rw---- root docker`). Any process that can write to this
socket can instruct the Docker daemon to:

1. Spawn a container with the host root filesystem bind-mounted.
2. Request `--privileged` mode (full Linux capabilities, no seccomp filter).
3. `chroot` into the mounted host root as UID 0.

**One-liner exploit:**

```bash
docker run --rm -v /:/host --privileged alpine chroot /host bash
```

This gives a fully interactive root shell on the host with:
- Read/write access to every file on the host system
- Ability to install kernel modules
- Ability to modify `/etc/sudoers`, `/etc/shadow`, SSH keys
- Ability to escape any container isolation entirely

**Why group membership equals root:**  
The Docker daemon itself has no concept of multi-tenancy. Any client that
connects to the socket is implicitly trusted as root. The `docker` group
is therefore documented by Docker, NixOS, and security references as
**functionally equivalent to UID 0**.

Reference: NixOS Wiki on Docker:
> "Note that membership in the 'docker' group is equivalent to root privileges."

### Attack Surface in VexOS

Because VexOS runs GNOME with an auto-login on boot (`services.displayManager.autoLogin`),
the user session — and all processes spawned by it including browser sandboxes,
Flatpak apps, VS Code extensions, npm scripts, and `rustup`-installed toolchains —
inherit full `docker` group membership from the moment the system boots. Any
supply-chain or code-execution vulnerability in any of those tools immediately
yields root access with zero additional steps.

---

## 3. Proposed Solution: Rootless Docker

### Security Model Comparison

| Property | Root Docker (current) | Rootless Docker (proposed) |
|---|---|---|
| Daemon runs as | root (UID 0) | nimda (UID 1000) |
| Socket path | `/run/docker.sock` | `/run/user/1000/docker.sock` |
| Socket permissions | root:docker 0660 | nimda:nimda 0600 |
| Group needed | `docker` (= root) | None |
| Privileged containers | Allowed | Restricted |
| `--net=host` | Allowed | Requires extra config |
| Port < 1024 binding | Allowed | Needs sysctl |
| Host filesystem RW | Trivial via sock | Not accessible via sock |
| Exploit via sock | Root in 1 command | Cannot escalate past UID 1000 |

### Rootless Docker NixOS Options (Context7-verified, NixOS 25.11)

Source: NixOS Wiki — https://wiki.nixos.org/wiki/Docker

```nix
virtualisation.docker = {
  # Disable the system-wide root daemon — rootless replaces it entirely
  enable = false;

  rootless = {
    enable = true;          # Installs docker-rootless, creates user systemd unit
    setSocketVariable = true; # Sets DOCKER_HOST via PAM env for all login sessions
  };
};
```

**`virtualisation.docker.rootless.enable`**  
When `true`, NixOS installs `docker-rootless` and provisions a systemd user
service (`docker.service`) that runs under the target user's UID. The socket
is placed at `$XDG_RUNTIME_DIR/docker.sock` (typically
`/run/user/1000/docker.sock`).

**`virtualisation.docker.rootless.setSocketVariable`**  
When `true`, NixOS writes `DOCKER_HOST=unix:///run/user/<uid>/docker.sock` into
the PAM environment (`/etc/environment` or equivalent pam_env configuration),
which causes the variable to be available in all login sessions (TTY, GDM,
SSH). This means **no manual `DOCKER_HOST` entry is needed** in
`home/default.nix` or `home.sessionVariables`.

**`virtualisation.docker.enableOnBoot`**  
This option controls whether the *system-wide* Docker service is started at
boot. It is irrelevant once `enable = false`. It should be removed to avoid
a conflicting option evaluation warning.

### Do `enable` and `rootless.enable` Coexist?

They can coexist (`enable = true` + `rootless.enable = true`) but this is
incorrect for the purpose of this fix: the system-wide root daemon would still
be running and the `docker` group would still be meaningful. The fix requires
`enable = false` so that **only** the rootless daemon exists. The NixOS Wiki
explicitly recommends disabling the system-wide daemon when switching to
rootless mode.

### `"docker"` Group in `extraGroups`

After the fix, the `"docker"` group entry in `extraGroups` serves no purpose
and must be removed. The rootless Docker socket is owned by the user directly
(`nimda:nimda 0600`); group membership is not required or consulted.

### Linger: Rootless Service Persistence

By default, a user's systemd instance (and its services) only runs while that
user has at least one active login session. Without `linger`, if all sessions
for `nimda` end (e.g., a remote headless build server scenario), the rootless
Docker daemon stops and all running containers die.

For VexOS, which uses GNOME auto-login, the session is always active when the
machine is running. Linger is not strictly required for interactive desktop use.
However, it is **recommended** for correctness and consistency:

```nix
users.users.nimda.linger = true;
```

This ensures the rootless Docker daemon starts at boot (even before GDM's
auto-login completes) and survives any transient session gaps. It has no
security downside — it simply keeps the user slice alive.

---

## 4. Interaction with `modules/gnome.nix` (libvirtd)

`modules/gnome.nix` enables `virtualisation.libvirtd`. This is a **separate
virtualisation stack** (QEMU/KVM guest management) that runs as a system
daemon under `root` and is controlled via polkit. The user `nimda` is in the
`libvirtd` group, which grants polkit permission to manage VMs.

**Rootless Docker does not conflict with libvirtd:**

- They use different networking bridges (`docker0` for Docker vs
  `virbr0` for libvirt).
- They manage different resource types (OCI containers vs KVM VMs).
- They use different IPC mechanisms (Docker socket vs libvirt socket/D-Bus).
- The `libvirtd` group membership in `extraGroups` **must be retained** —
  removing it would break GNOME Boxes and virt-manager.

No changes required in `modules/gnome.nix`.

---

## 5. Implementation Steps

The following ordered changes constitute the complete fix.

### Step 1 — `modules/system.nix`

**Replace:**
```nix
# Docker
virtualisation.docker.enable = true;
virtualisation.docker.enableOnBoot = true;
```

**With:**
```nix
# Docker — rootless mode eliminates the docker group privilege escalation (BUG-02).
# The system-wide root daemon is disabled; only the per-user rootless daemon runs.
# DOCKER_HOST is set automatically for all login sessions via setSocketVariable.
virtualisation.docker.rootless = {
  enable = true;
  setSocketVariable = true;
};
```

### Step 2 — `modules/users.nix`

**Remove** `"docker"` from `extraGroups`.

**Add** `linger = true` to the `users.users.nimda` attribute set.

**Before:**
```nix
users.users.nimda = {
  isNormalUser = true;
  description = "Nimda";
  extraGroups = [ 
    "networkmanager" 
    "wheel"
    "audio"
    "video"
    "docker"
    "libvirtd"
    "gamemode"
  ];
  shell = pkgs.bash;
```

**After:**
```nix
users.users.nimda = {
  isNormalUser = true;
  description = "Nimda";
  extraGroups = [ 
    "networkmanager" 
    "wheel"
    "audio"
    "video"
    "libvirtd"
    "gamemode"
  ];
  # Linger keeps the user systemd slice (and rootless Docker) alive at boot
  # even before the first interactive login session is established.
  linger = true;
  shell = pkgs.bash;
```

### Step 3 — `home/default.nix`

**No changes required.**

`virtualisation.docker.rootless.setSocketVariable = true` causes NixOS to
inject `DOCKER_HOST=unix:///run/user/1000/docker.sock` via PAM, which is
sourced by all login sessions including GDM/Wayland. Adding a duplicate
`DOCKER_HOST` entry in `home.sessionVariables` would be redundant and could
cause conflicts if the runtime UID differs from 1000.

---

## 6. Files Modified

| File | Change |
|---|---|
| `modules/system.nix` | Replace system-wide Docker with rootless configuration |
| `modules/users.nix` | Remove `"docker"` group; add `linger = true` |
| `home/default.nix` | No changes needed |
| `modules/gnome.nix` | No changes needed |

---

## 7. Verification Steps

After `sudo nixos-rebuild switch --flake .#vexos`:

### 7.1 Confirm system-wide Docker daemon is gone
```bash
systemctl status docker.service
# Expected: Unit not found OR inactive/dead
```

### 7.2 Confirm rootless daemon is running
```bash
systemctl --user status docker.service
# Expected: Active (running)
docker info | grep -i rootless
# Expected: rootless appears in SecurityOptions
```

### 7.3 Confirm DOCKER_HOST is set automatically
```bash
echo $DOCKER_HOST
# Expected: unix:///run/user/1000/docker.sock
```

### 7.4 Confirm the escalation path is closed
```bash
# Old exploit — must now FAIL
docker run --rm -v /:/host --privileged alpine chroot /host bash
# Expected: Error — if rootless mode is working correctly, --privileged
# containers are restricted (they run in a user namespace, not as real root).
# The container's root is nimda's UID on the host; host /etc is not writable.
```

### 7.5 Confirm `nimda` is no longer in the `docker` group
```bash
id nimda | grep docker
# Expected: no output (group absent)
groups
# Expected: docker absent from the output
```

### 7.6 Confirm Docker still works for normal operations
```bash
docker run --rm hello-world
# Expected: Hello from Docker! (rootless daemon responds correctly)
```

### 7.7 Confirm linger is active
```bash
loginctl show-user nimda | grep Linger
# Expected: Linger=yes
```

### 7.8 Run flake check
```bash
nix flake check
# Expected: no errors
```

---

## 8. Ripple Effects

### `oci-containers` backend (if used in future)
`virtualisation.oci-containers.backend = "docker"` works with both root and
rootless Docker. If this backend is added in future, it will automatically use
the user-level daemon when rootless is configured. No additional changes needed.

### `scripts/deploy.sh` / `scripts/install.sh`
Review for any `newgrp docker` calls or Docker socket path hardcoding. In
rootless mode, the socket is at `$XDG_RUNTIME_DIR/docker.sock`, not
`/var/run/docker.sock`. If any script uses `/var/run/docker.sock` or
`/run/docker.sock` explicitly, it must be updated.

### `modules/flatpak.nix`
No interaction — Flatpak uses its own sandboxing. Not affected.

### `modules/gaming.nix`
No Docker interaction. Not affected.

---

## 9. Risks and Mitigations

### Risk 1: Privileged containers no longer work
**Description:** `docker run --privileged` inside rootless mode runs in a
user namespace. The container's UID 0 maps to `nimda` (UID 1000) on the host.
Operations that require real host root (loading kernel modules, mounting
arbitrary filesystems) will fail.

**Mitigation:** This is intentional — it is the security guarantee. For the
current VexOS use cases (development, Flatpak, gaming, GNOME), privileged
containers are not required. If a specific workload genuinely requires
privileged mode, it should use `virt-manager`/GNOME Boxes (already configured)
instead of Docker.

### Risk 2: Port binding below 1024
**Description:** Rootless containers cannot bind to ports < 1024 by default
because only root can bind low ports on Linux.

**Mitigation:** Not currently required by VexOS. If needed in future, add:
```nix
boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;
```

### Risk 3: `--net=host` is restricted in rootless
**Description:** Host network mode in rootless Docker uses `slirp4netns` or
`pasta` rather than a real host network namespace. Performance is lower and
some multicast/raw socket features may be unavailable.

**Mitigation:** Not currently required by VexOS. Rootless networking is
sufficient for development and build workloads.

### Risk 4: Storage driver differences
**Description:** Rootless Docker uses `overlay2` with `fuse-overlayfs` on
kernels that do not support unprivileged overlayfs. NixOS 25.11 ships a kernel
new enough to support native unprivileged overlay, so performance is unchanged.

**Mitigation:** Verify storage driver after rebuild:
```bash
docker info | grep "Storage Driver"
# Expected: overlay2
```

### Risk 5: `docker-compose` / Compose V2
**Description:** `docker compose` (Compose V2, the plugin) is bundled with the
Docker CLI and works transparently with rootless Docker. No changes needed.

### Risk 6: Linger has no security downside but persists services after logout
**Description:** `linger = true` means the user slice is kept alive at all
times. Containers started by `nimda` will continue to run whether or not the
user is logged in.

**Mitigation:** For a single-user desktop this is the intended behavior.
The security boundary is unchanged: containers run as `nimda` UID, not root.

---

## 10. Sources

1. NixOS Wiki — Docker: https://wiki.nixos.org/wiki/Docker  
   Confirms `virtualisation.docker.rootless.enable` / `setSocketVariable` options
   and recommends `enable = false` when switching to rootless.

2. NixOS Wiki — Docker (English): https://wiki.nixos.org/wiki/Docker/en  
   States explicitly: "membership in the 'docker' group is equivalent to root privileges."

3. NixOS Wiki — Systemd/User Services: https://wiki.nixos.org/wiki/Systemd/User_Services  
   Confirms `users.users.<username>.linger = true` declarative syntax.

4. NixOS Wiki — Security: https://wiki.nixos.org/wiki/Security  
   Confirms Docker container isolation via namespacing controls.

5. Docker Documentation — Rootless mode:
   https://docs.docker.com/engine/security/rootless/  
   Authoritative source on rootless architecture, user namespace mapping,
   and capability restrictions.

6. NixOS Manual (unstable): https://nixos.org/manual/nixos/unstable/  
   Reference for NixOS module evaluation and virtualisation options.

7. CVE databases / Docker security advisories:  
   Docker socket as a privilege escalation vector is well-documented and
   categorised as a known design property, not a bug in Docker itself — the
   group membership model is the attack surface.
