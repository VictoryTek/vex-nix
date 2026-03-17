# GNOME Clock 12-Hour Format — Implementation Specification

**Feature:** Set GNOME clock to 12-hour AM/PM format  
**Date:** 2026-03-16  
**Status:** Ready for Implementation

---

## 1. Current Configuration Analysis

### Home Manager (`home/default.nix`)

The file already contains a `dconf.settings` block (line 124) with the following sections:

| dconf path | Keys already set |
|---|---|
| `org/gnome/shell` | `enabled-extensions`, `favorite-apps` |
| `org/gnome/desktop/interface` | `icon-theme`, `cursor-theme`, `cursor-size` |
| `org/gnome/desktop/wm/preferences` | `button-layout` |
| `org/gnome/desktop/background` | `picture-uri`, `picture-uri-dark`, `picture-options` |
| `org/gnome/shell/extensions/dash-to-dock` | `dock-position` |
| `org/gnome/desktop/screensaver` | `lock-enabled` |

**Critically:** The `org/gnome/desktop/interface` path is **already declared** in `dconf.settings`.  
The `clock-format` key is **absent** — it must be added to that existing block.

### System-level (`modules/gnome.nix`)

No clock-format or gsettings override is set at the system level.  
The module enables `services.desktopManager.gnome.enable = true` with standard GNOME.

### Host config (`hosts/default/configuration.nix`)

- Timezone: `America/New_York`
- Locale: `en_US.UTF-8`
- No clock override present.

### Conclusion

No `clock-format` setting exists anywhere in the repository. GNOME defaults to `24h` on NixOS regardless of locale. The change must be applied via Home Manager `dconf.settings`.

---

## 2. GSettings Key and Value

| Property | Value |
|---|---|
| GSettings schema | `org.gnome.desktop.interface` |
| dconf path | `org/gnome/desktop/interface` |
| Key | `clock-format` |
| Value for 12-hour | `'12h'` (GVariant string) |
| Value for 24-hour | `'24h'` (GVariant string) |

The GVariant type is `s` (string). Valid values are `12h` and `24h`.

---

## 3. Placement Decision

**File to modify:** `home/default.nix`  
**Reason:** An `"org/gnome/desktop/interface"` block already exists there.  
Adding `clock-format` to that block is the minimal, non-duplicating change.  
No new file or module is needed.

**Do NOT add this to:**
- `modules/gnome.nix` — system-level NixOS modules cannot set per-user dconf keys via `programs.dconf`; the `glib.schemas` approach would affect all users and is less precise.
- A new home module — unnecessary complexity for a single key.

---

## 4. Exact Nix Code to Add

Locate the existing `"org/gnome/desktop/interface"` block in `home/default.nix`:

```nix
# BEFORE (current state, lines ~134-138)
"org/gnome/desktop/interface" = {
  icon-theme = "kora";
  cursor-theme = "Bibata-Modern-Classic";
  cursor-size = 24;
};
```

```nix
# AFTER (add clock-format)
"org/gnome/desktop/interface" = {
  icon-theme = "kora";
  cursor-theme = "Bibata-Modern-Classic";
  cursor-size = 24;
  clock-format = "12h";
};
```

---

## 5. `lib.hm.gvariant` Wrapper — Required or Not?

**Not required.** Home Manager automatically converts plain Nix strings to GVariant strings
for dconf settings. The existing `home/default.nix` confirms this pattern:

```nix
icon-theme = "kora";           # plain Nix string → GVariant 's' — works correctly
cursor-theme = "Bibata-Modern-Classic"; # same pattern
```

Using `lib.hm.gvariant.mkString "12h"` is semantically equivalent and is only necessary
when the type would otherwise be ambiguous (e.g., distinguishing a string from a bytestring,
or constructing variant arrays). For a simple `s`-typed key like `clock-format`, a plain
Nix string is idiomatic and consistent with the rest of the file.

**Confirmed for:** home-manager `release-25.11` (as declared in `flake.nix`).

---

## 6. Implementation Steps

1. Open `home/default.nix`.
2. Locate the `dconf.settings."org/gnome/desktop/interface"` attribute set.
3. Add the line `clock-format = "12h";` inside that block.
4. Run `nix flake check` to validate the change.
5. Run `sudo nixos-rebuild switch --flake .#vexos` to apply (or use the `just` workflow).

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| User has manually changed clock-format via GNOME Settings / dconf-editor | Low | The dconf override will re-apply on next `nixos-rebuild switch`, resetting any manual change. This is expected/desired Home Manager behaviour. |
| Conflict with a system-level `programs.dconf.enable` or similar | None | No system-level dconf override exists in this repo. |
| GVariant type mismatch (e.g. `12h` being misinterpreted) | None | Both `"12h"` plain string and `lib.hm.gvariant.mkString "12h"` produce the correct GVariant `s` type. `nix flake check` will catch evaluation errors. |
| `gnome-clocks` package absence affecting this key | None | `gnome-clocks` is excluded in `modules/gnome.nix`, but `clock-format` is in `org.gnome.desktop.interface` (GNOME Shell / control center schema), not in `gnome-clocks`. The key works independently. |
| `home-manager.useGlobalPkgs = true` import side effects | None | This flag only affects package sources; dconf settings are unaffected. |

---

## 8. Summary

**Change:** Add one key to one existing attribute set.  
**File:** `home/default.nix`  
**Line:** Inside `dconf.settings."org/gnome/desktop/interface"` block (~line 135).  
**Key/value:** `clock-format = "12h";`  
**No new files, no new imports, no new modules required.**
