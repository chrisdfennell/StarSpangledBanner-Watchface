# Changelog

All notable changes to Star Spangled Banner are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-16

Initial release of **Star Spangled Banner** — a 4th of July / Independence Day watch
face for Garmin Connect IQ. Fireworks rise from an open field and burst overhead
beneath a waving American flag.

### Added
- **Fireworks show**: Rockets streak up from the field and burst into expanding,
  drooping, fading showers of color overhead. Several shells run concurrently,
  staggered so the sky keeps popping through the evening and night. Everything is
  computed deterministically from the clock — no particle state is kept between
  frames — and spark counts scale with the adaptive quality level.
- **Living summer sky**: A time-of-day gradient (warm dawn → bright midday blue →
  golden hour → fiery sunset → deep starry night), anchored to the **real**
  sunrise/sunset computed from the watch's last-known location (with a fixed summer
  fallback). A warm sun and silver moon arc along the same real sun times, and stars
  come out at night.
- **Open field & distant tree line**: A rolling green field ringed along the horizon
  by a silhouetted forest edge (rounded canopy plus a few conifer spires), a
  foreground grass strip, and grass blades — the "wide-open field, trees all around"
  look.
- **Waving American flag**: 13 red/white stripes with a blue canton of white
  star-dots, billowing on a travelling wave on a pole with a gold finial, planted in
  the field.
- **Fireflies at night**: Soft yellow-green glints drift and blink over the field
  after dark.
- **America's 250th** (on by default): A golden "1776 ★ 2026" banner marking the
  Semiquincentennial — 250 years of independence on July 4, 2026.
- **Grand Finale mode** (off by default): Denser, faster fireworks day and night,
  patriotic red-white-blue bunting across the top, a twinkling flag finial, and a
  biplane flyover trailing a star-spangled pennant.
- **Field critters** (on by default): Occasional crossing visitors, one at a time,
  every ~40s. Day pool: bald eagle (soars), deer (walks), cottontail (bounds),
  butterfly (flutters). Night pool: owl (glides), red fox (trots + pounces), raccoon
  (trundles), bat (darts). Silhouette-outlined and active-layer only.
- **Spinning star seconds**: A five-pointed star second indicator orbits the
  perimeter.
- **Configurable complications**: Bottom-left and bottom-right each choose from Heart
  Rate, Body Battery, Device Battery (with a live fill bar), Steps, Calories, or Off,
  each with a matching icon. A red-white-blue steps progress bar and numeric count
  sit in the center.
- **Broad device support**: Every Connect IQ 4.0+ round watch — Forerunner (incl.
  965 / 970), fenix 7/8, epix 2 / Pro, enduro 3, Venu 2/3, Vivoactive 5/6, Instinct 3
  / E / Crossover, and the Approach (golf), Descent (dive), D2 (aviation), and MARQ
  specialty watches. Square/rectangular panels (Venu Sq 2, Venu X1) are excluded.
- **Always-on / low-power support**: A burn-in-safe layout (dim time/date, thin
  outline metrics, no fills or animation, per-minute pixel shift) with a clipped
  AMOLED partial update.

### Performance
- Adaptive render quality (0–3) that times each frame and scales detail with
  hysteresis; cached per-frame syscalls; hoisted/reused buffers; an AMOLED sky
  gradient rendered once into a `BufferedBitmap`; and loop-safe sun/angle math with a
  non-finite guard.

[1.0.0]: https://github.com/chrisdfennell/StarSpangledBanner-Watchface/releases/tag/v1.0.0
