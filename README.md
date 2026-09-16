# macVC

**GTA Vice City, native on Apple Silicon.** A build that renders through
**Metal**, runs sharp at full **Retina** resolution, and turns on macOS **Game
Mode** automatically. One command turns your own copy of the original game —
Steam, retail disc, or files from an old PC — into a ready-to-play
`Grand Theft Auto Vice City.app`. No administrator password needed.

This repository hosts the **download only** — there is no source code here.

> ⚠️ **This needs the original Vice City, not the Definitive Edition.** The
> Definitive Edition is a different, rebuilt game and will not work.

## Install

**You need:** an Apple Silicon Mac (M1 or newer) on macOS 15.7.9 or later, and
your own copy of the **original GTA Vice City** — the classic 2002/2003 PC
release, *not* the Definitive Edition
([Steam](https://store.steampowered.com/app/12110/) works out of the box — you
never have to launch it).

1. Open **Terminal** (`Cmd+Space`, type `Terminal`, press Enter), paste this
   line and press Enter:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/gtamac/macVC/main/quick-install.sh | bash
   ```

   It finds your game files automatically (a Steam copy, or an already-installed
   app from an earlier run — including the previous macVC.app or reVC.app) and
   puts **Grand Theft Auto Vice City.app** in your Downloads folder — about a
   minute, the app is ~1.6 GB with the game inside.

2. When Finder opens, **drag Grand Theft Auto Vice City into Applications** —
   or just double-click it to play right away.

**Using a non-Steam copy?** Add the path to the end of the command — a game
folder (the one with `models`, `data`, `audio`, …) or a Vice City `.app` that
contains the files (including Wineskin/Wine wrappers) both work — again, from
the original game, not the Definitive Edition:

```sh
curl -fsSL https://raw.githubusercontent.com/gtamac/macVC/main/quick-install.sh | bash -s -- ~/Downloads/"Grand Theft Auto - Vice City.app"
```

**Upgrading?** Run the same one-liner again — it reuses the game files from your
installed app.

Prefer a classic disk image? Add `--dmg` to get a drag-to-Applications
`Grand Theft Auto Vice City.dmg` instead: `... | bash -s -- --dmg`.

**Coming from reVC?** This is the same project under a new name. The installer
picks the game files straight out of your existing `reVC.app`, and the first
launch copies your settings and save games over from
`~/Library/Application Support/reVC`. Nothing is moved or deleted — the old
folder and the old app stay exactly where they are, so you can go back at any
time. The two save folders are independent from then on.

## Direct downloads

| File | What it is |
|---|---|
| [`macVC-macos-arm64.tar.gz`](https://raw.githubusercontent.com/gtamac/macVC/main/macVC-macos-arm64.tar.gz) | the app with no game assets, for building your own bundle |
| [`macVC-macos-arm64.zip`](https://raw.githubusercontent.com/gtamac/macVC/main/macVC-macos-arm64.zip) | the same, zipped |
| [`quick-install.sh`](https://raw.githubusercontent.com/gtamac/macVC/main/quick-install.sh) | the installer the one-liner runs |
| [`signtool-arm64.tar.gz`](https://raw.githubusercontent.com/gtamac/macVC/main/signtool-arm64.tar.gz) | the bundled ad-hoc signer, so installing needs no Xcode |

## Legal

macVC requires the files from your own legally purchased copy of the original
Grand Theft Auto: Vice City. No game assets are distributed here.

## What's changed in this port

Everything below is on top of upstream reVC (the `miami` branch), which itself is the reversed Vice City source. macVC is that port, under its own name. The goal is a faithful native Mac experience — original gameplay and look, modern rendering underneath.

### The original name and icon
- **The installed app is now `Grand Theft Auto Vice City.app`, with the classic Vice City icon** — the name on disk, in the menu bar, and in the Dock all match the original game. macVC stays the name of the project and the download repository. Upgrading with the one-liner carries everything over, and picks up the game files from an existing install under any of its past names (macVC.app, reVC.app).

### Rendering: OpenGL → Metal
- librw's GL3 renderer now runs through **ANGLE (OpenGL ES on Metal)** on macOS, so every draw call ends up on Metal — no OpenGL deprecation warnings, no Rosetta, native arm64 all the way down. The ANGLE dylibs ship inside the app (and as a separate prebuilt archive below).
- **HDR rendering** (new in-game Display option): the swap chain uses a float16 EDR surface in the Display P3 colorspace via a small ANGLE patch, so highlights like sun glare, headlights, and neon get real extended-range brightness on XDR/HDR displays.
- **MetalFX upscaling** (new in-game Graphics option, on by default at Balanced): the game renders at a lower internal resolution and Apple's **MetalFX temporal scaler** reconstructs it to your display resolution at present time — big GPU savings at Retina resolutions, with jittered, motion-compensated multi-frame reconstruction that stays close to native sharpness from a fraction of the pixels. Presets right under the Screen Resolution selector, best to off: **Best Quality** (100% — pure temporal anti-aliasing, no upscale), **Quality** (85%), **Balanced** (75%, the default), **Performance** (67%), **Max Performance** (50%), **Ultra Performance** (33% — needs a GPU with 3x scaling support, else falls back to 50%), and off for native rendering. Every preset uses the temporal scaler now (the spatial scaler is retired); it does its own anti-aliasing and switches MSAA off automatically, and MSAA is a regular menu option in the Advanced tab otherwise. Like HDR and Screen Resolution, the preset is applied from the main menu before loading a save — greyed out in the in-game pause menu, because applying it rebuilds the renderer.

- **MetalFX frame generation** (new **FPS** Graphics option): the engine stays locked at its physics-correct 30fps while Apple's frame interpolator (macOS 26) synthesizes an extra frame between every two rendered ones, so the display shows a smooth ~60fps. The single **FPS** row replaces the old frame-limiter toggle — **Interpolate (60)**, plain **30** (the default; interpolation is opt-in because it can still show artifacts), or **No Limit** (uncapped, breaks physics). Interpolation switches MSAA off while active and is applied from the main menu.

- **Per-object motion vectors**: the temporal scaler and the frame interpolator no longer see only camera motion. A velocity pass re-renders the moving objects — vehicles, pedestrians, props — into a motion-vector buffer shared with MetalFX, so dynamic motion is reconstructed and interpolated correctly, not smeared. Each vehicle is treated as one rigid body (so wheels and doors don't tear off), and the HUD, text and menus render into a separate layer that's composited *after* interpolation so they never warp. Following the approach documented by Apple and NVIDIA, fast rotation (spinning wheels) intentionally uses translation-only motion to avoid the artifacts true spin vectors cause.

- **Metal ray tracing** (new in-game Graphics option, off by default): a ray-tracing pass on the Metal GPU traces real shadows through the scene, down to the weapon in a ped's hands — crisp sun shadows with volumetric light rays by day; after dark, street lamps cast shadows and every car headlight throws a halogen low beam onto the road, starting softly just ahead of the bumper, each lamp with its own ray-traced shadow. Headlights follow the game's own switching logic — cars light up one by one through dusk, and a midday storm fills the street with lit beams — and their tint matches the car: near-white halogens on the 80s exotics, warm ~3000K beams on ordinary traffic, dim yellow sealed beams on the old clunkers. Explosions and muzzle flashes light up their surroundings and throw hard radial shadows day and night: the flash scales with the weapon, from a pistol's pop to a minigun's blaze, and no two shots flare alike. Rockets in flight trail a flickering flame that lights the street as they pass, and helicopter searchlights are now true volumetric cones — a godray beam hanging in the air that casts a crisp pool on the ground, and anything caught in it carves dark shafts through the beam. The map's painted-on shadows — the fixed dark patches baked into the roads under trees, petrol pumps and the like — disappear while ray tracing is on, replaced by the real traced shadows, and come back the moment it's off. And vegetation properly casts its own: palms, bushes and hedges throw soft translucent shadows that let part of the light through, instead of the solid silhouettes or missing shadows of before. Turn it on with the **METAL RAY TRACING** switch in the Graphics menu, right below the MetalFX preset — it's experimental and starts off.

### Graphics quality
- Textures are now **mipmapped with trilinear and anisotropic filtering** (plus fixes to librw's mipmap generation), which kills the shimmering on distant roads and buildings.
- **Extended draw distance** for the map while keeping the **stock fog** look, and vehicles now fade in smoothly at every detail level instead of popping.
- **Better defaults**: PS2 alpha test (cleaner transparency edges) now starts on — and stays on after "restore defaults" — while the Neo world lightmaps option starts off.

### macOS integration
- The game ships as a **self-contained app bundle** — installed as `Grand Theft Auto Vice City.app` — with binary, dylibs, and macVC's game data inside, ad-hoc signed — so macOS treats it as a real game and enables **Game Mode** automatically.
- The game always **starts windowed and then enters native macOS fullscreen**, so Spaces, Mission Control, and Cmd+Tab behave like they should.
- A one-line **installer script** finds your game files (an existing install — Grand Theft Auto Vice City.app, macVC.app, or reVC.app — or a Steam install, auto-detected, or any folder or Vice City .app you point it at), bakes them into the app, and can also produce a drag-to-install DMG — so upgrades re-run the same one-liner without needing the original game around, and needs nothing installed beyond macOS itself — no Homebrew, no Xcode. The installer got a proper terminal face too: numbered steps and live progress bars for the download and the game-data bake.
- **Update notification**: the installed app checks the download repository on launch and, when a newer build is out, offers **Install** (quits the game and runs the one-line updater in Terminal, reusing your existing game files) or **Ignore**. The check is silent when you're offline or already up to date.
- **Advanced graphics tab**: the Graphics menu keeps the essentials (resolution, HDR, MetalFX, widescreen, frame limiter) and moves the rest — MSAA, windowed/fullscreen, VSync, island loading, PS2 alpha test, colour filter, motion blur, and the Neo pipeline options — to a new Advanced sub-page, which also adds a **Metal performance HUD** toggle (the same overlay as the `-metalhud` launch flag).

### Fixes
- **Rare crash with MetalFX upscaling or frame generation on**: an object removed at exactly the wrong moment mid-frame could take down the motion-vector pass. Those objects are now dropped from the pass safely.
- **Mouse input randomly not being detected** — the infamous Vice City mouse bug — is fixed in the GLFW backend.
- **HUD and camera misaligned on HiDPI/Retina displays** right after launch (cropped, off-center view; radar and mission text pushed toward the screen edges) — fixed by seeding the first camera resize from the real framebuffer size. Thanks to [@KreamBrulee](https://github.com/KreamBrulee) for the report and fix.
- **First launch now defaults to your display's actual pixel resolution** (e.g. 3840x2160 on a 4K screen) instead of the scaled macOS desktop size.
- **Multi-display setups: the game now opens on the screen you launch it from** instead of always on the primary display.
- **The mouse cursor can no longer leave the game in fullscreen**: menus keep the cursor captured (like exclusive fullscreen always did), so it can't wander onto another display, reveal the Dock, or click you out of the game — and it now reaches the whole screen with MetalFX on instead of stopping at two thirds.
- **The rocket launcher's sight no longer shows as a solid black square** with MetalFX upscaling or frame generation on — additive HUD draws now composite correctly in the separate UI layer.
- **Applying graphics settings no longer crashes or leaves an oversized window**: switching resolution, HDR, or the MetalFX preset re-creates the renderer, and the game now reliably drops out of and back into native fullscreen around that instead of crashing or ending up larger than the screen.
