# Why this patcher exists

Everything below was observed on a real install (2026-07-16), not inferred. Where something is
inference, it says so.

## 1. `enabled.txt` — the mod never starts

UE4SS starts a Lua mod one of two ways:

* the mod is listed in `ue4ss/Mods/mods.txt`, → logs `Starting C++ mod 'X'`
* or it ships an `enabled.txt` marker, → logs `Mod 'X' has enabled.txt, starting mod.`

**Stock TFWWorkbench releases satisfy neither.** `TFWWorkbench-v0.2.1.zip` contains
`Scripts/`, `dlls/main.dll` and `Examples/` — no `enabled.txt` — and the stock UE4SS `mods.txt`
has no TFWWorkbench line. So a by-the-book install of the official release **silently never runs**.

Bundled distributions (the Construction Vendor all-in-one, the community Codex AIO) add the marker
for you. That is why this bites people who install the *official* release and reasonably assume
they got the same thing the bundles ship.

> **Log-marker trap.** Do not probe for `Starting C++ mod` to decide whether TFWWorkbench loaded.
> That string is emitted **only** for the mods.txt path. Since TFWWorkbench takes the enabled.txt
> path, the marker is a **false negative** — it is absent from logs where the mod demonstrably
> loaded. Probe for `[TFWWorkbench] Registered Lua functions for mod` instead, which is the C++
> half announcing itself. (Related: a bare `0x7f` grep matches every `0x7ff…` address in the log.
> Match `ERROR_PROC_NOT_FOUND` instead.)

## 2. `ModChildDirs` — 160 `cmd.exe` spawns to accomplish nothing

`CreateModChildDirs()` (main.lua) builds the `DataTable/` tree by shelling out — a probe and a
create, per child:

```lua
local failed = os.execute(string.format("if exist \"%s\" (true)", childDirPath))
if failed then
    os.execute(string.format("mkdir \"%s\"", childDirPath))
end
```

Under MO2, `os.execute` spawns a `cmd.exe` child which **access-violates immediately**:

```
[Lua] [TFWWorkbench] Failed to create directory: exit - -1073741819
```

`-1073741819` is `0xC0000005`, `STATUS_ACCESS_VIOLATION`.

**Verified:** the crash, the exit code, and the resulting nil-deref chain. **Inferred:** *why* the
child dies — most likely USVFS hooking `CreateProcess` and injecting into it. What is proven is
that spawning a shell from UE4SS Lua under MO2 access-violates, reproducibly. On a plain non-MO2
install the same build creates its tree without complaint.

The consequences compound:

* Every probe returns falsy → `if failed then` never fires → **no `mkdir` is ever attempted.**
  Confirmed: a full launch produced **zero** `Creating directory` lines.
* The loop still runs. With 20 DataTable handlers × 8 children = **160 `cmd.exe` spawns**, i.e.
  ~60 seconds of windows flashing across the screen, every launch, achieving nothing.
* When the tree really is absent, `FindOrCreateModDir()` returns `nil` and the error surfaces
  three frames later as `attempt to index a nil value (local 'modDir')` — which reads as a
  TFWWorkbench bug rather than an environment one.

### Why emptying the table is safe

`Settings.ModChildDirs` has exactly **one** consumer — `CreateModChildDirs()`. Collection does not
use it:

```lua
CreateModChildDirs(modDir)
for dirName, dir in pairs(modDir.DataTable or {}) do   -- the REAL, snapshotted directory tree
    DataCollections[dirName] = CollectData(dir)         -- never Settings.ModChildDirs
end
```

So with the tree already present, emptying the table removes 160 shell-outs and changes nothing
else. Under MO2 you lose nothing at all, because the mechanism could not create a directory here
in the first place.

### What must create the tree instead

[ForeverWinterMO2Support](https://github.com/dataterminals/ForeverWinterMO2Support) v0.2.0+
pre-creates it in MO2's **Overwrite** folder, which its `mappings()` maps wholesale onto
`Content\Paks\Mods\`. Overwrite is the only viable route: `mappings()` maps *files*, and an empty
directory has none — so a dirs-only MO2 mod would map nothing at all, silently.

Timing matters and works out: MO2 calls `mappings()` **before** it starts the game process, so the
directories exist on disk before TFWWorkbench snapshots the tree. That matters because
TFWWorkbench snapshots *before* creating its own children — so even a tree it built successfully
on first launch would not be read until the **second**. Pre-creation is what makes the first
launch work.

```
<instance>\overwrite\
└─ TFWWorkbench\
   └─ DataTable\            ← SINGULAR. Upstream's README says "DataTables"; the code disagrees.
      ├─ Item\  ItemValue\  CraftingRecipe\  CraftingGroup\
      ├─ VendorData\  WeaponsDetailsData\  WeaponPartStatsData\
      └─ Dumps\             ← output dir, nested INSIDE DataTable\
```

That list is not arbitrary — it is `Settings.ModChildDirs` itself, which is why this patcher
records it in [`hashes.json`](../hashes.json) per release. **If a future release changes that list,
the plugin's pre-created tree must change with it.** That is the contract, and it is why the script
refuses to patch an unrecognised build without `-Force`.

## Verified working

`UE4SS v3.0.1-894-g2172883` + `TFWWorkbench 0.2.1` + Signature Bypass + content paks, under MO2 with
Root Builder enabled, 2026-07-16:

```
Mod 'TFWWorkbench' has enabled.txt, starting mod.
[TFWWorkbench] Registered Lua functions for mod
[TFWWorkbench:main:CollectData] Collecting data from ...\Content\Paks\Mods\TFWWorkbench\DataTable\CraftingRecipe
[TFWWorkbench:main:CollectData] Add CraftingRecipe - Name: 50PST_Ammo2  File: 005_HeavyRifleRebalance_Recipe.json
```

All 7 collect folders scanned, 34 rows added, zero errors. The 34 matched exactly the 34
`"Action": "Add"` entries counted statically in the source JSON beforehand.

> **Pin UE4SS.** TFWWorkbench's `main.dll` will not load against current RE-UE4SS: build `-929`
> (2026-01-30) narrowed `UStruct::GetMinAlignment` from `int32&` to `int16&`, and anything from
> there on fails with `0x7F ERROR_PROC_NOT_FOUND` — after which every dependent mod **silently
> does nothing**. See
> [tfworkbench-compat-research](https://github.com/dataterminals/tfworkbench-compat-research).

## Not upstream

Fix #2 is an **MO2-specific adaptation**, not a bug report. Upstream is right to create its own
directories on a normal install; it simply cannot here. The `os.execute`-per-child pattern *is*
worth raising upstream on its own merits — it is slow everywhere, not just under MO2 — but this
repo deliberately does not fork TFWWorkbench to fix that.
