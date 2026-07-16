# TFWWorkbench MO2 Patcher

Makes [**TFWWorkbench**](https://github.com/smotti/TFWWorkbench) (smotti) work properly under
**Mod Organizer 2** for *The Forever Winter*.

Two things stop a stock TFWWorkbench release from behaving under MO2. Neither is TFWWorkbench's
fault exactly — both come from MO2's virtual filesystem (USVFS) — and neither produces a useful
error. This script fixes both, in place, on **your own copy**.

> **This repo ships no TFWWorkbench code.** TFWWorkbench has no licence
> ([no LICENSE file, `licenseInfo: null`](https://github.com/smotti/TFWWorkbench)), so it is
> "all rights reserved" and not ours to redistribute. You download the release yourself; this
> script only *transforms* what you already have, and verifies it first by hash.

Companion to [**ForeverWinterMO2Support**](https://github.com/dataterminals/ForeverWinterMO2Support)
— the MO2 game plugin for TFW. **Fix #2 below depends on it.**

---

## What it fixes

### 1. `enabled.txt` is missing → the mod never starts, silently

UE4SS starts a Lua mod one of two ways: it is listed in `ue4ss/Mods/mods.txt`, or it ships an
`enabled.txt` marker. **Stock TFWWorkbench releases ship neither.** It is absent from the stock
`mods.txt`, and the release zip contains no `enabled.txt`.

Bundled distributions (e.g. the Construction Vendor all-in-one) add the marker for you, which is
why this bites people who install the *official* release and assume they got the same thing.

Symptom: no `Starting C++ mod` line, no TFWWorkbench output at all, no error. The mod is simply
never started.

Fix: create the 0-byte `enabled.txt`.

### 2. `Settings.ModChildDirs` → ~160 `cmd.exe` spawns per launch, achieving nothing

`CreateModChildDirs()` builds TFWWorkbench's `DataTable/` tree by shelling out:

```lua
os.execute(string.format("if exist \"%s\" (true)", childDirPath))   -- probe
os.execute(string.format("mkdir \"%s\"", childDirPath))             -- create
```

Under MO2, `os.execute` spawns a `cmd.exe` child that **access-violates immediately**
(`0xC0000005` / `-1073741819`) — the likely cause being USVFS hooking `CreateProcess` and
injecting into the child. So:

* every probe returns falsy → `if failed then` never fires → **no `mkdir` is ever attempted**;
* the loop still runs, once per child, per DataTable handler.

With 20 handlers × 8 children that is **160 `cmd.exe` spawns**, ~60 seconds of windows flashing
across your screen on every single launch, to accomplish precisely nothing.

Worse, when the tree genuinely is missing, `FindOrCreateModDir()` returns `nil` and the failure
surfaces three frames downstream as `attempt to index a nil value (local 'modDir')` — which reads
like a TFWWorkbench bug rather than an environment one.

Fix: empty `Settings.ModChildDirs`. It is the **only** consumer of that table, and collection is
unaffected — `main.lua` iterates `modDir.DataTable`, the real snapshotted directory tree, never
this table.

> **⚠ This makes TFWWorkbench dependent on something else creating the tree.**
> Under MO2 that is [ForeverWinterMO2Support](https://github.com/dataterminals/ForeverWinterMO2Support)
> v0.2.0+, which pre-creates it in MO2's Overwrite folder *before the game process starts*.
> **Do not apply fix #2 to a non-MO2 install** — use `-Revert`, or `-EnabledTxtOnly`.

---

## Usage

```powershell
# auto-detect TFWWorkbench inside your MO2 mods folder
.\Patch-TFWWorkbench.ps1 -ModsPath "H:\MO2Instance_ModData\ForeverWinter\mods"

# or point straight at the mod
.\Patch-TFWWorkbench.ps1 -Path "...\ue4ss\Mods\TFWWorkbench"

# marker only — safe for non-MO2 installs
.\Patch-TFWWorkbench.ps1 -Path "..." -EnabledTxtOnly

# undo (restores Settings.lua from the .bak, removes enabled.txt)
.\Patch-TFWWorkbench.ps1 -Path "..." -Revert
```

The script is **idempotent**, backs up `Settings.lua` before touching it, and refuses to run on a
build whose hashes it does not recognise unless you pass `-Force`.

## Verified against

| Release | File | Size | SHA-256 |
|---|---|---|---|
| 0.2.1 | `TFWWorkbench-v0.2.1.zip` | 133,156 | `13461844995d8c40…` |
| 0.2.1 | `Scripts/Settings.lua` | 3,155 | `2f1363e04b99c5f6…` |
| 0.2.1 | `Scripts/main.lua` | 27,064 | `2230fa8cce69b957…` |
| 0.2.1 | `dlls/main.dll` | 219,136 | `24b05dc267dc6e9f…` |

Full list in [`hashes.json`](hashes.json). An unrecognised hash is a warning, not a wall — but do
re-read `Settings.lua` first, because **`ModChildDirs` is the contract**: if a future release
changes that list, the plugin's pre-created tree must change with it.

## See also

* [`docs/WHY.md`](docs/WHY.md) — the evidence, the traps, and what is *not* proven.
* [ForeverWinterMO2Support](https://github.com/dataterminals/ForeverWinterMO2Support) — the MO2 plugin.
* [tfworkbench-compat-research](https://github.com/dataterminals/tfworkbench-compat-research) —
  why TFWWorkbench needs UE4SS pinned to `v3.0.1-894-g2172883`, and what breaks otherwise.

## Licence

[MIT](LICENSE) — covers **this script only**. TFWWorkbench is smotti's work under its own (absent)
terms; nothing of it is included or redistributed here.
