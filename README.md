# IGTAP Multiplayer Mod

Cosmetic multiplayer for *IGTAP: An Incremental Game That's Also a Platformer* (Playtest and Demo Steam builds). Patches `Assembly-CSharp.dll` directly — no BepInEx, no mod loader. Other players show up as ghosts synced over a small relay server: position, facing, animation, name, and colour. No shared game state, no physics.

This repo does **not** contain any of the game's own code or compiled binaries. It has the mod's own source (`mod/`), the small unified diffs needed against the two base-game files that get touched (`patches/`), the relay server (`server/`), and the installer (`installer/`).

## Layout

- `mod/` — the mod itself. Eight standalone `.cs` files, no dependency on any other new script.
- `patches/playtest/`, `patches/demo/` — a one-file diff (`pauseMenuScript.patch`) plus the `Assembly-CSharp.csproj` used to build against each install, since the two Steam builds' `pauseMenuScript.cs` differ slightly in structure.
- `server/server.js` — the relay. Plain TCP, newline-delimited JSON, no game-state authority.
- `installer/install-mod.ps1` — builds and deploys the patched DLL into a local Steam install; also handles restoring the original.

## Building from source

You need your own decompile of the game (ilspycmd works well) — this repo doesn't ship one.

1. Decompile `Assembly-CSharp.dll` from your own Playtest and/or Demo install into two project folders.
2. Apply `patches/<target>/pauseMenuScript.patch` to that file in your decompile.
3. Copy `patches/<target>/Assembly-CSharp.csproj` in (adjust the `HintPath` entries to your own install location).
4. Drop the eight files from `mod/` into the same folder.
5. `dotnet build -c Release`.
6. Run `installer/install-mod.ps1`, or copy the built DLL over the game's `Assembly-CSharp.dll` yourself (back up the original first).

## Server

```
node server/server.js
```

Defaults to port 7777. Set `PORT` to change it.

## How it works

`MpNetworkManager` is a persistent connection/lobby manager hooked in through one small patch to `pauseMenuScript.Awake()`. `MpMenuBuilder` clones the game's own menu panels to build a "Multiplayer" entry that looks native. Other players are rendered by `MpGhostManager` as cosmetic copies of the local player's sprite — no collider, no rigidbody — interpolated toward whatever the relay last reported.
