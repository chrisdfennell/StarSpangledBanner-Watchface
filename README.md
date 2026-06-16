# Star Spangled Banner Watch Face

![Star Spangled Banner — 4th of July watch face](assets/hero_image.png)

A premium, **4th of July / Independence Day** themed **digital watch face** for **Garmin** watches, written in Monkey C for Connect IQ. Fireworks rise from an open field and burst overhead beneath a waving American flag. It runs on every Connect IQ 4.0+ round watch (see [Hardware / scaling](#hardware--scaling)).

<p align="center">
  <img src="assets/screen_active.png" alt="Star Spangled Banner active render" width="320">
</p>

Star Spangled Banner brings the celebration to your wrist:

- **Fireworks Show**: Rockets streak up from the field and burst into expanding, drooping, fading showers of color overhead — several shells animate at once through the evening and night. Everything is computed from the clock, so the show is deterministic (no battery-draining state) yet always changing.
- **Living Summer Sky Backdrop**: A smooth color gradient shifting through warm dawn, bright midday blue, a golden hour, a fiery sunset, and a deep starry night based on the current hour.
- **Open Field & Distant Tree Line**: An open, rolling green field is ringed along the horizon by a silhouetted forest edge (rounded canopy with a few conifer spires) — the "standing in a wide-open field, trees all around" look. A foreground grass strip and blades sit at the very bottom.
- **Waving American Flag**: The Stars-and-Stripes flies on a pole planted in the field — 13 red/white stripes, a blue canton of white star-dots, billowing on a travelling wave, topped with a gold finial.
- **Arcing Sun & Moon**: A warm summer sun (with faint rotating rays and a warm halo) and a silver moon rise and set along a circular path, driven by the **real sunrise/sunset** computed from the watch's location and today's date (falls back to a fixed summer schedule when no location fix is available). The sky, day/night, and fireworks all follow the same real sun times.
- **Fireflies at Night**: Soft yellow-green glints drift and blink over the field once the sun goes down.
- **America's 250th** *(one toggle, on by default)*: A golden **"1776 ★ 2026"** banner marks the Semiquincentennial — 250 years of American independence, landing on July 4, 2026.
- **Grand Finale Mode** *(one toggle, off by default)*: Crank up the show. Denser, faster fireworks all day and night, patriotic red-white-blue **bunting** draped across the top, a twinkling flag finial, and a **biplane** that sweeps across the sky on a timed flyover trailing a star-spangled pennant. Switch it off for the everyday scene.
- **Field Critters** *(one toggle, on by default)*: Occasional little visitors cross the scene — at most one at a time, every ~40s, computed purely from the clock. By day a **bald eagle** soars the sky, a **deer** walks the field, a **cottontail** bounds past, and a **butterfly** flutters by. By night an **owl** glides over, a **red fox** trots and pounces, a **raccoon** trundles past, and a **bat** darts across. Sky visitors draw in the sky; ground visitors walk on the field. Critters never render in always-on, so they cost nothing on the burn-in budget.
- **Spinning Star Seconds**: A five-pointed star second indicator orbits the outer perimeter (drawn on top of everything, and only while the watch is active).
- **Centered Digital Time**: Large, clean, rounded clock numerals centered with high-contrast black outlining.
- **Centered Date & Weather**: An elegant date line showing the calendar date and dynamic weather temperature (with automatic Celsius/Fahrenheit unit conversion).
- **Configurable Complications**: The bottom-left and bottom-right complications are each chosen in the app settings, and the watch draws a matching icon:
  - **❤ Heart Rate** (red heart) — live BPM, sampled at most once every ~10s to spare the battery.
  - **⚡ Body Battery** (silver bolt) — Garmin's 0–100 energy score.
  - **🔋 Device Battery** (patriot-blue battery with a live fill bar) — the watch's charge.
  - **👣 Steps** (boot) — today's step count.
  - **🔥 Calories** (ember flame) — today's calories.
  - **Off** — hide the complication.
  - Defaults: left = Heart Rate, right = Device Battery.
  - **Bottom-center**: A red-white-blue steps progress bar + steps numeric count, always shown.
- **High-Contrast Text Outlines**: All text elements (clock, date, and metrics) are drawn with a custom black outline to ensure legibility against any dynamic gradient or sky background.

## Hardware / scaling

Star Spangled Banner targets **every Connect IQ 4.0+ round watch that supports watch faces**. The full product list lives in [manifest.xml](manifest.xml); the families covered are:

- **Forerunner** — 165, 255 (incl. S/Music), 265 / 265S, 570, 955, **965**, **970**
- **fenix / epix / enduro** — fenix 7 (S/X, Pro), fenix 8 (AMOLED + Solar), fenix E, epix 2 / Pro (42/47/51mm), enduro 3
- **Venu / Vivoactive** — Venu 2 / 2S / 2 Plus, Venu 3 / 3S, Venu 4 (41/45mm), Vivoactive 5 / 6
- **Instinct** — Instinct 3 (AMOLED 45/50mm, Solar 45mm), Instinct E (40/45mm), Instinct Crossover (AMOLED)
- **Specialty** — Approach S50 / S70 (golf), Descent G2 / Mk3 (dive), D2 Air X10 / Mach 1 / Mach 2 (aviation), MARQ 2 / Aviator

Edge bike computers and handheld GPS units are excluded (not watches), and the **square/rectangular panels (Venu Sq 2, Venu X1) are excluded too** — the circular layout is designed for round screens.

### How it scales

Everything is laid out in percentages of `dc.getWidth()/getHeight()` and the screen center, so the same source renders across every panel. Because bitmap fonts don't scale, [tools/gen_fonts.py](tools/gen_fonts.py) bakes a correctly-sized font set for each distinct resolution and [monkey.jungle](monkey.jungle) maps every product to the right one:

| Resolution | Set                          | Example devices |
|------------|------------------------------|-----------------|
| 454×454    | `resources/` (base)          | Fenix 8 47/51mm, FR965/970, Venu 3, epix 2 Pro 51mm |
| 416×416    | `resources-round-416x416/`   | Fenix 8 43mm, FR265, epix 2, Venu 2 |
| 390×390    | `resources-round-390x390/`   | FR165, Venu 3S, Vivoactive 5/6, Instinct 3 AMOLED 45mm |
| 360×360    | `resources-round-360x360/`   | FR265S, Venu 2S |
| 280×280    | `resources-round-280x280/`   | Fenix 7X, Fenix 8 Solar 51mm, enduro 3 |
| 260×260    | `resources-round-260x260/`   | FR255/955, Fenix 7, Fenix 8 Solar 47mm |
| 240×240    | `resources-round-240x240/`   | Fenix 7S |
| 218×218    | `resources-round-218x218/`   | FR255S |
| 176×176    | `resources-round-176x176/`   | Instinct 3 Solar 45mm, Instinct E 45mm |
| 166×166    | `resources-round-166x166/`   | Instinct E 40mm |

Re-run `python tools/gen_fonts.py` after changing font sizes or adding a new resolution. Fonts scale by `min(width, height)` so they fit the shorter axis on rectangular panels.

## Always-on display

The face has two render paths sharing one `onUpdate()`:

- **Active mode** — full brightness, animations (fireworks, swaying flag, sun rotation, fireflies, drifting clouds, field critters), sky gradients, and text outlines.
- **Always-on / low-power** (`mIsSleep`) — burn-in-safe: dim grey time/date, thin outline representations of the battery metrics, steps progress outline, and **no visual fills or background animations**. All lit pixels are shifted a few pixels each minute (`requiresBurnInProtection`). `onPartialUpdate()` only repaints when the minute changes, and on AMOLED always-on it **clips to just the central time/date band** rather than re-rendering the whole screen — staying well inside the partial-update budget. (MIP panels, whose sleep frame is the full colour scene, keep the full redraw.)

### Performance & stability

Star Spangled Banner is tuned to keep animating smoothly on everything from a 166px Instinct to a 454px flagship without tripping Garmin's per-frame execution/power budget (the usual cause of a watch face "freezing"):

- **Adaptive render quality** — `onUpdate()` times its own frame and nudges a quality level (0–3) with hysteresis. Expensive detail (text-outline passes, sun rays, firework spark counts, firefly count) scales with it, so the scene keeps fully animating and only sheds detail on hardware that can't keep up — auto-fitting each device with no per-device guessing.
- **Cached per-frame syscalls** — device settings, clock, and activity info are read once per redraw and reused; sunrise/sunset retries are throttled while no fix is available.
- **No per-frame heap churn** — the star field, sky-gradient tables, and the field-hill polygon buffer are hoisted/reused; on AMOLED the sky gradient is rendered once into a `BufferedBitmap` and blitted, repainting in place only when the colors change. Fireworks draw with cheap circles and are fully deterministic from the clock (no particle arrays kept between frames).
- **Loop-safe math** — angle/hour normalizers use bounded modulo with a non-finite guard (no unbounded `while`), and `%`-based wraps use positive modulo.

## Data sources

- **Steps + goal:** `ActivityMonitor.getInfo()` (`steps`, `stepGoal`).
- **Calories:** `ActivityMonitor.getInfo().calories`.
- **Heart rate:** `Activity.getActivityInfo().currentHeartRate` (with an `ActivityMonitor.getHeartRateHistory` fallback), cached and refreshed at most once every ~10s.
- **Device battery:** `System.getSystemStats().battery`.
- **Body Battery:** `SensorHistory.getBodyBatteryHistory()`. Fails gracefully if the value is unavailable.
- **Weather:** `Weather.getCurrentConditions()` (uses Connect IQ weather APIs to display current temperature in Celsius or Fahrenheit depending on device settings).
- **Location & sun times:** last-known location from `Activity.getActivityInfo().currentLocation` (or the weather observation location — neither powers up GPS); sunrise/sunset are computed locally with a standard NOAA almanac formula and cached per day.

## Settings

Editable in Garmin Connect / the simulator's App Settings:

- **Show Date** — toggle the date and weather line.
- **Fireworks** — toggle the rising-and-bursting fireworks show.
- **America's 250th** — toggle the golden "1776 ★ 2026" Semiquincentennial banner.
- **Grand Finale** — denser/faster fireworks, patriotic bunting, a twinkling flag finial, and the biplane flyover.
- **Field Critters** — toggle the occasional crossing visitors (eagle, deer, rabbit, butterfly, owl, fox, raccoon, bat).
- **Step Goal Override** — steps for a full progress bar; `0` uses the watch's own step goal.
- **Bottom-Left Complication** — Off / Heart Rate / Body Battery / Device Battery / Steps / Calories.
- **Bottom-Right Complication** — same options (each shows an emoji in the phone picker and a matching icon on the watch).

## Build & run

Prerequisites: the **Connect IQ SDK** and a JDK. Paths live in `build_config.json` (auto-created on first run) — edit them to match your machine:

```json
{
  "JavaHome": "C:\\Program Files\\Android\\openjdk\\jdk-21.0.8",
  "SdkDir":   "C:\\Users\\<you>\\AppData\\Roaming\\Garmin\\ConnectIQ\\Sdks\\<sdk-version>"
}
```

### Build (default device = `fenix847mm`, 454×454)

```powershell
./build.ps1                     # build .prg
./build.ps1 -Device fenix843mm  # build the 416×416 variant
./build.ps1 -Export             # package a store-ready .iq
```

### Build + launch in the simulator

```powershell
./build.ps1 -Run                # or double-click run_simulator.bat
```

In the simulator you can exercise the design via the menus:
- **Settings → Battery** to move the device-battery complication.
- **Simulation → Body Battery** for the Body Battery percentage.
- **Simulation → Time / Sleep** (Always On) to preview the low-power render path.
- **Simulation → Set Time** to test different hour transitions (warm dawn, bright noon, fiery sunset, and the fireworks-lit night).

### Sideload to the watch

1. Build the `.prg` (or `.iq`).
2. Connect the watch by USB; it mounts as a drive.
3. Copy `bin/StarSpangledBanner.prg` to `GARMIN/APPS/` on the device.
4. Eject and select **Star Spangled Banner** from the watch face list.

For store distribution, upload the `.iq` from `./build.ps1 -Export`.

## Fonts & Typography

The face renders using custom rasterized bitmap fonts:

- **Time font**: *Arial Rounded MT Bold* (`exocet_time.fnt`/`.png`).
- **Date / Metrics font**: *Segoe UI Light* (`exocet_label.fnt`/`.png`).

The bitmap font pipeline is:

```
fonts-src/RoundedTime.ttf  ──┐
fonts-src/SegoeUILight.ttf ──┤  python tools/gen_fonts.py
                             └─▶  resources/fonts/exocet_*.fnt + .png
```

- `tools/gen_fonts.py` rasterizes the glyphs we use (digits, symbols like `:` and `%`, and standard letters) into alpha atlases so `dc.setColor()` tints them. Re-run it if you need to modify font sizes or support new characters.
- `resources/fonts/fonts.xml` declares `ExocetTime` / `ExocetValue` / `ExocetLabel`.
- `initFonts()` loads them, falling back to vector fonts then built-ins if missing.

## Promotional art

`tools/gen_promo.py` composes the store/README art (`hero_image.png`, `cover_image.png/.jpg`, and the `app_icon_*.png` star badge) from the watch's own night palette, dropping the real `assets/screen_active.png` render into a drawn watch body. Re-run `python tools/gen_promo.py` after updating the screenshot.

## Customizing

- **Colors / palettes**: field, tree line, firework, flag, and sky gradient palettes are constants and function calculations inside `StarSpangledView.mc`.
- **Layout anchors**: all coordinate scales are relative percentage values in `onUpdate()`.
