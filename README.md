# DOTnet

Cosmetic multiplayer for *IGTAP: An Incremental Game That's Also a Platformer* (Playtest and Demo Steam builds). Patches `Assembly-CSharp.dll` directly — no BepInEx, no mod loader. Other players show up as ghosts synced over a small relay server: position, facing, animation, name, and colour. No shared game state, no physics.

## Layout

- `mod/` — the mod itself. Eight standalone `.cs` files, no dependency on any other new script.
- `patches/playtest/`, `patches/demo/` — documentation of the one small change needed in `pauseMenuScript.cs` per build (a `pauseMenuScript.patch` diff, plus the `Assembly-CSharp.csproj` used when building by hand). The installer applies the equivalent edit itself; these are for readers, not required at install time.
- `server/server.js` — the relay. Plain TCP, newline-delimited JSON, no game-state authority.
- `installer/` — `build-and-install.ps1` (the real installer logic: decompile → patch → build → deploy) and `setup.iss` (the Inno Setup wrapper around it).

## Installing

Run the installer (`.exe`, from a release, or built yourself per below). It detects whichever of Playtest/Demo you have installed, decompiles each one's own `Assembly-CSharp.dll`, applies the mod, rebuilds, and deploys — keeping a backup of the true original so uninstalling restores it exactly.

Requires the .NET SDK on the machine running the installer (it does a real build). Get it from [dotnet.microsoft.com/download](https://dotnet.microsoft.com/download) if `dotnet --list-sdks` comes back empty.

## Building the installer yourself

1. Stage `ilspycmd` (the decompiler) into `installer/tools/ilspycmd/` — e.g. `dotnet tool install --tool-path installer/tools/ilspycmd ilspycmd`, then copy the contents of its `tools/net*/any/` folder up to `installer/tools/ilspycmd/` directly (this folder is gitignored; it's a build-time dependency, not part of the repo).
2. Compile `installer/setup.iss` with Inno Setup 6 (`ISCC.exe installer/setup.iss`).
3. The result lands in `installer/output/`.

You can also just run `installer/build-and-install.ps1` directly against an already-installed copy of the game, without building the `.exe` wrapper at all.

## Server

```
node server/server.js
```

Defaults to port 7777. Set `PORT` to change it.

There's no built-in/hardcoded server — the client's Direct Connect fields take any host and port. The relay only needs to be running and reachable at the moment people want to play (it doesn't relay anything when nobody's connected, so there's nothing to leave running otherwise). Two people can host and connect entirely on their own, with nobody else's server involved: one of them runs `server.js` somewhere reachable from the internet (a cheap VPS, or their own machine with the port forwarded), and both point Direct Connect at that address. Only the relay itself needs to accept inbound connections — the players don't need to open any ports on their own end.

## How it works

`MpNetworkManager` is a persistent connection/lobby manager hooked in through one small patch to `pauseMenuScript.Awake()`. `MpMenuBuilder` clones the game's own menu panels to build a "Multiplayer" entry that looks native. Other players are rendered by `MpGhostManager` as cosmetic copies of the local player's sprite — no collider, no rigidbody — interpolated toward whatever the relay last reported.
