# DOTnet

Cosmetic multiplayer for *IGTAP: An Incremental Game That's Also a Platformer* (Playtest and Demo Steam builds). Patches `Assembly-CSharp.dll` directly — no BepInEx, no mod loader. Other players show up as ghosts synced over a small relay server: position, facing, animation, name, and colour. No shared game state, no physics.

Defaults to a public relay at `wss://codecade.co.za/dotnet` — install and play, no server setup needed. You can point Direct Connect at any other relay instead; see [Server](#server).

## Layout

- `mod/` — the mod itself. Eight standalone `.cs` files, no dependency on any other new script.
- `patches/playtest/`, `patches/demo/` — documentation of the one small change needed in `pauseMenuScript.cs` per build (a `pauseMenuScript.patch` diff, plus the `Assembly-CSharp.csproj` used when building by hand). The installer applies the equivalent edit itself; these are for readers, not required at install time.
- `server/server.js` — the relay. WebSocket, JSON messages, no game-state authority.
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
cd server
npm install
node server.js
```

Defaults to port 7777 (`PORT` to change it) and speaks plain `ws://` — no TLS of its own. Rate limits, connection/lobby caps, payload size limits, idle timeouts, and per-IP connection limits are all built in; see the top of `server.js` to tune them.

The client's Direct Connect fields take any host/port — port `443` specifically means "the public relay behind codecade.co.za" (`wss://<host>/dotnet`); anything else means a plain `ws://host:port` to whatever's actually running there. So you're never stuck using the default: run your own `server.js` somewhere reachable (a VPS, or your own machine with the port forwarded) and have people Direct Connect to that address/port instead. Only the relay needs to accept inbound connections - players never need to open a port on their own end, and nobody else's server is involved unless you choose the default.

## How it works

`MpNetworkManager` is a persistent connection/lobby manager hooked in through one small patch to `pauseMenuScript.Awake()`. `MpMenuBuilder` clones the game's own menu panels to build a "Multiplayer" entry that looks native. Other players are rendered by `MpGhostManager` as cosmetic copies of the local player's sprite — no collider, no rigidbody — interpolated toward whatever the relay last reported. `MpNetClient` wraps `ClientWebSocket` for the actual connection.
