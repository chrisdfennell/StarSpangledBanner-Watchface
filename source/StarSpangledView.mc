import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Application;
import Toybox.SensorHistory;
import Toybox.Position;
import Toybox.Math;
import Toybox.Weather;

//
// Star Spangled Banner - a 4th of July / Independence Day watch face.
//
//   - Center:  large digital time + elegant date line
//   - Left:    configurable complication (default heart rate)
//   - Right:   configurable complication (default device battery)
//   - Bottom:  steps progress bar, styled in patriotic red-white-blue
//   - Background: a living summer sky gradient, arcing summer sun / moon, stars,
//                 drifting clouds, an open rolling field ringed by a distant tree
//                 line, a waving American flag, drifting fireflies at night, and
//                 FIREWORKS that rise from the field and burst overhead.
//
// The two bottom complications are chosen in the app settings (heart rate, Body
// Battery, device battery, steps, or calories) and each draws a matching icon.
// The sun, day/night, fireworks, and sky track the REAL sunrise/sunset computed
// from the watch's location and today's date, falling back to a fixed summer
// schedule when no location fix is available.
//
// Everything scales cleanly relative to the screen dimensions (dc.getWidth()/getHeight()).
//
class StarSpangledView extends WatchUi.WatchFace {

    // --- Screen geometry (resolved in onLayout) ---
    private var mWidth as Number = 0;
    private var mHeight as Number = 0;
    private var mCenterX as Number = 0;
    private var mCenterY as Number = 0;

    // --- State ---
    private var mIsSleep as Boolean = false;
    private var mLowPower as Boolean = false;  // true only on AMOLED in Always-On (burn-in) mode
    private var mFlatGlobes as Boolean = false; // true on MIP: flat 2-tone fills (no banded gradient)
    private var mLastMin as Number = -1;       // throttles low-power partial updates

    // --- Per-frame syscall caches (read once at the top of a redraw, reused
    //     everywhere; helpers fall back to a live read if called outside one). ---
    private var mSettings as System.DeviceSettings or Null = null;
    private var mClock as System.ClockTime or Null = null;
    private var mActInfo as ActivityMonitor.Info or Null = null;

    // --- Sunrise/sunset retry throttle ---
    private var mSunLastTry as Number = -10000;  // epoch sec of last failed retry

    // --- Adaptive render quality: self-tunes detail to the device by measuring
    //     each active frame and nudging mQuality with hysteresis. ---
    private var mQuality as Number = 2;        // 3 = full detail, 0 = leanest
    private var mFrameStart as Number = 0;
    private const Q_SLOW_MS = 220;             // frame slower than this -> drop a level
    private const Q_FAST_MS = 120;             // faster than this -> raise a level

    // --- AMOLED sky-gradient buffer: render the per-row gradient into a bitmap
    //     once and blit it; repaint in place only when colors change. ---
    private var mSkyBufRef as Graphics.BufferedBitmapReference or Null = null;
    private var mSkyKeyTop as Number = -1;
    private var mSkyKeyBottom as Number = -1;
    private var mSkyKeyW as Number = -1;
    private var mSkyKeyH as Number = -1;

    // --- Hoisted per-frame allocations -------------------------------------
    // Night star field.
    private const STAR_X = [70, 120, 180, 240, 310, 380, 90, 150, 220, 290, 360, 130, 200, 270, 340, 110, 250, 330] as Array<Number>;
    private const STAR_Y = [50, 70, 45, 60, 55, 75, 110, 95, 120, 105, 115, 90, 130, 80, 100, 60, 125, 70] as Array<Number>;

    // Sky-gradient keyframe color tables (a living summer sky: warm dawn, bright
    // blue midday, a golden-hour glow, a fiery sunset, then deep night).
    // The keyframe HOURS still vary per frame to anchor to the real sun times.
    private const SKY_TOP_REAL    = [0x070B1E, 0x1A2350, 0x5A6FB0, 0x4F93D8, 0x3F8AD8, 0x6E6AA8, 0x4A3A78, 0x141A40, 0x070B1E] as Array<Number>;
    private const SKY_BOTTOM_REAL = [0x121A38, 0x4A4A7A, 0xF0A060, 0xBFE4F5, 0xCDEAF6, 0xFFC070, 0xF0702A, 0x5A3A6E, 0x121A38] as Array<Number>;
    private const SKY_TOP_FB      = [0x070B1E, 0x1A2350, 0x5A6FB0, 0x3F8AD8, 0x3F8AD8, 0x6E6AA8, 0x4A3A78, 0x141A40, 0x070B1E] as Array<Number>;
    private const SKY_BOTTOM_FB   = [0x121A38, 0x4A4A7A, 0xF0A060, 0xCDEAF6, 0xCDEAF6, 0xFFC070, 0xF0702A, 0x5A3A6E, 0x121A38] as Array<Number>;
    private const SKY_HOURS_FB    = [0.0, 5.0, 6.0, 8.0, 13.0, 19.0, 20.5, 21.5, 24.0] as Array<Float>;

    // Firework spark palette (bright, saturated bursts).
    private const FIRE_COLORS = [0xFFD23F, 0xFF3B30, 0x4F9BFF, 0x44E06A, 0xFF5AD0, 0xFFFFFF, 0x37D6FF, 0xFF8A3D] as Array<Number>;

    // Reusable polygon buffer for the rolling field hills.
    private var mDriftPts as Array<Array> or Null = null;

    // --- Complication option ids (must match resources/settings list values) ---
    private const COMP_OFF      = 0;
    private const COMP_HR       = 1;  // heart rate (BPM)
    private const COMP_BODY     = 2;  // Body Battery (%)
    private const COMP_BATTERY  = 3;  // device battery (%)
    private const COMP_STEPS    = 4;  // step count
    private const COMP_CALORIES = 5;  // calories (kcal)

    // --- Settings (see resources/settings) ---
    private var mShowDate as Boolean = true;
    private var mStepGoalOverride as Number = 0;  // 0 => use device step goal
    private var mLeftComp as Number = COMP_HR;       // bottom-left complication
    private var mRightComp as Number = COMP_BATTERY; // bottom-right complication
    private var mFestive as Boolean = false;         // Grand Finale extras (opt-in)
    private var mShowFireworks as Boolean = true;    // rockets rise + burst at night
    private var mShow250 as Boolean = true;          // America's 250th birthday banner
    private var mShowCritters as Boolean = true;     // occasional field visitors

    // --- Critter type ids (day + night pools, indexed by a clock hash) ---
    private const CR_EAGLE     = 0;  // bald eagle, soars across the sky (day)
    private const CR_DEER      = 1;  // deer, walks across the field (day)
    private const CR_RABBIT    = 2;  // cottontail, bounds across the field (day)
    private const CR_BUTTERFLY = 3;  // butterfly, flutters across the sky (day)
    private const CR_OWL       = 4;  // owl, glides across the night sky (night)
    private const CR_FOX       = 5;  // red fox, trots across the field (night)
    private const CR_RACCOON   = 6;  // raccoon, trundles across the field (night)
    private const CR_BAT       = 7;  // bat, darts across the night sky (night)

    // --- Festive timing: a biplane flyover every PLANE_PERIOD seconds, lasting
    //     PLANE_FLIGHT seconds as it crosses the sky left-to-right. ---
    private const PLANE_PERIOD = 150;  // one flyover every 2.5 minutes
    private const PLANE_FLIGHT = 10;   // seconds the plane is on screen

    // --- Heart-rate cache (sensor read throttled to once every ~10s) ---
    private var mCachedHr as Number or Null = null;
    private var mHrLastSec as Number = -100;

    // --- Sunrise/sunset cache (recomputed when the day or first fix changes) ---
    private var mSunDay as Number = -1;        // day-of-year the times were computed for
    private var mSunValid as Boolean = false;  // true once a real location fix was used
    private var mSunrise as Float = 6.0;       // local hours; defaults = fixed summer schedule
    private var mSunset as Float = 20.5;

    // --- Fonts (vector fonts with safe fallbacks) ---
    private var mFontTime as Graphics.FontType or Null = null;
    private var mFontDate as Graphics.FontType or Null = null;
    private var mFontValue as Graphics.FontType or Null = null;
    private var mFontLabel as Graphics.FontType or Null = null;

    // --- Color Palettes ----------------------------------------------------
    // Old Glory red / white / blue
    private const C_RED   = 0xC8102E;
    private const C_WHITE = 0xF4F7FF;
    private const C_BLUE  = 0x3457A8;
    private const C_NAVY  = 0x10204A;

    // Body Battery globe = silver-white
    private const C_BODY_BRIGHT = 0xE6ECF6;
    private const C_BODY_DARK   = 0x1C2436;
    private const C_BODY_RIM    = 0xFFFFFF;
    private const C_BODY_GLOW   = 0x5A6A88;

    // Device battery globe = patriot blue
    private const C_BATT_BRIGHT = 0x7FB0FF;
    private const C_BATT_DARK   = 0x101F44;
    private const C_BATT_RIM    = 0xCFE0FF;
    private const C_BATT_GLOW   = 0x2A4E8C;

    // Steps bar = red fill with a white frost frame
    private const C_XP_TRACK    = 0x141C2E;
    private const C_XP_FILL     = 0xC8102E;
    private const C_XP_BRIGHT   = 0xFF8A7A;
    private const C_XP_GLOW     = 0x6A0E1E;
    private const C_XP_BORDER   = 0xF4F7FF;

    private const BG_COLOR = 0x000000;        // pitch black for AMOLED contrast/battery

    // Screenshot showcase: force a night Grand Finale frame for promo art. OFF in shipping builds.
    private const SHOWCASE = false;

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    // Read user settings; safe to call any time.
    function loadSettings() as Void {
        try {
            if (Application has :Properties) {
                var showDate = Application.Properties.getValue("ShowDate");
                var stepGoal = Application.Properties.getValue("StepGoalOverride");
                var leftComp = Application.Properties.getValue("LeftComplication");
                var rightComp = Application.Properties.getValue("RightComplication");
                var festive = Application.Properties.getValue("FestiveMode");
                var fireworks = Application.Properties.getValue("ShowFireworks");
                var show250 = Application.Properties.getValue("Show250");
                var critters = Application.Properties.getValue("ShowCritters");
                if (showDate != null) { mShowDate = showDate; }
                if (stepGoal != null) { mStepGoalOverride = stepGoal; }
                if (leftComp != null) { mLeftComp = leftComp; }
                if (rightComp != null) { mRightComp = rightComp; }
                if (festive != null) { mFestive = festive; }
                if (fireworks != null) { mShowFireworks = fireworks; }
                if (show250 != null) { mShow250 = show250; }
                if (critters != null) { mShowCritters = critters; }
            }
        } catch (e) {
            // keep defaults
        }
        if (mStepGoalOverride < 0) { mStepGoalOverride = 0; }
    }

    function onLayout(dc as Dc) as Void {
        mWidth = dc.getWidth();
        mHeight = dc.getHeight();
        mCenterX = mWidth / 2;
        mCenterY = mHeight / 2;
        initFonts();
    }

    // Custom fonts generated by gen_fonts.py are loaded here.
    function initFonts() as Void {
        try {
            mFontTime  = WatchUi.loadResource(Rez.Fonts.ExocetTime) as Graphics.FontType;
            mFontValue = WatchUi.loadResource(Rez.Fonts.ExocetValue) as Graphics.FontType;
            mFontLabel = WatchUi.loadResource(Rez.Fonts.ExocetLabel) as Graphics.FontType;
            mFontDate  = mFontLabel;
        } catch (e) {
            mFontTime = null;
            mFontValue = null;
            mFontLabel = null;
            mFontDate = null;
        }

        // Vector-font fallback for anything that didn't load.
        if (Graphics has :getVectorFont) {
            var bold = ["RobotoCondensedBold", "RobotoRegular", "sans-serif"] as Array<String>;
            if (mFontTime == null)  { mFontTime  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.21).toNumber() }); }
            if (mFontDate == null)  { mFontDate  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.058).toNumber() }); }
            if (mFontValue == null) { mFontValue = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.085).toNumber() }); }
            if (mFontLabel == null) { mFontLabel = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.044).toNumber() }); }
        }

        // Built-in last resort.
        if (mFontTime == null)  { mFontTime  = Graphics.FONT_NUMBER_THAI_HOT; }
        if (mFontDate == null)  { mFontDate  = Graphics.FONT_TINY; }
        if (mFontValue == null) { mFontValue = Graphics.FONT_MEDIUM; }
        if (mFontLabel == null) { mFontLabel = Graphics.FONT_XTINY; }
    }

    function onShow() as Void {
        loadSettings();
    }

    // Single render entry point for both active and low-power frames.
    function onUpdate(dc as Dc) as Void {
        mFrameStart = System.getTimer();

        var w = mWidth;
        var h = mHeight;

        // Cache per-frame syscalls once: settings, clock, activity.
        var settings = System.getDeviceSettings();
        mSettings = settings;
        var clockTime = System.getClockTime();
        mClock = clockTime;
        mActInfo = ActivityMonitor.getInfo();

        var burnIn = false;
        var dx = 0;
        var dy = 0;
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        if (hasBurnIn && mIsSleep) {
            burnIn = true;
            var shift = computeBurnInShift();
            dx = shift[0]; dy = shift[1];
        }
        mLowPower = burnIn;
        mFlatGlobes = !hasBurnIn;

        var cx = mCenterX + dx;
        var cy = mCenterY + dy;

        // 1. Clear to pitch black
        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        // Time values
        var hour = clockTime.hour;
        var min = clockTime.min;
        var secVal = clockTime.sec;

        if (!mLowPower) {
            // --- ACTIVE VISUAL LAYER ---

            // A. Resolve today's sunrise/sunset (cached), then get the living
            //    summer-sky gradient colors for the current time.
            updateSunTimes();
            var tNow = hour.toFloat() + min.toFloat() / 60.0;
            var skyColors = SHOWCASE ? getSkyColors(22, 0) : getSkyColors(hour, min);
            var cTop = skyColors[0];
            var cBottom = skyColors[1];

            // B. Draw Sky
            var skyH = (h * 0.72).toNumber();
            if (mFlatGlobes) {
                // MIP: Solid fill to prevent ugly banding
                dc.setColor(cTop, cTop);
                dc.fillRectangle(0, 0, w, skyH);
            } else {
                // AMOLED: smooth gradient, cached in a BufferedBitmap.
                var skyBmp = getSkyBitmap(w, skyH, cTop, cBottom);
                if (skyBmp != null) {
                    dc.drawBitmap(0, 0, skyBmp);
                } else {
                    drawSkyGradientDirect(dc, w, skyH, cTop, cBottom);
                }
            }

            var isNight = !(tNow >= mSunrise && tNow < mSunset);
            // Fireworks light up the evening and night (and all the time in Grand
            // Finale). isDusk catches the last hour before sunset for an early show.
            var isDusk = (tNow > mSunset - 1.0) && (tNow < mSunset);
            if (SHOWCASE) { isNight = true; isDusk = false; mFestive = true; mShowFireworks = true; }

            // At most one critter is active at a time; computed purely from the clock.
            var crit = mShowCritters ? computeCritter(hour, min, secVal, isNight) : null;

            // C. Stars at night
            if (isNight) {
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                for (var i = 0; i < STAR_X.size(); i++) {
                    var stx = (STAR_X[i] * w / 454).toNumber();
                    var sty = (STAR_Y[i] * h / 454).toNumber();
                    dc.drawPoint(stx, sty);
                }
            }

            // D. Arcing Summer Sun / Moon along the real day arc
            var dayStart = mSunrise;
            var dayEnd = mSunset;
            var t = tNow;
            var isDay = !isNight;
            var arcR = (w * 0.38).toNumber();
            var arcCenterY = (h * 0.66).toNumber();

            var angle = 0.0;
            if (isDay) {
                angle = Math.PI - (Math.PI * (t - dayStart) / (dayEnd - dayStart));
            } else {
                var tNight = (t < dayStart) ? (t + (24.0 - dayEnd)) : (t - dayEnd);
                angle = Math.PI - (Math.PI * tNight / (24.0 - (dayEnd - dayStart)));
            }
            var sx = cx + (arcR * Math.cos(angle)).toNumber();
            var sy = arcCenterY - (arcR * Math.sin(angle)).toNumber();

            if (isDay) {
                drawSummerSun(dc, sx, sy, (w * 0.07).toNumber(), skyH, cTop, cBottom, secVal);
            } else {
                drawMoon(dc, sx, sy, (w * 0.055).toNumber(), skyH, cTop, cBottom);
            }

            // E. Drifting summer clouds
            var cloudOffset = (min * 60 + secVal).toFloat();
            var cloudSpan = w + 80;
            var cx1 = (((((w * 0.1 + (cloudOffset * 0.07)).toNumber()) % cloudSpan) + cloudSpan) % cloudSpan) - 40;
            var cx2 = (((((w * 0.7 - (cloudOffset * 0.045)).toNumber()) % cloudSpan) + cloudSpan) % cloudSpan) - 40;
            var cloudTint = isDay ? lerpColor(0xFFFFFF, cBottom, 0.20) : lerpColor(0x4A4A6A, cBottom, 0.30);
            drawCloud(dc, cx1, (h * 0.18).toNumber(), cloudTint);
            drawCloud(dc, cx2, (h * 0.26).toNumber(), cloudTint);

            // F. FIREWORKS rise from the field and burst overhead.
            if (mShowFireworks && (isNight || isDusk || mFestive)) {
                drawFireworks(dc, w, h, skyH, hour, min, secVal, mFestive);
            }

            // F2. Sky critters (eagle/butterfly by day, owl/bat by night).
            if (crit != null && isSkyCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }

            // G. Open rolling field (green hills) + distant tree line on the horizon.
            drawField(dc, w, h, skyH, isNight, secVal);

            // H. The waving American flag — the centerpiece of the field.
            var fieldTop = (h * 0.66).toNumber();
            drawFlag(dc, (w * 0.80).toNumber(), (h * 0.92).toNumber(), (h * 0.40).toNumber(), secVal, mFestive && isNight);

            // H2. Grand Finale: a biplane sweeps across the sky now and then.
            if (mFestive) {
                drawPlaneFlyover(dc, w, h, hour, min, secVal);
            }

            // H3. Ground critters (deer/rabbit/fox/raccoon) walk on the field.
            if (crit != null && !isSkyCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }

            // I. Fireflies drift over the field at night.
            if (isNight) {
                drawFireflies(dc, w, h, secVal, min);
            }

            // J. Grand Finale: patriotic bunting drapes across the top.
            if (mFestive) {
                drawBunting(dc, w, h);
            }

            // K. America's 250th: golden "1776 * 2026" banner above the time.
            if (mShow250) {
                drawBirthday250(dc, cx, (h * 0.30).toNumber());
            }
        }

        // --- Center Clock & Date ---
        drawTime(dc, cx, cy - (h * 0.05).toNumber());
        if (mShowDate) {
            drawDate(dc, cx, cy + (h * 0.06).toNumber());
        }

        // --- Bottom Field Complications (Symmetrical Layout) ---
        var metricsY = (h * 0.815).toNumber() + dy;
        var leftX    = (w * 0.22).toNumber() + dx;
        var rightX   = (w * 0.78).toNumber() + dx;

        drawComplication(dc, leftX, metricsY, mLeftComp);
        drawComplication(dc, rightX, metricsY, mRightComp);

        // Steps Progress Bar & Numeric Text (Centered)
        var barW = (w * 0.38).toNumber();
        var barH = 8;
        var barY = (h * 0.91).toNumber() + dy;
        var stepsFraction = getStepFraction();
        drawXpBar(dc, cx, barY, barW, barH, stepsFraction);

        if (!burnIn) {
            var actInfo = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
            var steps = (actInfo != null && actInfo.steps != null) ? actInfo.steps : 0;
            var stepsStr = steps.format("%d") + " STEPS";
            drawTextWithOutline(dc, cx, barY - 14, mFontLabel, stepsStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, 0xFFFFFF);
        }

        // Spinning star seconds marker — drawn LAST so it sits on top of the time,
        // date, and complications. Only animates while active.
        if (!mIsSleep) {
            var secAngle = (secVal * 6.0) * Math.PI / 180.0;
            var secRadius = (w * 0.44).toNumber() - 10;
            var fsx = cx + (secRadius * Math.sin(secAngle)).toNumber();
            var fsy = cy - (secRadius * Math.cos(secAngle)).toNumber();
            drawStarSecond(dc, fsx, fsy, secVal);
        }

        // Adaptive quality: nudge detail up/down by this frame's cost, active frames only.
        if (!mLowPower) {
            var dt = System.getTimer() - mFrameStart;
            if (dt > Q_SLOW_MS) { if (mQuality > 0) { mQuality--; } }
            else if (dt < Q_FAST_MS) { if (mQuality < 3) { mQuality++; } }
        }
    }

    // Shared anti-burn-in pixel shift.
    private function computeBurnInShift() as Array<Number> {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var phase = clock.min % 4;
        if (phase == 1)      { return [4, 2]; }
        else if (phase == 2) { return [-3, 4]; }
        else if (phase == 3) { return [3, -4]; }
        return [0, 0];
    }

    // ------------------------------------------------------------------ Elements

    function drawTime(dc as Dc, cx as Number, cy as Number) as Void {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var hour = clock.hour;
        var min = clock.min;
        var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
        var is24 = settings.is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var hourStr = is24 ? hour.format("%02d") : hour.format("%d");
        var timeStr = hourStr + ":" + min.format("%02d");

        var color = mLowPower ? 0x6E6E6E : 0xF4F7FF;
        drawTextWithOutline(dc, cx, cy, mFontTime, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    function drawDate(dc as Dc, cx as Number, y as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week.toUpper() + "   " + info.month.toUpper() + " " + info.day;

        var weatherStr = mLowPower ? null : getWeatherString();
        if (weatherStr != null) {
            dateStr = dateStr + "   •   " + weatherStr;
        }

        var color = mLowPower ? 0x555555 : 0x9FC0FF;
        drawTextWithOutline(dc, cx, y, mFontDate, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    private function drawCloud(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 12, y, 10);
        dc.fillCircle(x + 12, y, 10);
        dc.fillCircle(x, y - 5, 14);
        dc.fillRectangle(x - 12, y - 2, 24, 12);
    }

    // Warm summer sun with a soft halo and faint rotating rays.
    private function drawSummerSun(dc as Dc, sx as Number, sy as Number, sunR as Number, skyH as Number, cTop as Number, cBottom as Number, sec as Number) as Void {
        var skyFrac = sy.toFloat() / skyH.toFloat();
        if (skyFrac < 0.0) { skyFrac = 0.0; }
        if (skyFrac > 1.0) { skyFrac = 1.0; }
        var skyColor = lerpColor(cTop, cBottom, skyFrac);

        if (mQuality >= 2) {
            dc.setColor(0xFFE9A8, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            var numRays = 8;
            var secOffset = sec.toFloat() * 0.02;
            for (var i = 0; i < numRays; i++) {
                var rayAngle = (i * (2.0 * Math.PI / numRays)) + secOffset;
                var rx1 = (sx + (sunR + 2) * Math.cos(rayAngle)).toNumber();
                var ry1 = (sy + (sunR + 2) * Math.sin(rayAngle)).toNumber();
                var rx2 = (sx + (sunR + 9) * Math.cos(rayAngle)).toNumber();
                var ry2 = (sy + (sunR + 9) * Math.sin(rayAngle)).toNumber();
                dc.drawLine(rx1, ry1, rx2, ry2);
            }
        }

        // Warm halo
        dc.setColor(lerpColor(skyColor, 0xFFD27A, 0.30), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, sunR + 6);
        dc.setColor(lerpColor(skyColor, 0xFFE6A8, 0.60), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, sunR + 3);

        // Core
        dc.setColor(0xFFEFB0, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, sunR);
        dc.setColor(0xFFF8E0, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, sunR - 4);
    }

    private function drawMoon(dc as Dc, sx as Number, sy as Number, moonR as Number, skyH as Number, cTop as Number, cBottom as Number) as Void {
        var skyFrac = sy.toFloat() / skyH.toFloat();
        if (skyFrac < 0.0) { skyFrac = 0.0; }
        if (skyFrac > 1.0) { skyFrac = 1.0; }
        var skyColor = lerpColor(cTop, cBottom, skyFrac);

        dc.setColor(0xE6ECF2, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, moonR);
        dc.setColor(skyColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx + 5, sy - 2, moonR);
    }

    // ------------------------------------------------------------- Fireworks
    //
    // Rockets rise from the field and burst overhead. Everything is deterministic
    // from the clock (no RNG/state), so a shell renders identically each frame
    // within a second. Several shells run concurrently, staggered so the sky keeps
    // popping. Each shell: rises for RISE seconds, bursts (sparks expand + fall
    // under gravity, fading out) for BURST seconds, then a quiet GAP.
    private function drawFireworks(dc as Dc, w as Number, h as Number, skyH as Number, hour as Number, min as Number, sec as Number, finale as Boolean) as Void {
        var secOfDay = hour * 3600 + min * 60 + sec;

        var shells = finale ? ((mQuality >= 2) ? 6 : 4) : ((mQuality >= 2) ? 3 : 2);
        var RISE  = 3;
        var BURST = 6;
        var GAP   = finale ? 1 : 4;
        var CYCLE = RISE + BURST + GAP;

        var marginX = (w * 0.14).toNumber();
        var spanX = w - 2 * marginX;
        if (spanX < 1) { spanX = 1; }
        var fieldTop = (h * 0.64).toNumber();

        for (var k = 0; k < shells; k++) {
            var tt = secOfDay + k * 7;          // stagger the launch slots
            var cyc = tt / CYCLE;               // integer cycle index
            var pos = tt - cyc * CYCLE;         // 0..CYCLE-1 (seconds into this cycle)

            // Deterministic per-shell parameters from the cycle + slot.
            var hsh  = (cyc * 131 + k * 733 + 17) % 100000;
            var hsh2 = (cyc * 977 + k * 389 + 53) % 100000;
            if (hsh < 0) { hsh = -hsh; }
            if (hsh2 < 0) { hsh2 = -hsh2; }

            var tx = marginX + (hsh % spanX);
            var burstY = (h * 0.14).toNumber() + (hsh2 % (h * 0.30).toNumber());
            var color = FIRE_COLORS[hsh % FIRE_COLORS.size()];

            if (pos < RISE) {
                // --- Rising rocket: a bright comet head + a short trail ---
                var rf = pos.toFloat() / RISE.toFloat();           // 0..~0.66
                var headY = (fieldTop + (burstY - fieldTop) * rf).toNumber();
                dc.setColor(0xFFE9A8, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(tx, headY, 2);
                dc.setColor(scaleColor(0xFFB04A, 0.6), Graphics.COLOR_TRANSPARENT);
                for (var j = 1; j <= 3; j++) {
                    var ty = headY + (j * (h * 0.025)).toNumber();
                    if (ty < fieldTop) { dc.fillCircle(tx, ty, 1); }
                }
            } else if (pos < RISE + BURST) {
                // --- Burst: a ring (or two) of sparks expanding + drooping ---
                var bf = (pos - RISE).toFloat() / BURST.toFloat();  // 0..~1
                var ease = 1.0 - (1.0 - bf) * (1.0 - bf);           // ease-out
                var maxR = (w * (finale ? 0.21 : 0.17));
                var rad = (maxR * ease).toNumber();
                var sag = (h * 0.10 * bf * bf).toNumber();          // gravity droop
                var bright = 1.0 - bf;                              // fade out
                var sparkC = lerpColor(0x101010, color, bright * 0.75 + 0.25);

                // Opening flash
                if (bf < 0.22) {
                    dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(tx, burstY, 3);
                }

                var nspark = (mQuality >= 2) ? (finale ? 16 : 12) : 8;
                dc.setColor(sparkC, Graphics.COLOR_TRANSPARENT);
                for (var s = 0; s < nspark; s++) {
                    var ang = s * (2.0 * Math.PI / nspark) + cyc.toFloat() * 0.3;
                    var px = (tx + rad * Math.cos(ang)).toNumber();
                    var py = (burstY + rad * Math.sin(ang)).toNumber() + sag;
                    dc.fillCircle(px, py, (bf < 0.6) ? 2 : 1);
                }

                // Inner ring at higher quality for a fuller burst.
                if (mQuality >= 3) {
                    var rad2 = (rad * 0.55).toNumber();
                    dc.setColor(lerpColor(sparkC, 0xFFFFFF, 0.25), Graphics.COLOR_TRANSPARENT);
                    for (var s2 = 0; s2 < nspark; s2++) {
                        var ang2 = (s2 + 0.5) * (2.0 * Math.PI / nspark) + cyc.toFloat() * 0.3;
                        var px2 = (tx + rad2 * Math.cos(ang2)).toNumber();
                        var py2 = (burstY + rad2 * Math.sin(ang2)).toNumber() + (sag / 2);
                        dc.fillCircle(px2, py2, 1);
                    }
                }
            }
        }
    }

    // Fireflies: a few soft yellow-green glints drifting and blinking over the
    // field at night. Deterministic from the clock; replaces the snow of winter.
    private function drawFireflies(dc as Dc, w as Number, h as Number, sec as Number, min as Number) as Void {
        var t = (min * 60 + sec).toFloat();
        var n = (mQuality >= 3) ? 16 : (mQuality == 2) ? 12 : (mQuality == 1) ? 8 : 5;
        var topY = (h * 0.60);
        var bandH = (h * 0.32);
        for (var i = 0; i < n; i++) {
            // Blink: each firefly is lit only part of the time, staggered.
            if (((sec + i * 3) % 4) >= 3) { continue; }
            var colF = ((i * 41) % 100).toFloat() / 100.0;
            var drift = 14.0 * Math.sin(t * 0.05 + i);
            var x = (colF * w + drift).toNumber();
            if (x < 0) { x += w; }
            if (x >= w) { x -= w; }
            var bob = ((i * 53) % 100).toFloat() / 100.0;
            var y = (topY + bob * bandH + 6.0 * Math.sin(t * 0.07 + i * 1.3)).toNumber();
            dc.setColor(0x2A3A12, Graphics.COLOR_TRANSPARENT);   // soft glow
            dc.fillCircle(x, y, 2);
            dc.setColor(0xD8F060, Graphics.COLOR_TRANSPARENT);   // warm yellow-green
            dc.fillCircle(x, y, 1);
        }
    }

    // ------------------------------------------------------------- The field
    //
    // An open, rolling green field that fills the lower screen, ringed along the
    // horizon by a silhouetted tree line (a distant forest edge) so the scene
    // reads as "standing in an open field, trees all around."
    private function drawField(dc as Dc, w as Number, h as Number, skyH as Number, isNight as Boolean, sec as Number) as Void {
        var horizon = (h * 0.64).toNumber();

        // Distant tree line silhouette sitting on the horizon.
        drawTreeLine(dc, w, horizon, isNight);

        // Rolling field: a couple of gentle hill bands in greens, darker at night.
        var backGreen  = isNight ? 0x16361E : 0x3E7A3A;
        var frontGreen = isNight ? 0x102A18 : 0x2E6A2E;
        var grassDark  = isNight ? 0x0A1E10 : 0x215022;

        // Back hill band
        drawHill(dc, (h * 0.70).toNumber(), 5, 60.0, sec.toFloat() * 0.01, backGreen);
        // Front hill band
        drawHill(dc, (h * 0.78).toNumber(), 6, 44.0, -sec.toFloat() * 0.012, frontGreen);

        // Foreground grass strip
        var grassY = (h * 0.90).toNumber();
        dc.setColor(grassDark, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, grassY, w, h - grassY);

        // A few grass blades poking up along the foreground edge.
        var blade = isNight ? 0x16361E : 0x3E7A3A;
        dc.setColor(blade, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        var step = (w / 26);
        if (step < 6) { step = 6; }
        for (var bx = 4; bx < w; bx += step) {
            var lean = ((bx % 3) - 1) * 2;
            dc.drawLine(bx, grassY + 2, bx + lean, grassY - 6);
        }
    }

    // A silhouetted distant tree line: overlapping rounded tree-tops across the
    // width, with a couple of taller conifers for variety, all one dark color.
    private function drawTreeLine(dc as Dc, w as Number, baseY as Number, isNight as Boolean) as Void {
        var treeColor = isNight ? 0x0C2414 : 0x1C4A24;
        dc.setColor(treeColor, Graphics.COLOR_TRANSPARENT);

        // A solid base strip to seat the canopy.
        dc.fillRectangle(0, baseY, w, (w * 0.03).toNumber() + 4);

        // Rounded deciduous canopy: overlapping circles of varied radius.
        var r = (w * 0.045).toNumber();
        if (r < 8) { r = 8; }
        var stepX = (r * 1.3).toNumber();
        var i = 0;
        for (var x = -r; x < w + r; x += stepX) {
            var rr = r + ((i % 3) - 1) * (r / 4);    // vary the size a little
            var top = baseY - (rr * 0.7).toNumber();
            dc.fillCircle(x, top, rr);

            // Every few trees, a taller conifer spire pokes above the canopy.
            if (i % 4 == 2) {
                var ch = (r * 2.2).toNumber();
                var cw = (r * 0.7).toNumber();
                dc.fillPolygon([
                    [x - cw, baseY - (r * 0.4).toNumber()],
                    [x + cw, baseY - (r * 0.4).toNumber()],
                    [x, baseY - ch]
                ] as Array<Array>);
            }
            i++;
        }
    }

    // One rolling hill band: a sine-wave polygon filled down to the bottom.
    private function drawHill(dc as Dc, yBase as Number, amp as Number, waveLen as Float, phase as Float, color as Number) as Void {
        var w = mWidth;
        var h = mHeight;
        var steps = 12;
        var stepW = w / steps;
        if (mDriftPts == null) {
            var buf = new [steps + 3] as Array<Array>;
            for (var k = 0; k < steps + 3; k++) { buf[k] = [0, 0]; }
            mDriftPts = buf;
        }
        var points = mDriftPts;
        points[0][0] = w; points[0][1] = h;
        points[1][0] = 0; points[1][1] = h;
        for (var i = 0; i <= steps; i++) {
            var x = i * stepW;
            var ang = (x.toFloat() / waveLen) + phase;
            var y = yBase + (amp * Math.sin(ang)).toNumber();
            points[i + 2][0] = x;
            points[i + 2][1] = y;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
    }

    // ------------------------------------------------------------- The flag
    //
    // A waving American flag on a pole planted in the field. Rendered as vertical
    // slices, each shifted by a travelling sine wave so the whole flag billows.
    // 13 red/white stripes with a blue union of white star-dots in the canton.
    private function drawFlag(dc as Dc, poleX as Number, baseY as Number, poleH as Number, sec as Number, spotlit as Boolean) as Void {
        var topY = baseY - poleH;

        // Pole
        var poleW = (poleH * 0.025).toNumber();
        if (poleW < 2) { poleW = 2; }
        dc.setColor(0x9AA0A6, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(poleX - poleW / 2, topY, poleW, baseY - topY);
        // Gold finial ball on top (with a little twinkle in Grand Finale at night)
        if (spotlit && (sec % 2 == 0)) {
            dc.setColor(0xFFF3C0, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            var sp = poleW + 4;
            dc.drawLine(poleX - sp, topY - 2, poleX + sp, topY - 2);
            dc.drawLine(poleX, topY - 2 - sp, poleX, topY - 2 + sp);
        }
        dc.setColor(0xFFD23F, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(poleX, topY - 2, poleW);

        // Flag dimensions (flies to the right of the pole)
        var fw = (poleH * 0.52).toNumber();
        var fh = (poleH * 0.34).toNumber();
        var flagX = poleX + poleW / 2;
        var flagTop = topY + 1;
        var stripeH = fh.toFloat() / 13.0;

        var slices = (mWidth > 300) ? 12 : 8;
        var sliceW = fw / slices;
        if (sliceW < 2) { sliceW = 2; }
        var unionSlices = (slices * 2 + 2) / 5;       // canton ~ 40% of width
        var unionStripes = 7;                          // canton covers 7 stripes
        var phase = sec.toFloat() * 0.5;

        for (var i = 0; i < slices; i++) {
            var xs = flagX + i * sliceW;
            // Travelling wave: more billow toward the free (right) end.
            var amp = 1.5 + (fh * 0.10) * (i.toFloat() / slices.toFloat());
            var dy = (amp * Math.sin(i * 0.9 - phase)).toNumber();
            var inUnion = (i < unionSlices);

            for (var s = 0; s < 13; s++) {
                var y0 = (flagTop + s * stripeH).toNumber() + dy;
                var col;
                if (inUnion && s < unionStripes) {
                    col = C_BLUE;
                } else {
                    col = (s % 2 == 0) ? C_RED : C_WHITE;
                }
                dc.setColor(col, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(xs, y0, sliceW.toNumber() + 1, (stripeH + 1.5).toNumber());
            }
        }

        // White star-dots sprinkled across the canton (follow the union's wave).
        var uw = unionSlices * sliceW;
        var uh = (unionStripes * stripeH).toNumber();
        var udy = (1.5 * Math.sin(0.9 - phase)).toNumber();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        var cols = 4;
        var rows = 3;
        for (var rr = 0; rr < rows; rr++) {
            for (var cc = 0; cc < cols; cc++) {
                var stxf = flagX + (uw * (cc + 0.7) / (cols + 0.4));
                var styf = flagTop + udy + (uh * (rr + 0.7) / (rows + 0.4));
                dc.fillCircle(stxf.toNumber(), styf.toNumber(), 1);
            }
        }
    }

    // ------------------------------------------------------------ Grand Finale
    //
    // Patriotic bunting: a row of scalloped red/white/blue drapes across the top.
    private function drawBunting(dc as Dc, w as Number, h as Number) as Void {
        var colors = [C_RED, C_WHITE, C_BLUE] as Array<Number>;
        var n = 7;
        var span = w.toFloat() / n;
        var topY = (h * 0.02).toNumber();
        var dip = (h * 0.06).toNumber();
        for (var i = 0; i < n; i++) {
            var x0 = (i * span).toNumber();
            var x1 = ((i + 1) * span).toNumber();
            var xm = ((x0 + x1) / 2);
            var c = colors[i % colors.size()];
            // A drape: a downward-bulging quad approximated with a 5-point polygon.
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [x0, topY],
                [x1, topY],
                [x1, topY + (dip * 0.4).toNumber()],
                [xm, topY + dip],
                [x0, topY + (dip * 0.4).toNumber()]
            ] as Array<Array>);
            // Gold pin at each junction
            dc.setColor(0xFFD23F, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0, topY, 2);
        }
        dc.setColor(0xFFD23F, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(w, topY, 2);
    }

    // A small biplane sweeping across the upper sky, trailing a star-spangled
    // pennant. Appears once every PLANE_PERIOD seconds for PLANE_FLIGHT seconds.
    private function drawPlaneFlyover(dc as Dc, w as Number, h as Number, hour as Number, min as Number, sec as Number) as Void {
        var secOfDay = hour * 3600 + min * 60 + sec;
        var cyclePos = secOfDay % PLANE_PERIOD;
        if (cyclePos >= PLANE_FLIGHT) { return; }

        var p = cyclePos.toFloat() / PLANE_FLIGHT.toFloat();    // 0..1 across screen
        var margin = (w * 0.30).toNumber();
        var x = (-margin + p * (w + 2 * margin)).toNumber();
        var baseY = (h * 0.16).toNumber();
        var y = baseY + (h * 0.025 * Math.sin(p * Math.PI * 3.0)).toNumber();

        drawBiplane(dc, x, y, sec);
    }

    private function drawBiplane(dc as Dc, x as Number, y as Number, sec as Number) as Void {
        var s = mWidth / 280.0;
        if (s < 0.7) { s = 0.7; }

        // Star-spangled pennant streaming behind (to the left).
        var bandColors = [C_RED, C_WHITE, C_BLUE] as Array<Number>;
        for (var i = 0; i < 9; i++) {
            var bx = (x - (12 + i * 7) * s).toNumber();
            var by = (y + (4.0 * Math.sin(sec.toFloat() * 0.6 + i * 0.7)) * s).toNumber();
            dc.setColor(bandColors[i % bandColors.size()], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, by, (5 * s).toNumber(), (3 * s).toNumber());
        }

        // Fuselage
        dc.setColor(0xD8DCE2, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - 8 * s).toNumber(), (y - 2 * s).toNumber(), (18 * s).toNumber(), (5 * s).toNumber(), (2 * s).toNumber());
        // Tail fin
        dc.fillPolygon([
            [(x - 8 * s).toNumber(), (y - 1 * s).toNumber()],
            [(x - 12 * s).toNumber(), (y - 5 * s).toNumber()],
            [(x - 7 * s).toNumber(), (y - 1 * s).toNumber()]
        ] as Array<Array>);
        // Stacked wings (biplane)
        dc.setColor(0xB22234, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle((x - 4 * s).toNumber(), (y - 6 * s).toNumber(), (12 * s).toNumber(), (2 * s).toNumber());
        dc.fillRectangle((x - 4 * s).toNumber(), (y + 2 * s).toNumber(), (12 * s).toNumber(), (2 * s).toNumber());
        dc.setColor(0x9AA0A6, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((s > 1.0) ? 2 : 1);
        dc.drawLine((x + 2 * s).toNumber(), (y - 4 * s).toNumber(), (x + 2 * s).toNumber(), (y + 4 * s).toNumber());
        // Nose + spinning prop
        dc.setColor(0x2A2A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + 10 * s).toNumber(), (y).toNumber(), (2 * s).toNumber());
        dc.setColor(0xCFCFD6, Graphics.COLOR_TRANSPARENT);
        if (sec % 2 == 0) {
            dc.drawLine((x + 10 * s).toNumber(), (y - 5 * s).toNumber(), (x + 10 * s).toNumber(), (y + 5 * s).toNumber());
        } else {
            dc.drawLine((x + 6 * s).toNumber(), (y).toNumber(), (x + 14 * s).toNumber(), (y).toNumber());
        }
    }

    // America's 250th (Semiquincentennial) banner: a golden "1776 (star) 2026"
    // line with a small five-point star between the years, centered above the time.
    private function drawBirthday250(dc as Dc, cx as Number, y as Number) as Void {
        var gold = 0xFFD23F;
        var d1 = "1776";
        var d2 = "2026";
        var starHalf = (mWidth > 300) ? 8 : 6;
        var gap = starHalf + 5;

        drawTextWithOutline(dc, cx - gap, y, mFontLabel, d1,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER, gold);
        drawTextWithOutline(dc, cx + gap, y, mFontLabel, d2,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER, gold);

        // Star between the years (black outline, then gold).
        drawStarShape(dc, cx, y, (starHalf + 1).toFloat(), 0.0, 0x000000);
        drawStarShape(dc, cx, y, starHalf.toFloat(), 0.0, gold);
        dc.setColor(0xFFF3C0, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, y, 1);
    }

    // A five-pointed star seconds marker that slowly spins, outlined in black so
    // it stays legible over the time/date text and the bright sky alike.
    private function drawStarSecond(dc as Dc, sx as Number, sy as Number, sec as Number) as Void {
        var rot = sec.toFloat() * 0.4;
        // Black outline pass (a slightly larger star + backing dot).
        drawStarShape(dc, sx, sy, 8.0, rot, 0x000000);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 2);
        // Bright star on top.
        drawStarShape(dc, sx, sy, 6.5, rot, 0xFFFFFF);
        dc.setColor(C_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 2);
        dc.setPenWidth(1);
    }

    private function drawStarShape(dc as Dc, cxp as Number, cyp as Number, rOuter as Float, rot as Float, color as Number) as Void {
        var rInner = rOuter * 0.42;
        var pts = new [10] as Array<Array>;
        for (var i = 0; i < 10; i++) {
            var rad = (i % 2 == 0) ? rOuter : rInner;
            var ang = -Math.PI / 2.0 + rot + i * (Math.PI / 5.0);
            pts[i] = [(cxp + rad * Math.cos(ang)).toNumber(), (cyp + rad * Math.sin(ang)).toNumber()];
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    private function drawPatriotBezel(dc as Dc, gx as Number, gy as Number, r as Number, lit as Boolean) as Void {
        var ring      = lit ? 0xCFE0FF : 0x5A7088;
        var frost     = lit ? 0xF4F7FF : 0xC0CEDC;
        var glowColor = lit ? 0xDCEAF8 : 0x2A4E8C;

        if (lit) {
            dc.setPenWidth(4);
            dc.setColor(scaleColor(glowColor, 0.4), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
        }
        dc.setPenWidth(3);
        dc.setColor(frost, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r + 1);
        dc.setPenWidth(1);
        dc.setColor(ring, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r - 1);
    }

    // Liquid-fill globe (Body Battery / device battery complications).
    function drawGlobe(dc as Dc, gx as Number, gy as Number, r as Number,
                       value as Number, available as Boolean,
                       bright as Number, dark as Number, rim as Number, glow as Number) as Void {
        if (mLowPower) {
            drawGlobeLowPower(dc, gx, gy, r, value, available, rim);
            return;
        }

        if (available && value > 0 && !mFlatGlobes) {
            dc.setPenWidth(3);
            dc.setColor(scaleColor(glow, 0.60), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
            dc.setPenWidth(2);
            dc.setColor(scaleColor(glow, 0.30), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 5);
        }

        dc.setColor(scaleColor(dark, 0.55), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, r);

        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var fillH = (2.0 * r) * v / 100.0;
            var surfaceY = ((gy + r) - fillH).toNumber();
            var bottomY = gy + r - 1;
            var flatTop = bright;
            var flatBottom = lerpColor(bright, dark, 0.5);
            var step = 2;
            for (var y = surfaceY; y <= bottomY; y += step) {
                var half = chordHalf(r - 1, y - gy);
                if (half < 1) { continue; }
                var depth = (y - surfaceY).toFloat() / fillH;
                var c;
                if (mFlatGlobes) {
                    c = (depth < 0.55) ? flatTop : flatBottom;
                } else {
                    var tt = 1.0 - depth;
                    if (tt < 0.0) { tt = 0.0; }
                    if (tt > 1.0) { tt = 1.0; }
                    c = lerpColor(dark, bright, tt);
                }
                dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(gx - half, y, 2 * half, step);
            }

            if (fillH > r * 0.5 && !mFlatGlobes) {
                var coreY = (gy + r - fillH * 0.45).toNumber();
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.10), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.22).toNumber());
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.22), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.10).toNumber());
            }

            var mHalf = chordHalf(r, surfaceY - gy);
            if (mHalf > 1) {
                dc.setPenWidth(2);
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.35), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - mHalf, surfaceY, gx + mHalf, surfaceY);
            }
        }

        if (available) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(gx - (r * 0.34).toNumber(), gy - (r * 0.42).toNumber(), (r * 0.12).toNumber());
        }

        drawPatriotBezel(dc, gx, gy, r, (available && value > 0));
    }

    function drawGlobeLowPower(dc as Dc, gx as Number, gy as Number, r as Number,
                               value as Number, available as Boolean, rim as Number) as Void {
        dc.setPenWidth(1);
        dc.setColor(scaleColor(rim, 0.45), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r);
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var surfaceY = ((gy + r) - (2.0 * r) * v / 100.0).toNumber();
            var half = chordHalf(r, surfaceY - gy);
            if (half > 1) {
                dc.setColor(scaleColor(rim, 0.65), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - half, surfaceY, gx + half, surfaceY);
            }
        }
    }

    // Steps progress bar (red fill, white frost frame).
    function drawXpBar(dc as Dc, cx as Number, y as Number, barW as Number, barH as Number, frac as Float) as Void {
        var x = cx - barW / 2;
        var top = y - barH / 2;
        var rad = barH / 2;

        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var fw = (barW * frac).toNumber();

        if (mLowPower) {
            dc.setPenWidth(1);
            dc.setColor(scaleColor(C_XP_FILL, 0.40), Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, top, barW, barH, rad);
            if (fw > 2) {
                dc.setColor(scaleColor(C_XP_FILL, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + 2, y, x + fw - 2, y);
            }
            return;
        }

        dc.setColor(C_XP_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, top, barW, barH, rad);

        if (frac > 0.0) {
            if (fw < barH) { fw = barH; }
            if (fw > barW) { fw = barW; }
            dc.setColor(C_XP_FILL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, fw, barH, rad);
        }

        dc.setPenWidth(1);
        dc.setColor(C_XP_BORDER, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, top, barW, barH, rad);

        dc.setColor(C_XP_BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 2, y, 3);
        dc.fillCircle(x + barW + 2, y, 3);
    }

    // ------------------------------------------------------------------- Data

    function getStepFraction() as Float {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        if (info == null || info.steps == null) { return 0.0; }
        var steps = info.steps;
        var goal = mStepGoalOverride;
        if (goal <= 0) {
            if (info.stepGoal != null && info.stepGoal > 0) {
                goal = info.stepGoal;
            } else {
                goal = 10000;
            }
        }
        if (goal <= 0) { return 0.0; }
        var f = steps.toFloat() / goal.toFloat();
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    function getBodyBattery() as Number or Null {
        try {
            if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
                var iter = SensorHistory.getBodyBatteryHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.data != null) {
                        var v = sample.data.toNumber();
                        if (v < 0) { v = 0; }
                        if (v > 100) { v = 100; }
                        return v;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // Current heart rate in BPM, cached and refreshed at most once every ~10s.
    function getHeartRate() as Number or Null {
        var nowSec = Time.now().value();
        if (mCachedHr != null && (nowSec - mHrLastSec) < 10) {
            return mCachedHr;
        }
        mHrLastSec = nowSec;
        try {
            if (Toybox has :Activity) {
                var info = Activity.getActivityInfo();
                if (info != null && info.currentHeartRate != null) {
                    mCachedHr = info.currentHeartRate;
                    return mCachedHr;
                }
            }
            if ((Toybox has :ActivityMonitor) && (ActivityMonitor has :getHeartRateHistory)) {
                var it = ActivityMonitor.getHeartRateHistory(1, true);
                if (it != null) {
                    var s = it.next();
                    if (s != null && s.heartRate != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                        mCachedHr = s.heartRate;
                        return mCachedHr;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return mCachedHr;
    }

    function getDeviceBattery() as Number {
        var stats = System.getSystemStats();
        return (stats.battery != null) ? stats.battery.toNumber() : 0;
    }

    function getSteps() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.steps != null) ? info.steps : 0;
    }

    function getCalories() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.calories != null) ? info.calories : 0;
    }

    // --------------------------------------------------------- Complications

    private function drawComplication(dc as Dc, cx as Number, y as Number, opt as Number) as Void {
        if (opt == COMP_OFF) { return; }

        var valStr = "--";
        var level = -1;
        var accent = 0xFFFFFF;

        if (opt == COMP_HR) {
            var hr = getHeartRate();
            valStr = (hr != null) ? hr.format("%d") : "--";
            accent = 0xFF5A5A;            // red heart
        } else if (opt == COMP_BODY) {
            var bb = getBodyBattery();
            valStr = (bb != null) ? bb.format("%d") + "%" : "--";
            accent = 0xE6ECF6;            // silver-white bolt
        } else if (opt == COMP_BATTERY) {
            var b = getDeviceBattery();
            valStr = b.format("%d") + "%";
            level = b;
            accent = 0x7FB0FF;            // patriot blue battery
        } else if (opt == COMP_STEPS) {
            valStr = getSteps().format("%d");
            accent = 0xCFE0F0;            // pale blue boot
        } else if (opt == COMP_CALORIES) {
            valStr = getCalories().format("%d");
            accent = 0xFF8A3D;            // ember flame
        } else {
            return;
        }

        var textColor = mLowPower ? 0x6E6E6E : 0xFFFFFF;
        var iconColor = mLowPower ? 0x6E6E6E : accent;

        var textWidth = dc.getTextWidthInPixels(valStr, mFontLabel);
        var totalW = 16 + 6 + textWidth;
        var startX = cx - totalW / 2;

        drawComplicationIcon(dc, opt, startX + 8, y, iconColor, level);
        drawTextWithOutline(dc, startX + 22, y, mFontLabel, valStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER, textColor);
    }

    private function drawComplicationIcon(dc as Dc, kind as Number, x as Number, y as Number, color as Number, level as Number) as Void {
        if (kind == COMP_HR) {
            drawHeartIcon(dc, x, y, color);
        } else if (kind == COMP_BODY) {
            drawBoltIcon(dc, x, y, color);
        } else if (kind == COMP_BATTERY) {
            drawBatteryIcon(dc, x, y, color, level);
        } else if (kind == COMP_STEPS) {
            drawBootIcon(dc, x, y, color);
        } else if (kind == COMP_CALORIES) {
            drawFlameIcon(dc, x, y, color);
        }
    }

    private function drawBoltIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBoltShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x - 1, y - 1);
        drawBoltShape(dc, x + 1, y - 1);
        drawBoltShape(dc, x - 1, y + 1);
        drawBoltShape(dc, x + 1, y + 1);
        drawBoltShape(dc, x - 1, y);
        drawBoltShape(dc, x + 1, y);
        drawBoltShape(dc, x,     y - 1);
        drawBoltShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x, y);
    }

    private function drawBoltShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x + 2, y - 8], [x - 5, y + 1], [x - 1, y + 1],
            [x - 2, y + 8], [x + 5, y - 2], [x + 1, y - 2]
        ] as Array<Array>);
    }

    private function drawBootIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBootShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x - 1, y - 1);
        drawBootShape(dc, x + 1, y - 1);
        drawBootShape(dc, x - 1, y + 1);
        drawBootShape(dc, x + 1, y + 1);
        drawBootShape(dc, x - 1, y);
        drawBootShape(dc, x + 1, y);
        drawBootShape(dc, x,     y - 1);
        drawBootShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x, y);
    }

    private function drawBootShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillRoundedRectangle(x - 4, y - 7, 6, 10, 2);  // leg
        dc.fillRoundedRectangle(x - 4, y + 1, 11, 4, 2);  // foot
    }

    private function drawFlameIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawFlameShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x - 1, y - 1);
        drawFlameShape(dc, x + 1, y - 1);
        drawFlameShape(dc, x - 1, y + 1);
        drawFlameShape(dc, x + 1, y + 1);
        drawFlameShape(dc, x - 1, y);
        drawFlameShape(dc, x + 1, y);
        drawFlameShape(dc, x,     y - 1);
        drawFlameShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x, y);
    }

    private function drawFlameShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x, y - 8], [x + 5, y - 1], [x + 4, y + 4], [x - 4, y + 4], [x - 5, y - 1]
        ] as Array<Array>);
        dc.fillCircle(x, y + 2, 4);
    }

    // -------------------------------------------------------------- Critters
    //
    // Occasional field visitors that cross the screen once in a while. At most ONE
    // is ever active. Everything is deterministic from the clock (no RNG, no
    // state), and critters are only drawn in the active layer (never low-power/AOD)
    // so they never touch the partial-update budget. Each creature is outlined by
    // drawing its silhouette 4x at +/-1 diagonal offsets in black, then once in
    // colour, to stay legible over the bright field and dark sky alike.

    private function computeCritter(hour as Number, min as Number, sec as Number, isNight as Boolean) as Array or Null {
        var PERIOD = 38.0;
        var CROSS  = 8.0;

        var tDay = (hour * 3600 + min * 60 + sec).toFloat();
        var period = (tDay / PERIOD).toNumber();
        var local = tDay - period * PERIOD;

        if (period % 5 == 0) { return null; }   // quiet window
        if (local >= CROSS) { return null; }

        var frac = local / CROSS;               // 0..1 across the screen
        var dir = ((period * 31 + 7) % 2 == 0) ? 1 : -1;
        var sel = (period * 17 + 5) % 4;

        var type;
        if (isNight) {
            var nightPool = [CR_OWL, CR_FOX, CR_RACCOON, CR_BAT] as Array<Number>;
            type = nightPool[sel];
        } else {
            var dayPool = [CR_EAGLE, CR_DEER, CR_RABBIT, CR_BUTTERFLY] as Array<Number>;
            type = dayPool[sel];
        }
        return [type, dir, frac, period] as Array;
    }

    private function isSkyCritter(type as Number) as Boolean {
        return type == CR_EAGLE || type == CR_BUTTERFLY || type == CR_OWL || type == CR_BAT;
    }

    private function drawCritter(dc as Dc, crit as Array) as Void {
        var w = mWidth;
        var h = mHeight;
        var type = crit[0] as Number;
        var dir = crit[1] as Number;
        var frac = crit[2] as Float;

        var margin = (w * 0.18).toNumber();
        var span = w + 2 * margin;
        var x;
        if (dir == 1) {
            x = (-margin + frac * span).toNumber();
        } else {
            x = (w + margin - frac * span).toNumber();
        }

        var groundY = (h * 0.92).toNumber();

        if (type == CR_EAGLE) {
            var y = (h * 0.20).toNumber() + (h * 0.04 * Math.sin(frac * Math.PI * 2.0)).toNumber();
            drawEagle(dc, x, y, dir, Math.sin(frac * Math.PI * 3.0), (w * 0.06).toNumber());
        } else if (type == CR_BUTTERFLY) {
            var y = (h * 0.30).toNumber() + (h * 0.10 * Math.sin(frac * Math.PI * 6.0)).toNumber();
            drawButterfly(dc, x, y, dir, frac, (w * 0.022).toNumber());
        } else if (type == CR_OWL) {
            var y = (h * 0.20).toNumber() + (h * 0.03 * Math.sin(frac * Math.PI * 2.0)).toNumber();
            drawOwl(dc, x, y, dir, Math.sin(frac * Math.PI * 4.0), (w * 0.055).toNumber());
        } else if (type == CR_BAT) {
            var y = (h * 0.22).toNumber() + (h * 0.06 * Math.sin(frac * Math.PI * 7.0)).toNumber();
            drawBat(dc, x, y, dir, Math.sin(frac * Math.PI * 12.0), (w * 0.03).toNumber());
        } else if (type == CR_RABBIT) {
            var sv = Math.sin(frac * Math.PI * 7.0);
            if (sv < 0.0) { sv = -sv; }
            var y = (groundY - (h * 0.05) * sv).toNumber();
            drawRabbit(dc, x, y, dir, (w * 0.04).toNumber());
        } else if (type == CR_FOX) {
            var y = groundY;
            var pounce = false;
            if (frac > 0.4 && frac < 0.6) {
                var pf = (frac - 0.4) / 0.2;
                y = (groundY - (h * 0.06) * Math.sin(pf * Math.PI)).toNumber();
                pounce = true;
            }
            drawFoxFamily(dc, x, y, dir, pounce, (w * 0.05).toNumber(), 0xE0662A, 0xF4ECE0, 0x2A1A12);
        } else if (type == CR_RACCOON) {
            drawRaccoon(dc, x, groundY, dir, (w * 0.045).toNumber());
        } else if (type == CR_DEER) {
            drawStag(dc, x, groundY, dir, frac, (w * 0.06).toNumber());
        }
    }

    // ---- Bald eagle (soars across the sky) ----
    private function drawEagle(dc as Dc, x as Number, y as Number, dir as Number, flap as Float, s as Number) as Void {
        if (s < 10) { s = 10; }
        eagleSil(dc, x - 1, y - 1, dir, s, flap, 0x000000);
        eagleSil(dc, x + 1, y - 1, dir, s, flap, 0x000000);
        eagleSil(dc, x - 1, y + 1, dir, s, flap, 0x000000);
        eagleSil(dc, x + 1, y + 1, dir, s, flap, 0x000000);
        eagleSil(dc, x, y, dir, s, flap, 0x3A2A1A);          // dark brown body

        // White head + tail
        dc.setColor(0xF4F7FF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.95).toNumber(), (y - s * 0.1).toNumber(), (s * 0.26).toNumber());  // head
        dc.fillPolygon([                                     // white tail
            [(x - dir * s * 0.7).toNumber(), (y - s * 0.1).toNumber()],
            [(x - dir * s * 1.15).toNumber(), (y + s * 0.05).toNumber()],
            [(x - dir * s * 0.7).toNumber(), (y + s * 0.2).toNumber()]
        ] as Array<Array>);
        dc.setColor(0xF2B03A, Graphics.COLOR_TRANSPARENT);   // gold beak
        dc.fillPolygon([
            [(x + dir * s * 1.15).toNumber(), (y - s * 0.1).toNumber()],
            [(x + dir * s * 1.4).toNumber(), (y).toNumber()],
            [(x + dir * s * 1.15).toNumber(), (y + s * 0.08).toNumber()]
        ] as Array<Array>);
    }

    private function eagleSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, flap as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.7).toNumber(), (y - s * 0.2).toNumber(), (s * 1.5).toNumber(), (s * 0.45).toNumber(), (s * 0.2).toNumber());  // body
        var tip = (flap * s * 0.7);                          // broad soaring wings
        dc.fillPolygon([
            [x, (y - s * 0.1).toNumber()],
            [(x - dir * s * 1.7).toNumber(), (y - s * 0.5 - tip).toNumber()],
            [(x - dir * s * 0.4).toNumber(), (y + s * 0.15).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [x, (y - s * 0.1).toNumber()],
            [(x + dir * s * 1.7).toNumber(), (y - s * 0.5 - tip).toNumber()],
            [(x + dir * s * 0.4).toNumber(), (y + s * 0.15).toNumber()]
        ] as Array<Array>);
    }

    // ---- Butterfly (flutters across the sky) ----
    private function drawButterfly(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 4) { s = 4; }
        var wingOpen = 0.5 + 0.5 * Math.sin(frac * Math.PI * 18.0);   // flap
        var ww = (s * (0.5 + wingOpen)).toNumber();
        // Body
        dc.setColor(0x2A2A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 1, y - s, 2, (s * 2).toNumber(), 1);
        // Wings (red upper, blue lower) on both sides
        dc.setColor(C_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - ww, y - (s * 0.4).toNumber(), (s * 0.7).toNumber());
        dc.fillCircle(x + ww, y - (s * 0.4).toNumber(), (s * 0.7).toNumber());
        dc.setColor(C_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - ww, y + (s * 0.5).toNumber(), (s * 0.55).toNumber());
        dc.fillCircle(x + ww, y + (s * 0.5).toNumber(), (s * 0.55).toNumber());
        // White dots
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - ww, y - (s * 0.4).toNumber(), 1);
        dc.fillCircle(x + ww, y - (s * 0.4).toNumber(), 1);
    }

    // ---- Bat (darts across the night sky) ----
    private function drawBat(dc as Dc, x as Number, y as Number, dir as Number, flap as Float, s as Number) as Void {
        if (s < 5) { s = 5; }
        var tip = (flap * s * 0.6);
        dc.setColor(0x14121C, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, (s * 0.4).toNumber());           // body
        // ears
        dc.fillPolygon([[x - s * 0.2, y - s * 0.3], [x - s * 0.35, y - s * 0.7], [x, y - s * 0.35]] as Array<Array>);
        dc.fillPolygon([[x + s * 0.2, y - s * 0.3], [x + s * 0.35, y - s * 0.7], [x, y - s * 0.35]] as Array<Array>);
        // wings (scalloped triangles)
        dc.fillPolygon([
            [x, y],
            [(x - s * 1.6).toNumber(), (y - s * 0.4 - tip).toNumber()],
            [(x - s * 0.9).toNumber(), (y + s * 0.3).toNumber()],
            [(x - s * 0.4).toNumber(), (y + s * 0.1).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [x, y],
            [(x + s * 1.6).toNumber(), (y - s * 0.4 - tip).toNumber()],
            [(x + s * 0.9).toNumber(), (y + s * 0.3).toNumber()],
            [(x + s * 0.4).toNumber(), (y + s * 0.1).toNumber()]
        ] as Array<Array>);
    }

    // ---- Owl (glides across the night sky) ----
    private function drawOwl(dc as Dc, x as Number, y as Number, dir as Number, flap as Float, s as Number) as Void {
        if (s < 9) { s = 9; }
        owlSil(dc, x - 1, y - 1, dir, s, flap, 0x000000);
        owlSil(dc, x + 1, y - 1, dir, s, flap, 0x000000);
        owlSil(dc, x - 1, y + 1, dir, s, flap, 0x000000);
        owlSil(dc, x + 1, y + 1, dir, s, flap, 0x000000);
        owlSil(dc, x, y, dir, s, flap, 0x6B4A2E);            // brown owl

        var hy = (y - s * 0.7).toNumber();
        dc.setColor(0xF2C03A, Graphics.COLOR_TRANSPARENT);   // big yellow eyes
        dc.fillCircle((x - s * 0.22).toNumber(), hy, (s * 0.14).toNumber());
        dc.fillCircle((x + s * 0.22).toNumber(), hy, (s * 0.14).toNumber());
        dc.setColor(0x1A1410, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 0.22).toNumber(), hy, (s * 0.06).toNumber() + 1);
        dc.fillCircle((x + s * 0.22).toNumber(), hy, (s * 0.06).toNumber() + 1);
        dc.setColor(0xF2A03A, Graphics.COLOR_TRANSPARENT);   // beak
        dc.fillPolygon([
            [x, (hy + s * 0.12).toNumber()],
            [(x - s * 0.08).toNumber(), (hy + s * 0.32).toNumber()],
            [(x + s * 0.08).toNumber(), (hy + s * 0.32).toNumber()]
        ] as Array<Array>);
    }

    private function owlSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, flap as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.5).toNumber(), (y - s * 0.4).toNumber(), (s * 1.0).toNumber(), (s * 1.1).toNumber(), (s * 0.4).toNumber());  // body
        dc.fillCircle(x, (y - s * 0.7).toNumber(), (s * 0.55).toNumber());   // round head
        var tip = (flap * s * 0.5);
        dc.fillPolygon([
            [x, (y - s * 0.2).toNumber()],
            [(x - s * 1.4).toNumber(), (y - s * 0.1 + tip).toNumber()],
            [(x - s * 0.3).toNumber(), (y + s * 0.4).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [x, (y - s * 0.2).toNumber()],
            [(x + s * 1.4).toNumber(), (y - s * 0.1 + tip).toNumber()],
            [(x + s * 0.3).toNumber(), (y + s * 0.4).toNumber()]
        ] as Array<Array>);
    }

    // ---- Cottontail rabbit (bounds across the field) ----
    private function drawRabbit(dc as Dc, x as Number, y as Number, dir as Number, s as Number) as Void {
        if (s < 8) { s = 8; }
        hareSil(dc, x - 1, y - 1, dir, s, 0x000000);
        hareSil(dc, x + 1, y - 1, dir, s, 0x000000);
        hareSil(dc, x - 1, y + 1, dir, s, 0x000000);
        hareSil(dc, x + 1, y + 1, dir, s, 0x000000);
        hareSil(dc, x, y, dir, s, 0x8A6A4A);                 // brown coat

        var hx = (x + dir * s * 0.7).toNumber();
        var hy = (y - s * 0.3).toNumber();
        dc.setColor(0x2A2A30, Graphics.COLOR_TRANSPARENT);   // eye
        dc.fillCircle(hx, hy, 1);
        dc.setColor(0xE6849A, Graphics.COLOR_TRANSPARENT);   // nose
        dc.fillCircle((hx + dir * s * 0.3).toNumber(), (hy + s * 0.15).toNumber(), 1);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);   // cotton tail
        dc.fillCircle((x - dir * s * 0.95).toNumber(), (y - s * 0.05).toNumber(), (s * 0.22).toNumber());
    }

    private function hareSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.8).toNumber(), (y - s * 0.5).toNumber(), (s * 1.5).toNumber(), (s * 0.8).toNumber(), (s * 0.4).toNumber());  // body
        dc.fillCircle((x - dir * s * 0.5).toNumber(), (y - s * 0.1).toNumber(), (s * 0.45).toNumber());   // haunch
        dc.fillCircle((x + dir * s * 0.7).toNumber(), (y - s * 0.3).toNumber(), (s * 0.35).toNumber());   // head
        var ex = (x + dir * s * 0.6).toNumber();             // two long ears
        var ey = (y - s * 0.55).toNumber();
        dc.fillRoundedRectangle((ex - dir * s * 0.1).toNumber(), (ey - s * 0.7).toNumber(), (s * 0.18).toNumber(), (s * 0.8).toNumber(), (s * 0.09).toNumber());
        dc.fillRoundedRectangle((ex - dir * s * 0.35).toNumber(), (ey - s * 0.65).toNumber(), (s * 0.18).toNumber(), (s * 0.8).toNumber(), (s * 0.09).toNumber());
        dc.fillRoundedRectangle((x + dir * s * 0.3).toNumber(), (y + s * 0.15).toNumber(), (s * 0.5).toNumber(), (s * 0.2).toNumber(), (s * 0.1).toNumber());   // tucked feet
    }

    // ---- Fox (red fox; palette-driven, also used as the raccoon base) ----
    private function drawFoxFamily(dc as Dc, x as Number, y as Number, dir as Number, pounce as Boolean, s as Number, body as Number, belly as Number, sock as Number) as Void {
        if (s < 8) { s = 8; }
        foxSil(dc, x - 1, y - 1, dir, s, pounce, 0x000000);
        foxSil(dc, x + 1, y - 1, dir, s, pounce, 0x000000);
        foxSil(dc, x - 1, y + 1, dir, s, pounce, 0x000000);
        foxSil(dc, x + 1, y + 1, dir, s, pounce, 0x000000);
        foxSil(dc, x, y, dir, s, pounce, body);

        dc.setColor(belly, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.95).toNumber(), (y - s * 0.1).toNumber(), (s * 0.2).toNumber());   // cheek/chest
        dc.fillCircle((x - dir * s * 1.5).toNumber(), (y - s * 0.45).toNumber(), (s * 0.22).toNumber());  // tail tip
        dc.setColor(sock, Graphics.COLOR_TRANSPARENT);
        var hx = (x + dir * s * 1.2).toNumber();
        var hy = (y - s * 0.25).toNumber();
        dc.fillCircle((hx + dir * s * 0.1).toNumber(), (hy + s * 0.12).toNumber(), 1);   // nose
        dc.fillCircle((hx - dir * s * 0.2).toNumber(), (hy - s * 0.05).toNumber(), 1);   // eye
    }

    private function foxSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, pounce as Boolean, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.9).toNumber(), (y - s * 0.35).toNumber(), (s * 1.9).toNumber(), (s * 0.7).toNumber(), (s * 0.3).toNumber());  // body
        dc.setPenWidth((s > 12) ? 3 : 2);                    // legs (tucked during a pounce)
        var legLen = pounce ? 0.35 : 0.6;
        var legY2 = (y + s * legLen).toNumber();
        dc.drawLine((x + dir * s * 0.65).toNumber(), (y + s * 0.2).toNumber(), (x + dir * s * 0.65).toNumber(), legY2);
        dc.drawLine((x + dir * s * 0.2).toNumber(),  (y + s * 0.2).toNumber(), (x + dir * s * 0.2).toNumber(),  legY2);
        dc.drawLine((x - dir * s * 0.2).toNumber(),  (y + s * 0.2).toNumber(), (x - dir * s * 0.2).toNumber(),  legY2);
        dc.drawLine((x - dir * s * 0.65).toNumber(), (y + s * 0.2).toNumber(), (x - dir * s * 0.65).toNumber(), legY2);
        dc.setPenWidth(1);
        dc.fillPolygon([                                     // neck + head (snout)
            [(x + dir * s * 0.6).toNumber(),  (y - s * 0.3).toNumber()],
            [(x + dir * s * 1.35).toNumber(), (y - s * 0.35).toNumber()],
            [(x + dir * s * 1.25).toNumber(), (y).toNumber()],
            [(x + dir * s * 0.6).toNumber(),  (y + s * 0.1).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([                                     // ears
            [(x + dir * s * 0.75).toNumber(), (y - s * 0.3).toNumber()],
            [(x + dir * s * 0.7).toNumber(),  (y - s * 0.8).toNumber()],
            [(x + dir * s * 1.0).toNumber(),  (y - s * 0.35).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(x + dir * s * 1.0).toNumber(),  (y - s * 0.3).toNumber()],
            [(x + dir * s * 1.05).toNumber(), (y - s * 0.8).toNumber()],
            [(x + dir * s * 1.25).toNumber(), (y - s * 0.35).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([                                     // bushy tail
            [(x - dir * s * 0.7).toNumber(), (y - s * 0.2).toNumber()],
            [(x - dir * s * 1.7).toNumber(), (y - s * 0.6).toNumber()],
            [(x - dir * s * 1.5).toNumber(), (y + s * 0.1).toNumber()],
            [(x - dir * s * 0.7).toNumber(), (y + s * 0.2).toNumber()]
        ] as Array<Array>);
    }

    // ---- Raccoon (grey body, black mask, ringed tail) ----
    private function drawRaccoon(dc as Dc, x as Number, y as Number, dir as Number, s as Number) as Void {
        if (s < 8) { s = 8; }
        foxSil(dc, x - 1, y - 1, dir, s, false, 0x000000);
        foxSil(dc, x + 1, y - 1, dir, s, false, 0x000000);
        foxSil(dc, x - 1, y + 1, dir, s, false, 0x000000);
        foxSil(dc, x + 1, y + 1, dir, s, false, 0x000000);
        foxSil(dc, x, y, dir, s, false, 0x8A8F99);           // grey body

        // Black face mask
        var hx = (x + dir * s * 1.1).toNumber();
        var hy = (y - s * 0.2).toNumber();
        dc.setColor(0x1A1A1E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(hx, hy, (s * 0.22).toNumber());
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);   // eye glint
        dc.fillCircle((hx - dir * s * 0.05).toNumber(), (hy - s * 0.05).toNumber(), 1);
        // Ringed tail: alternating dark bands on the bushy tail
        dc.setColor(0x2A2A2E, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 3; i++) {
            var rx = (x - dir * s * (0.9 + i * 0.3)).toNumber();
            var ry = (y - s * (0.2 + i * 0.15)).toNumber();
            dc.fillCircle(rx, ry, (s * 0.13).toNumber());
        }
    }

    // ---- Stag / deer (antlered; walks across the field) ----
    private function drawStag(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 10) { s = 10; }
        stagSil(dc, x - 1, y - 1, dir, s, 0x000000);
        stagSil(dc, x + 1, y - 1, dir, s, 0x000000);
        stagSil(dc, x - 1, y + 1, dir, s, 0x000000);
        stagSil(dc, x + 1, y + 1, dir, s, 0x000000);
        stagSil(dc, x, y, dir, s, 0x8B5A2E);                 // warm brown coat

        dc.setColor(0xE8D8B8, Graphics.COLOR_TRANSPARENT);   // pale rump
        dc.fillCircle((x - dir * s * 0.8).toNumber(), (y - s * 0.05).toNumber(), (s * 0.18).toNumber());
    }

    private function stagSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.85).toNumber(), (y - s * 0.4).toNumber(), (s * 1.7).toNumber(), (s * 0.7).toNumber(), (s * 0.25).toNumber());  // body
        dc.setPenWidth((s > 12) ? 3 : 2);                    // long slender legs
        var legY2 = (y + s * 0.85).toNumber();
        dc.drawLine((x + dir * s * 0.6).toNumber(),  (y + s * 0.2).toNumber(), (x + dir * s * 0.6).toNumber(),  legY2);
        dc.drawLine((x + dir * s * 0.25).toNumber(), (y + s * 0.2).toNumber(), (x + dir * s * 0.25).toNumber(), legY2);
        dc.drawLine((x - dir * s * 0.25).toNumber(), (y + s * 0.2).toNumber(), (x - dir * s * 0.25).toNumber(), legY2);
        dc.drawLine((x - dir * s * 0.6).toNumber(),  (y + s * 0.2).toNumber(), (x - dir * s * 0.6).toNumber(),  legY2);
        dc.setPenWidth(1);
        dc.fillPolygon([                                     // neck (up-forward)
            [(x + dir * s * 0.55).toNumber(), (y - s * 0.35).toNumber()],
            [(x + dir * s * 1.1).toNumber(),  (y - s * 1.0).toNumber()],
            [(x + dir * s * 1.35).toNumber(), (y - s * 0.9).toNumber()],
            [(x + dir * s * 0.85).toNumber(), (y - s * 0.2).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([                                     // head/muzzle
            [(x + dir * s * 1.1).toNumber(),  (y - s * 1.05).toNumber()],
            [(x + dir * s * 1.7).toNumber(),  (y - s * 0.95).toNumber()],
            [(x + dir * s * 1.35).toNumber(), (y - s * 0.75).toNumber()]
        ] as Array<Array>);
        dc.setPenWidth((s > 12) ? 3 : 2);                    // branching antlers
        var ax = (x + dir * s * 1.15).toNumber();
        var ay = (y - s * 1.05).toNumber();
        dc.drawLine(ax, ay, (ax - dir * s * 0.1).toNumber(), (ay - s * 0.8).toNumber());
        dc.drawLine((ax - dir * s * 0.1).toNumber(), (ay - s * 0.4).toNumber(), (ax + dir * s * 0.3).toNumber(), (ay - s * 0.6).toNumber());
        dc.drawLine((ax - dir * s * 0.1).toNumber(), (ay - s * 0.8).toNumber(), (ax + dir * s * 0.25).toNumber(), (ay - s * 1.0).toNumber());
        dc.drawLine((ax + dir * s * 0.2).toNumber(), ay, (ax + dir * s * 0.35).toNumber(), (ay - s * 0.7).toNumber());
        dc.drawLine((ax + dir * s * 0.35).toNumber(), (ay - s * 0.35).toNumber(), (ax + dir * s * 0.7).toNumber(), (ay - s * 0.5).toNumber());
        dc.setPenWidth(1);
        dc.fillPolygon([                                     // short tail
            [(x - dir * s * 0.8).toNumber(),  (y - s * 0.3).toNumber()],
            [(x - dir * s * 1.05).toNumber(), (y - s * 0.1).toNumber()],
            [(x - dir * s * 0.8).toNumber(),  (y + s * 0.05).toNumber()]
        ] as Array<Array>);
    }

    // ----------------------------------------------------------- Sun times

    private function updateSunTimes() as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var doy = dayOfYear(info.year, info.month, info.day);
        if (doy == mSunDay && mSunValid) { return; }
        if (doy != mSunDay) {
            mSunDay = doy;
            mSunrise = 6.0;
            mSunset = 20.5;
            mSunValid = false;
            mSunLastTry = -10000;
        }
        var nowSec = Time.now().value();
        if ((nowSec - mSunLastTry) < 60) { return; }
        mSunLastTry = nowSec;
        var loc = getLocationDeg();
        if (loc == null) { return; }
        var offset = System.getClockTime().timeZoneOffset.toFloat() / 3600.0;
        var sr = computeSunEvent(doy, loc[0], loc[1], offset, true);
        var ss = computeSunEvent(doy, loc[0], loc[1], offset, false);
        if (sr != null && ss != null && ss > sr) {
            mSunrise = sr;
            mSunset = ss;
            mSunValid = true;
        }
    }

    private function getLocationDeg() as Array<Float> or Null {
        try {
            if (Toybox has :Activity) {
                var ai = Activity.getActivityInfo();
                if (ai != null && ai.currentLocation != null) {
                    var d = ai.currentLocation.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        try {
            if (Toybox has :Weather) {
                var cc = Weather.getCurrentConditions();
                if (cc != null && cc.observationLocationPosition != null) {
                    var d = cc.observationLocationPosition.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        return null;
    }

    private function computeSunEvent(n as Number, lat as Float, lng as Float, offset as Float, sunrise as Boolean) as Float or Null {
        var ZENITH = 90.833;
        var D2R = Math.PI / 180.0;
        var R2D = 180.0 / Math.PI;

        var lngHour = lng / 15.0;
        var tt = sunrise ? (n + ((6.0 - lngHour) / 24.0)) : (n + ((18.0 - lngHour) / 24.0));

        var m = (0.9856 * tt) - 3.289;
        var l = m + (1.916 * Math.sin(m * D2R)) + (0.020 * Math.sin(2.0 * m * D2R)) + 282.634;
        l = normDeg(l);

        var ra = Math.atan(0.91764 * Math.tan(l * D2R)) * R2D;
        ra = normDeg(ra);
        var lQuad = (Math.floor(l / 90.0) * 90.0).toFloat();
        var raQuad = (Math.floor(ra / 90.0) * 90.0).toFloat();
        ra = ra + (lQuad - raQuad);
        ra = ra / 15.0;

        var sinDec = 0.39782 * Math.sin(l * D2R);
        var cosDec = Math.cos(Math.asin(sinDec));

        var cosH = (Math.cos(ZENITH * D2R) - (sinDec * Math.sin(lat * D2R))) / (cosDec * Math.cos(lat * D2R));
        if (cosH > 1.0 || cosH < -1.0) { return null; }

        var bigH = sunrise ? (360.0 - (Math.acos(cosH) * R2D)) : (Math.acos(cosH) * R2D);
        bigH = bigH / 15.0;

        var bigT = bigH + ra - (0.06571 * tt) - 6.622;
        var ut = normHour(bigT - lngHour);
        return normHour(ut + offset);
    }

    private function dayOfYear(year as Number, month as Number, day as Number) as Number {
        var cum = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334] as Array<Number>;
        var n = cum[month - 1] + day;
        if (month > 2 && isLeapYear(year)) { n += 1; }
        return n;
    }

    private function isLeapYear(y as Number) as Boolean {
        return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    }

    private function normDeg(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }
        var r = a - 360.0 * Math.floor(a / 360.0);
        if (r < 0.0) { r += 360.0; }
        if (r >= 360.0) { r -= 360.0; }
        return r;
    }

    private function normHour(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }
        var r = a - 24.0 * Math.floor(a / 24.0);
        if (r < 0.0) { r += 24.0; }
        if (r >= 24.0) { r -= 24.0; }
        return r;
    }

    // ------------------------------------------------------------ Color helpers

    function chordHalf(r as Number, dy as Number) as Number {
        var d = r * r - dy * dy;
        if (d <= 0) { return 0; }
        return Math.sqrt(d).toNumber();
    }

    function lerpColor(c1 as Number, c2 as Number, t as Float) as Number {
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }
        var r1 = (c1 >> 16) & 0xFF;
        var g1 = (c1 >> 8) & 0xFF;
        var b1 = c1 & 0xFF;
        var r2 = (c2 >> 16) & 0xFF;
        var g2 = (c2 >> 8) & 0xFF;
        var b2 = c2 & 0xFF;
        var r = (r1 + ((r2 - r1) * t)).toNumber();
        var g = (g1 + ((g2 - g1) * t)).toNumber();
        var b = (b1 + ((b2 - b1) * t)).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    function scaleColor(c as Number, f as Float) as Number {
        return lerpColor(0x000000, c, f);
    }

    // Smoothly calculate the summer sky colors based on hour of day: warm dawn,
    // bright blue midday, golden hour, a fiery sunset, then deep night.
    private function getSkyColors(hour as Number, min as Number) as Array<Number> {
        var t = hour.toFloat() + min.toFloat() / 60.0;

        var sr = mSunrise;
        var ss = mSunset;
        var hours;
        var topColors;
        var bottomColors;

        if (sr > 1.6 && ss < 22.4 && (ss - sr) > 4.0) {
            var mid = (sr + ss) / 2.0;
            hours        = [0.0, sr - 1.5, sr, sr + 1.5, mid, ss - 1.5, ss, ss + 1.5, 24.0];
            topColors    = SKY_TOP_REAL;
            bottomColors = SKY_BOTTOM_REAL;
        } else {
            hours        = SKY_HOURS_FB;
            topColors    = SKY_TOP_FB;
            bottomColors = SKY_BOTTOM_FB;
        }

        var idx = 0;
        for (var i = 0; i < hours.size() - 1; i++) {
            if (t >= hours[i] && t < hours[i+1]) {
                idx = i;
                break;
            }
        }

        var frac = (t - hours[idx]) / (hours[idx+1] - hours[idx]);
        var cTop = lerpColor(topColors[idx], topColors[idx+1], frac);
        var cBottom = lerpColor(bottomColors[idx], bottomColors[idx+1], frac);

        return [cTop, cBottom] as Array<Number>;
    }

    private function getSkyBitmap(w as Number, skyH as Number, cTop as Number, cBottom as Number) as Graphics.BufferedBitmap or Null {
        if (!(Graphics has :createBufferedBitmap)) { return null; }
        var bmp = (mSkyBufRef != null) ? mSkyBufRef.get() : null;
        if (bmp == null || w != mSkyKeyW || skyH != mSkyKeyH) {
            try {
                var ref = Graphics.createBufferedBitmap({ :width => w, :height => skyH });
                if (ref == null) { return null; }
                mSkyBufRef = ref;
                bmp = ref.get();
                if (bmp == null) { return null; }
            } catch (e) {
                mSkyBufRef = null;
                return null;
            }
            mSkyKeyW = w;
            mSkyKeyH = skyH;
            mSkyKeyTop = cTop + 1;
        }
        if (cTop != mSkyKeyTop || cBottom != mSkyKeyBottom) {
            drawSkyGradientDirect(bmp.getDc(), w, skyH, cTop, cBottom);
            mSkyKeyTop = cTop;
            mSkyKeyBottom = cBottom;
        }
        return bmp;
    }

    private function drawSkyGradientDirect(dc as Dc, w as Number, skyH as Number, cTop as Number, cBottom as Number) as Void {
        var step = 4;
        for (var y = 0; y < skyH; y += step) {
            var frac = y.toFloat() / skyH.toFloat();
            var c = lerpColor(cTop, cBottom, frac);
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, y, w, step);
        }
    }

    // ----------------------------------------------------------- Lifecycle

    function onHide() as Void {}

    function onExitSleep() as Void {
        mIsSleep = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        mIsSleep = true;
        mLastMin = -1;
        WatchUi.requestUpdate();
    }

    private function getWeatherString() as String or Null {
        try {
            if (Toybox has :Weather) {
                var conditions = Weather.getCurrentConditions();
                if (conditions != null && conditions.temperature != null) {
                    var temp = conditions.temperature;
                    var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
                    var isImperial = (settings has :temperatureUnits) && (settings.temperatureUnits != System.UNIT_METRIC);
                    if (isImperial) {
                        temp = (temp * 9.0 / 5.0 + 32.0).toNumber();
                        return temp.format("%d") + "°F";
                    } else {
                        return temp.format("%d") + "°C";
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    private function drawTextWithOutline(dc as Dc, x as Number, y as Number, font as Graphics.FontType, text as String, justify as Number, textColor as Number) as Void {
        if (mLowPower) {
            dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, text, justify);
            return;
        }
        var passes = (mQuality >= 3) ? 8 : (mQuality == 2) ? 4 : (mQuality == 1) ? 2 : 0;
        if (passes > 0) {
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            if (passes >= 4) {
                dc.drawText(x - 1, y - 1, font, text, justify);
                dc.drawText(x + 1, y - 1, font, text, justify);
                dc.drawText(x - 1, y + 1, font, text, justify);
                dc.drawText(x + 1, y + 1, font, text, justify);
            }
            if (passes >= 8) {
                dc.drawText(x - 1, y,     font, text, justify);
                dc.drawText(x + 1, y,     font, text, justify);
                dc.drawText(x,     y - 1, font, text, justify);
                dc.drawText(x,     y + 1, font, text, justify);
            } else if (passes == 2) {
                dc.drawText(x + 1, y + 1, font, text, justify);
                dc.drawText(x - 1, y - 1, font, text, justify);
            }
        }
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    private function drawHeartIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawHeartShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x - 1, y - 1);
        drawHeartShape(dc, x + 1, y - 1);
        drawHeartShape(dc, x - 1, y + 1);
        drawHeartShape(dc, x + 1, y + 1);
        drawHeartShape(dc, x - 1, y);
        drawHeartShape(dc, x + 1, y);
        drawHeartShape(dc, x,     y - 1);
        drawHeartShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x, y);
    }

    private function drawHeartShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillCircle(x - 4, y - 3, 4);
        dc.fillCircle(x + 4, y - 3, 4);
        dc.fillPolygon([[x - 8, y - 3], [x + 8, y - 3], [x, y + 7]] as Array<Array>);
    }

    private function drawBatteryIcon(dc as Dc, x as Number, y as Number, color as Number, level as Number) as Void {
        var bw = 14;
        var bh = 9;
        var left = x - bw / 2;
        var top = y - bh / 2;

        var lvl = level;
        if (lvl < 0) { lvl = 0; }
        if (lvl > 100) { lvl = 100; }

        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(left, top, bw, bh, 2);
            dc.fillRectangle(left + bw, y - 2, 2, 4);
            return;
        }

        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(left - 1, top - 1, bw + 2, bh + 2, 3);
        dc.fillRectangle(left + bw, y - 3, 4, 6);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(left, top, bw, bh, 2);
        dc.fillRectangle(left + bw, y - 2, 2, 4);

        var innerMax = bw - 4;
        var fillW = (innerMax * lvl / 100).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(left + 2, top + 2, fillW, bh - 4);
        }
    }

    // Low-power partial update, called up to once per second in sleep mode.
    function onPartialUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();
        var min = clock.min;
        if (min == mLastMin) { return; }
        mLastMin = min;

        var settings = System.getDeviceSettings();
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        var aod = hasBurnIn && mIsSleep;

        if (!aod || !(dc has :setClip)) {
            onUpdate(dc);
            return;
        }

        mLowPower = true;
        mFlatGlobes = false;
        mSettings = settings;
        mClock = clock;
        mActInfo = null;

        var shift = computeBurnInShift();
        var cx = mCenterX + shift[0];
        var cy = mCenterY + shift[1];

        var clipY = (mHeight * 0.30).toNumber();
        var clipH = (mHeight * 0.34).toNumber();
        dc.setClip(0, clipY, mWidth, clipH);

        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();
        drawTime(dc, cx, cy - (mHeight * 0.05).toNumber());
        if (mShowDate) { drawDate(dc, cx, cy + (mHeight * 0.06).toNumber()); }

        if (dc has :clearClip) { dc.clearClip(); }
    }
}
