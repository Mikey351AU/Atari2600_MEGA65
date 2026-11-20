Atari 2600 for MEGA65
=====================

A port of the MiSTer Atari 2600 core
([Atari2600_MiSTer](https://github.com/MiSTer-devel/Atari2600_MiSTer): A2601 by Retromaster, MiSTer
port by Sorgelig and others) to the MEGA65, built on the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) framework (by sy2002 and MJoergen).
The original framework README is in `M2M-README.md`.

Status: **V0.1. Builds for the MEGA65 R6 and R3/R3A with Vivado 2022.2 (timing met).**

**Works on a MEGA65 R6** (HDMI): the core starts, the options menu opens, cartridges load from
the SD card and games play. The picture stays visible while the menu is open (the game keeps
running behind it).

Fixed after hardware tests:
* "Heap corruption: Hint: MENU_HEAP_SIZE" when Help was pressed: `MENU_HEAP_SIZE` in
  `CORE/m2m-rom/m2m-rom.asm` is now 2048.
* Picture broke up / game graphics vanished while the menu was open: the core no longer pauses
  when the menu opens (`OPTM_PAUSE = false`, like MiSTer). Halting the CPU stops the VSYNC that
  2600 games generate in software.
* Picture shifted sideways and wrapped around with "Original VBlank" (Miner 2049er): the game
  sets VSYNC in the middle of a line and never blanks between frames, so the HDMI scaler started
  each frame mid-line. VSYNC now only changes at line starts and the VSYNC lines are always
  blanked (`main.vhd`). Confirmed on the R6.

The boot screen (black Atari logo on brick red) is what MiSTer's boot ROM draws, not a colour error.
Automatic bank switching detection ("Cart type: Auto (detect)") confirmed on the R6 with plain
`.bin` files: Frogger II, Gyruss, Montezuma's Revenge, Popeye, Super Cobra, Tutankham (E0),
Decathlon, Robot Tank (FE), Polaris, River Patrol (3F), BurgerTime, Masters of the Universe (E7)
and Pitfall II (DPC) load and play without setting the type by hand.
Miner 2049er (Tigervision, 3F, 8K: detected correctly) also works, but draws its picture lower
than most games: with the default regenerated VBlank (MiSTer's fixed window, frame line 34 to
VSYNC-25) the bottom of the screen is cut off, the same as on MiSTer. With "Original VBlank"
(menu: Video and audio) the whole screen is shown correctly (confirmed on the R6).

Not specifically confirmed yet: UA and CV detection, paddles, Superchip auto-detection, PAL
colours, VGA output. R3/R3A: `release/a2600_r3.cor` builds (timing met) but has not been tested on
an R3 yet. R4/R5 have not been built.

Project layout
--------------

| Path                          | What it is                                                                  |
|-------------------------------|-----------------------------------------------------------------------------|
| `CORE/Atari2600_MiSTer/`      | The MiSTer core's `rtl/` (see changes below), `Atari2600.sv`, readme        |
| `CORE/vhdl/main.vhd`          | Atari wrapper: controls, paddles, video sampling, VBlank regeneration, audio |
| `CORE/vhdl/cart.vhd`          | Cartridge device: 64 KB RAM, M2M ROM loader protocol, Superchip detection   |
| `CORE/vhdl/mega65.vhd`        | Clocks, menu settings, cartridge type, video/audio settings                 |
| `CORE/vhdl/clk.vhd`           | 57.27 MHz main clock and the 3.579545 MHz Atari clock (gated with a BUFGCE) |
| `CORE/vhdl/rom_boot.hex`      | MiSTer's boot ROM (`rtl/rom.mif`), shown before a cartridge is loaded       |
| `CORE/vhdl/keyboard.vhd`      | MEGA65 key mapping                                                          |
| `CORE/vhdl/globals.vhd`       | Clock speed, OSM size, cartridge device                                     |
| `CORE/vhdl/config.vhd`        | Welcome screen, help, options menu                                          |
| `build/`                      | Build scripts (Vivado for Windows + WSL), `bit2core` from mega65-tools      |

Changes to the MiSTer sources:
* `label: work.x` instantiations changed to `label: entity work.x` (28 places; Quartus accepts the
  short form, Vivado does not).
* `rtl/TIA/TIA.vhd`: the unused entity `audio` renamed to `tia_audio` (name clash with the M2M
  framework's `audio` entity).
* **Data bus without tristates.** The original models the console's shared data bus with an
  `inout` port and `'Z'` drivers in the CPU (`A6507`), RIOT (`A6532`), TIA and the cartridge logic
  (`A2601top`). Quartus turns that into multiplexers; Vivado rejects it ("multiple driver nets").
  Each of these now has `d_i` (the resolved bus) and `d_o`/`d_oe` (what it drives); `A2601Core`
  combines CPU, TIA and RIOT, and `A2601top` resolves the final bus with the cartridge. If nobody
  drives the bus, it keeps its last value (like the real floating bus). The RIOT's `pa`/`pb` ports
  are plain inputs: the original only ever drove `'Z'` on them.

How the port works
------------------

* **Clocks:** the Atari runs on the NTSC colour clock, 3.579545 MHz, like MiSTer's `clk_cpu`.
  A 7-series MMCM cannot output less than 4.69 MHz, so the MMCM makes 57.272727 MHz
  (100 MHz / 5 x 31.5 = 630 MHz VCO, / 11), which is exactly 16x the colour clock, and a BUFGCE
  passes one of every 16 pulses. The two clocks share their source and buffer type, so they are
  aligned and Vivado times all paths between them. The TIA colour table (`vid_clk`) and the
  framework run on 57.27 MHz.
* **Cartridges:** loaded with the M2M file browser into a 64 KB RAM in `cart.vhd`, which
  implements the M2M "manually loadable ROM" protocol (CSR in 4K window `0xFFFF`). The Atari is
  held in reset while loading. Game archives use `.bin` for everything, so instead of MiSTer's file
  extensions the bank switching scheme is **detected from the cartridge contents** ("Cart type:
  Auto (detect)", like Stella's CartDetector): after loading, `cart.vhd` scans the ROM (one byte
  per QNICE clock) for typical code: E0 (8K, accesses to `$1FE0`/`$FFE9`/...), 3F (8K, `STA $3F`
  at least twice), UA (8K, `$0240`/`$021F`), FE (8K, Activision JSR sequences), E7 (16K,
  `$1FE5`/`$1FE7`/`$FFE2`/...), CV (2K/4K, `STA $F3FF,X`/`STA $F400,Y`), DPC (Pitfall II, by its
  size 10240–10495 bytes). Otherwise the scheme is chosen by size, like MiSTer. The size limits
  per scheme are those of the MiSTer core's bank switching. Superchip RAM is detected the way
  Stella does it (identical bytes in `0x000-0x07F` and `0x080-0x0FF` of each 4K bank); a Superchip
  cart always uses the size-based scheme (F8/F6/F4). The menu can force a scheme and Superchip
  on/off. The scanner is checked with a cycle model: `sim/CartScanSim.cs` (25 test ROMs).
* **Video:** the TIA output (160 pixels per line) is sampled at 4x the colour clock (640 pixels
  per line). VBlank is regenerated like MiSTer's default (lines 34 to VSYNC-25), or taken from
  the game ("Original VBlank", plus blanking during VSYNC). VSYNC is passed on only at line
  starts. OSM: 640 x 384 = 40 x 24 characters.
* **Audio:** two 4-bit TIA channels, mixed to mono (MiSTer's default) or stereo.

Controls
--------

| MEGA65                         | Atari 2600                              |
|--------------------------------|-----------------------------------------|
| Joystick ports 1 and 2         | Joysticks (or paddles, see menu)        |
| Cursor keys + Space            | Joystick 1                              |
| F1                             | Game Select switch                      |
| F3                             | Game Reset switch                       |
| Help                           | Options menu, load cartridge            |

Difficulty switches, colour/B&W, cartridge type, Superchip, paddles, NTSC/PAL colours and the
video options are in the menu. Paddles: MEGA65 paddle inputs, buttons on the joystick left/right
lines (like Atari/C64 paddles). Press each paddle button once to activate it (as on MiSTer).

Installing
----------

1. Create the folder `/atari2600` on the SD card for your cartridges (`.a26`/`.bin`, up to 64 KB).
2. Copy `sdcard/atari2600/a26cfg` there too, so the menu settings are saved.
3. Flash `release/a2600_r6.cor` (MEGA65 R6) or `release/a2600_r3.cor` (R3/R3A, not yet tested on
   hardware) with the MEGA65 core menu.

Building
--------

Vivado 2022.2 for Windows plus WSL (Ubuntu). Clone with the QNICE submodule:

```bash
git clone --recursive <this repository's URL>
```

One-time setup in `build\`:

```bash
wsl bash ./setup_wsl.sh
```

Then build for your board (writes `release\a2600_r6.bit` and `release\a2600_r6.cor`):

```bash
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Board R6
```

Known limitations / TODO
------------------------

* The bank switching detection uses signatures; a game that uses none of them (or an unusual
  dump) falls back to the size-based scheme and needs "Cart type" set by hand. Schemes not
  detected at all: F0 (Dynacom), FA is by size (12K), 32-in-1 is the 64K default.
* No MiSTer-style "adaptive" aspect ratio; HDMI uses the M2M 4:3 window.
* The default "regenerated VBlank" window (from MiSTer) cuts off games that draw lower than usual
  (Miner 2049er); "Original VBlank" shows them completely. The setting is saved for the core, not
  per game.

License
-------

GPL v3 (MiSTer2MEGA65, A2601), the MiSTer core sources keep their original licenses.
