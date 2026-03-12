# Plymouth Boot Splash — Review & Quality Assurance

**Feature**: Silent graphical boot splash screen using Plymouth  
**Project**: VexOS NixOS Flake Configuration  
**Review Date**: 2026-03-11  
**Reviewer**: QA Subagent  
**Spec**: `.github/docs/subagent_docs/plymouth_spec.md`

---

## 1. Files Reviewed

- `modules/plymouth.nix`
- `hosts/default/configuration.nix`
- `modules/gpu.nix`
- `modules/system.nix`
- `modules/gnome.nix`

---

## 2. Full Content of `modules/plymouth.nix`

```nix
{ config, lib, pkgs, ... }:

{
  # Plymouth boot splash screen
  boot.plymouth = {
    enable = true;
    theme = "breeze";
    themePackages = [ pkgs.breeze-plymouth ];
  };

  # Silent boot kernel parameters for a clean Plymouth experience
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "udev.log_priority=3"
    "rd.systemd.show_status=auto"
  ];

  # Reduce kernel console log noise during boot
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;

  # KMS (Kernel Mode Setting) modules for early Plymouth display.
  # These must be loaded in initrd so Plymouth can show the splash
  # before the full kernel drivers are loaded.
  boot.initrd.kernelModules = lib.optionals (config.gpu.type == "intel") [ "i915" ]
    ++ lib.optionals (config.gpu.type == "amd") [ "amdgpu" ]
    ++ lib.optionals (config.gpu.type == "nvidia") [
      "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"
    ];

  # Hide grub menu on boot (press Shift during POST to interrupt).
  # A non-zero timeout is kept here to allow interruption if needed.
  boot.loader.grub.timeoutStyle = "hidden";
  boot.loader.timeout = 0;
}
```

---

## 3. Validation Checklist

### 3.1 plymouth.nix

| Check | Status | Notes |
|-------|--------|-------|
| `boot.plymouth.enable = true` | ✅ PASS | Present |
| `boot.plymouth.theme = "breeze"` | ✅ PASS | Present |
| `boot.plymouth.themePackages = [ pkgs.breeze-plymouth ]` | ✅ PASS | Present |
| Kernel param `quiet` | ✅ PASS | Present |
| Kernel param `splash` | ✅ PASS | Present |
| Kernel param `boot.shell_on_fail` | ✅ PASS | Present |
| Kernel param `udev.log_priority=3` | ✅ PASS | Present |
| Kernel param `rd.systemd.show_status=auto` | ✅ PASS | Present |
| `boot.consoleLogLevel = 3` | ✅ PASS | Present |
| `boot.initrd.verbose = false` | ✅ PASS | Present |
| KMS: `lib.optionals` for `intel` → `[ "i915" ]` | ✅ PASS | Present |
| KMS: `lib.optionals` for `amd` → `[ "amdgpu" ]` | ✅ PASS | Present |
| KMS: `lib.optionals` for `nvidia` → all 4 modules | ✅ PASS | Present |
| KMS: `"none"` → empty list (no modules) | ✅ PASS | Correct by exclusion — all three conditions false |
| `boot.loader.grub.timeoutStyle = "hidden"` | ✅ PASS | Present |
| `boot.loader.timeout = 0` | ✅ PASS | Present |
| Function signature includes `lib` | ✅ PASS | `{ config, lib, pkgs, ... }:` |
| Valid Nix syntax | ✅ PASS | Brackets, semicolons, string quoting all correct |

### 3.2 hosts/default/configuration.nix — Import Check

The imports list contains:

```nix
../../modules/plymouth.nix
```

✅ **PASS** — Plymouth module is correctly imported.

---

## 4. Cross-Module Conflict Analysis

### 4.1 `boot.loader.grub.*` Conflicts

`hosts/default/configuration.nix` sets:
```nix
boot.loader.grub.enable = true;
boot.loader.grub.device = "/dev/sda";
```

`modules/plymouth.nix` sets:
```nix
boot.loader.grub.timeoutStyle = "hidden";
boot.loader.timeout = 0;
```

**Assessment**: No conflict. These are distinct attributes within the `boot.loader.grub` attrset and `boot.loader` respectively. NixOS merges them cleanly. `timeoutStyle` and `timeout` do not interfere with `enable` or `device`.

✅ **PASS**

### 4.2 `boot.kernelParams` Conflicts

Checked: `modules/system.nix`, `modules/gnome.nix`, `modules/gpu.nix`, `hosts/default/configuration.nix`.

**Result**: No other module or host file sets `boot.kernelParams`. The five parameters introduced by `plymouth.nix` are additive with no collision risk.

✅ **PASS**

### 4.3 `boot.initrd.kernelModules` Conflicts

Checked all modules and the host configuration file.

**Result**: `boot.initrd.kernelModules` is not set in any other file. `gpu.nix` does not set it — GPU drivers are configured via `services.xserver.videoDrivers` and `hardware.nvidia`/`hardware.graphics` options, not via initrd kernel modules. No conflict.

✅ **PASS**

---

## 5. Critical Verification: `gpu.type` Option Declaration in `modules/gpu.nix`

The `plymouth.nix` references `config.gpu.type` in three `lib.optionals` expressions. This requires `options.gpu.type` to be declared as a proper NixOS option in the module system. If it were absent, Nix evaluation would fail with an "attribute not found" or "undefined variable" error.

From `modules/gpu.nix`:

```nix
options.gpu = {
    type = lib.mkOption {
      type    = lib.types.enum [ "none" "intel" "amd" "nvidia" ];
      default = "none";
      description = ''
        Select the GPU driver stack to configure.
          "none"   — No GPU-specific configuration (VM/headless safe default).
          "intel"  — Intel integrated graphics (modesetting + VA-API media driver).
          "amd"    — AMD discrete/integrated GPU (amdgpu + RADV Vulkan).
          "nvidia" — NVIDIA proprietary driver (requires Turing architecture or newer
                     for the open kernel module; set open = false for older cards).
      '';
    };
    ...
};
```

**Assessment**:

- `options.gpu.type` IS declared using `lib.mkOption`. ✅
- The type is `lib.types.enum [ "none" "intel" "amd" "nvidia" ]`. ✅
- Default is `"none"`. ✅
- All values referenced in `plymouth.nix` (`"intel"`, `"amd"`, `"nvidia"`) are valid enum members. ✅
- `gpu.nix` is imported before `plymouth.nix` in `configuration.nix` (it appears earlier in the imports list), though module evaluation order in NixOS is declarative, not sequential — this is irrelevant but noted. ✅

✅ **PASS — No critical issue. `config.gpu.type` will evaluate correctly.**

---

## 6. Issues Found

### CRITICAL
None.

### RECOMMENDED
None.

### MINOR

**M-1: Misleading comment in `plymouth.nix`**

The comment directly above `boot.loader.timeout = 0` reads:

```nix
# Hide grub menu on boot (press Shift during POST to interrupt).
# A non-zero timeout is kept here to allow interruption if needed.
boot.loader.timeout = 0;
```

The second line of the comment says "A non-zero timeout is kept here" but the value is `0` (zero). This is factually incorrect and potentially confusing to future maintainers who might think the value should be non-zero. The mechanism for interrupting GRUB is via the `Shift` key with `timeoutStyle = "hidden"`, not a non-zero timeout value. The comment should be corrected.

**Suggested fix**:
```nix
# Hide grub menu on boot — hold Shift during BIOS POST to interrupt and show the GRUB menu.
# timeout = 0 boots the default entry immediately without any countdown delay.
boot.loader.timeout = 0;
```

---

## 7. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 97% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A (non-NixOS host) | N/A |

**Overall Grade: A (99%)**

---

## 8. Summary

The Plymouth implementation is **complete and correct**. All required options are present and properly configured:

- `boot.plymouth` is fully enabled with the `breeze` theme and `pkgs.breeze-plymouth` theme package.
- All five silent-boot kernel parameters are set correctly.
- `boot.consoleLogLevel = 3` and `boot.initrd.verbose = false` suppress boot verbosity.
- KMS initrd modules are conditionally loaded via `lib.optionals` against `config.gpu.type`, correctly handling all four valid GPU types.
- GRUB timeout is hidden with `timeoutStyle = "hidden"` and `timeout = 0`.
- `modules/plymouth.nix` is imported in `hosts/default/configuration.nix`.
- **Critically**: `options.gpu.type` is properly declared as a `lib.mkOption` with `lib.types.enum` in `modules/gpu.nix`. The `config.gpu.type` references in `plymouth.nix` will evaluate without error.
- No cross-module conflicts exist for `boot.kernelParams`, `boot.initrd.kernelModules`, or `boot.loader.grub.*`.

One **minor** documentation error was found: a comment incorrectly states "A non-zero timeout is kept here" while the actual value is `0`.

---

## 9. Verdict

**PASS**

The implementation is functionally complete, spec-compliant, and free of critical issues. Only one minor comment correction is recommended (non-blocking).
