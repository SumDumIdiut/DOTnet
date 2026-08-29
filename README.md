# DOTnet

Cosmetic multiplayer for *IGTAP: An Incremental Game That's Also a Platformer* (the Steam Demo). Patches `Assembly-CSharp.dll` directly — no BepInEx, no mod loader. Other players show up as ghosts synced over a small relay server: position, facing, animation, name, and colour. No shared game state, no physics.

Clicking Connect with the Direct Connect fields untouched reaches a public relay at `wss://codecade.co.za/dotnet` — install and play, no server setup needed. That address is never shown on screen though: the fields just read "Server IP" / "Port" until you type something, so a screenshot or stream of the panel doesn't leak it. Type a real host/port to use a different relay instead; see [Server](#server).

## Layout

- `mod/` — the mod itself. Eight standalone `.cs` files, no dependency on any other new script.
- `patches/playtest/`, `patches/demo/` — documentation of the one small change needed in `pauseMenuScript.cs` (a `pauseMenuScript.patch` diff, plus the `Assembly-CSharp.csproj` used when building by hand) for both Steam builds the mod has been built against. The shipped installer only targets the Demo; the Playtest patch is kept here for reference/manual builds.
- `server/server.js` — the relay. WebSocket, JSON messages, no game-state authority.
- `installer/` — `build-and-install.ps1` (the real installer logic: decompile → patch → build → deploy) and `setup.iss` (the Inno Setup GUI wrapper around it).

## Installing

Run the installer (`.exe`, from a release, or built yourself per below). No admin rights needed — it installs per-user and only ever touches your Steam Demo install and its own folder, both of which you already own. It decompiles the Demo's own `Assembly-CSharp.dll`, applies the mod, rebuilds, and deploys — keeping a backup of the true original so uninstalling restores it exactly.

It does a real build, so it needs a .NET SDK. If one isn't already on your system, it asks before downloading a portable copy (about 200 MB, cached for next time) — nothing happens without you saying yes. Progress shows in the installer's own window, not a separate console.

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

The client's Direct Connect fields take any host/port — port `443` means "connect via `wss://<host>/dotnet`" (for a relay routed through a reverse proxy the way this project's own instance is, see below); anything else means a plain `ws://host:port` straight to whatever's running there. Run `server.js` somewhere reachable (a VPS, or your own machine with the port forwarded) and share that address with whoever you want to play with. Only the relay needs to accept inbound connections - players never need to open a port on their own end.

## How it works

`MpNetworkManager` is a persistent connection/lobby manager hooked in through one small patch to `pauseMenuScript.Awake()`. `MpMenuBuilder` clones the game's own menu panels to build a "Multiplayer" entry that looks native. Other players are rendered by `MpGhostManager` as cosmetic copies of the local player's sprite — no collider, no rigidbody — interpolated toward whatever the relay last reported. `MpNetClient` wraps `ClientWebSocket` for the actual connection.
