# Flatpak Implementation Review — VexOS

**Feature:** Declarative Flatpak with Flathub and Application Installation  
**Date:** 2026-03-11  
**Reviewer:** QA Subagent  
**Verdict:** PASS

---

## 1. File Contents Reviewed

### 1.1 `modules/flatpak.nix` (full contents)

```nix
{ ... }:

{
  # ── Enable Flatpak ────────────────────────────────────────────────────
  services.flatpak.enable = true;

  # ── XDG Portal (explicit for clarity; GNOME already enables this) ─────
  xdg.portal.enable = true;

  # ── Declarative Flatpak applications (all from Flathub) ───────────────
  # nix-flatpak default remote is Flathub; no explicit remote declaration needed.
  services.flatpak.packages = [
    "com.bitwarden.desktop"
    "io.github.pol_rivero.github-desktop-plus"
    "com.github.tchx84.Flatseal"
    "it.mijorus.gearlever"
    "org.gimp.GIMP"
    "io.missioncenter.MissionCenter"
    "org.onlyoffice.desktopeditors"
    "org.prismlauncher.PrismLauncher"
    "com.rustdesk.RustDesk"
    "com.simplenote.Simplenote"
    "io.github.flattool.Warehouse"
    "app.zen_browser.zen"
  ];

  # ── Update policy ─────────────────────────────────────────────────────
  # false = install missing apps on rebuild, but do not auto-update existing ones.
  services.flatpak.update.onActivation = false;
}
```

### 1.2 `flake.nix` — Relevant Sections

**Input declaration:**
```nix
# Declarative Flatpak management
# Provides: nixosModules.nix-flatpak, homeManagerModules.nix-flatpak
nix-flatpak.url = "github:gmodena/nix-flatpak";
```

**Outputs function signature:**
```nix
outputs = { self, nixpkgs, home-manager, nix-flatpak, ... }@inputs:
```

**Module import in `mkVexosSystem`:**
```nix
# nix-flatpak declarative Flatpak management
nix-flatpak.nixosModules.nix-flatpak
```

### 1.3 `hosts/default/configuration.nix` — Imports Section

```nix
imports = [
  ../../modules/system.nix
  ../../modules/gnome.nix
  ../../modules/users.nix
  ../../modules/gpu.nix
  ../../modules/gaming.nix
  ../../modules/asus.nix
  ../../modules/flatpak.nix   # ← Flatpak module
];
```

---

## 2. Validation Checklist

| Check | Status | Notes |
|-------|--------|-------|
| `nix-flatpak` input in `flake.nix` | ✅ PASS | `github:gmodena/nix-flatpak` |
| `nix-flatpak` in `outputs` function args | ✅ PASS | Explicitly destructured |
| `nix-flatpak.nixosModules.nix-flatpak` in `mkVexosSystem` | ✅ PASS | Present with descriptive comment |
| `../../modules/flatpak.nix` imported in `hosts/default/configuration.nix` | ✅ PASS | Last entry in imports list |
| `services.flatpak.enable = true` | ✅ PASS | |
| `xdg.portal.enable = true` | ✅ PASS | Explicit (GNOME sets this too; redundant but correct) |
| `services.flatpak.update.onActivation = false` | ✅ PASS | Prevents rebuild-triggered updates |
| All 12 Flatpak app IDs present | ✅ PASS | See §3 below |
| Nix syntax valid | ✅ PASS | Proper `{ ... }:` module form, semicolons, list syntax |
| No deprecated options | ✅ PASS | Uses `nix-flatpak` module options, not nixpkgs builtin |
| Project conventions followed | ✅ PASS | Consistent with other modules |

---

## 3. Flatpak App ID Verification (All 12)

| # | App ID | Status |
|---|--------|--------|
| 1 | `com.bitwarden.desktop` | ✅ Present |
| 2 | `io.github.pol_rivero.github-desktop-plus` | ✅ Present |
| 3 | `com.github.tchx84.Flatseal` | ✅ Present |
| 4 | `it.mijorus.gearlever` | ✅ Present |
| 5 | `org.gimp.GIMP` | ✅ Present |
| 6 | `io.missioncenter.MissionCenter` | ✅ Present |
| 7 | `org.onlyoffice.desktopeditors` | ✅ Present |
| 8 | `org.prismlauncher.PrismLauncher` | ✅ Present |
| 9 | `com.rustdesk.RustDesk` | ✅ Present |
| 10 | `com.simplenote.Simplenote` | ✅ Present |
| 11 | `io.github.flattool.Warehouse` | ✅ Present |
| 12 | `app.zen_browser.zen` | ✅ Present |

**All 12 app IDs are present and correctly spelled.**

---

## 4. Issues Found

No critical issues were found. The following observations are noted for completeness:

### MINOR — `xdg.portal.enable` is redundant (not a defect)

`services.desktopManager.gnome.enable = true` (set in `modules/gnome.nix`) already enables
`xdg.portal.enable` and configures `xdg-desktop-portal-gnome` as the portal backend.
Setting `xdg.portal.enable = true` again in `flatpak.nix` is harmless — NixOS deduplicates
option assignments of this type — and adds defensive clarity. This is acceptable and aligns
with the spec's rationale.

**Severity:** MINOR (no action required)

### MINOR — `nix-flatpak` input does not pin `inputs.nixpkgs.follows`

```nix
nix-flatpak.url = "github:gmodena/nix-flatpak";
```

The `nix-flatpak` flake does not declare a `nixpkgs` input of its own, so
`inputs.nixpkgs.follows = "nixpkgs"` is not applicable here. This is correct as-is.

**Severity:** MINOR (not a defect; informational only)

---

## 5. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A (non-NixOS host) | N/A |

**Overall Grade: A (99%)**

---

## 6. Summary

The Flatpak implementation is **complete, correct, and fully aligned with the specification**.

- All 12 declarative Flatpak app IDs are present and correctly spelled.
- `nix-flatpak` is properly declared as a flake input, destructured in `outputs`, and wired into `mkVexosSystem` as a NixOS module.
- `modules/flatpak.nix` is correctly imported in `hosts/default/configuration.nix`.
- Nix syntax is valid throughout. No deprecated options are used.
- The update policy (`onActivation = false`) is set as required.
- No critical or recommended issues were found.

**Verdict: PASS**
