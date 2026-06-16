# Records the running watch face from the Connect IQ simulator into a short,
# smooth preview MP4 for the Connect IQ Store "Preview Video" field
# (upload the MP4 to YouTube/Vimeo, then paste the link).
#
# A watch face only redraws ~once per second, so this captures one frame on each
# whole-second boundary and holds each one for one real second in the output --
# the video shows the face's true 1 fps cadence, exactly as it animates on the
# watch. Run it AFTER the face is deployed and animating in the sim:
#
#     ./build.ps1 -Device fenix847mm -Run      # (with SHOWCASE = true for the night show)
#     powershell.exe -ExecutionPolicy Bypass -File tools/record_preview.ps1
#
# Must run under Windows PowerShell 5.1 (the inline System.Drawing C# needs it),
# NOT pwsh 7.
param(
    [int]$Frames = 24,        # whole-second frames to capture (~ video length * 2)
    [int]$Fps = 30            # output framerate after interpolation
)

Add-Type -AssemblyName System.Drawing

$Win32Code = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;

public class Win32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hwndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public class WindowInfo {
        public IntPtr Handle { get; set; }
        public string ClassName { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public static List<WindowInfo> GetChildWindows(IntPtr parentHandle) {
        List<WindowInfo> result = new List<WindowInfo>();
        EnumChildWindows(parentHandle, (hWnd, lParam) => {
            StringBuilder className = new StringBuilder(256);
            GetClassName(hWnd, className, className.Capacity);
            RECT rect; GetWindowRect(hWnd, out rect);
            result.Add(new WindowInfo {
                Handle = hWnd, ClassName = className.ToString(),
                Left = rect.Left, Top = rect.Top,
                Width = rect.Right - rect.Left, Height = rect.Bottom - rect.Top
            });
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static Bitmap CaptureRegion(int x, int y, int width, int height) {
        Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.CopyFromScreen(x, y, 0, 0, new Size(width, height), CopyPixelOperation.SourceCopy);
        }
        return bmp;
    }

    public static Bitmap ResizeBitmap(Bitmap src, int width, int height) {
        Bitmap result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(result)) {
            g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
            g.DrawImage(src, 0, 0, width, height);
        }
        return result;
    }

    public static Bitmap ApplyCircularMask(Bitmap src) {
        int w = src.Width; int h = src.Height;
        Bitmap result = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(result)) {
            g.Clear(Color.Black);
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using (System.Drawing.Drawing2D.GraphicsPath path = new System.Drawing.Drawing2D.GraphicsPath()) {
                path.AddEllipse(0, 0, w, h);
                g.SetClip(path);
                g.DrawImage(src, 0, 0);
            }
        }
        return result;
    }
}
"@
Add-Type -TypeDefinition $Win32Code -ReferencedAssemblies System.Drawing

# --- locate the simulator + its display region (same logic as savescreenshot.ps1) ---
$process = Get-Process -Name simulator -ErrorAction SilentlyContinue
if (!$process) { Write-Error "Garmin Connect IQ Simulator is not running."; exit 1 }
$mainHandle = $process.MainWindowHandle
if ($mainHandle -eq [IntPtr]::Zero) { Write-Error "No simulator main window handle."; exit 1 }

$title = $process.MainWindowTitle
Write-Host "Simulator window: '$title'"
$devicesBaseDir = Join-Path $env:APPDATA "Garmin\ConnectIQ\Devices"
$deviceDir = $null
if ($title -like "*CIQ Simulator - *") {
    $rawDevices = ($title -split "CIQ Simulator - ")[1] -split "/"
    foreach ($rawDevice in $rawDevices) {
        $clean = ($rawDevice -split "\(")[0].Trim().ToLower() -replace "[^a-z0-9]", ""
        $candidates = @($clean, ($clean -replace "fenixr", "fenix"), ($clean -replace "fnix", "fenix"))
        foreach ($cand in $candidates) {
            $path = Join-Path $devicesBaseDir $cand
            if (Test-Path $path) { $deviceDir = $path; break }
        }
        if ($deviceDir) { break }
    }
}
if (!$deviceDir) { $deviceDir = Join-Path $devicesBaseDir "fenix847mm" }
Write-Host "Device config: $deviceDir"

$simJson = Get-Content (Join-Path $deviceDir "simulator.json") | ConvertFrom-Json
$displayLoc = $simJson.display.location
$bgImagePath = Join-Path $deviceDir $simJson.image
$bgImg = [System.Drawing.Image]::FromFile($bgImagePath)
$bgWidth = $bgImg.Width; $bgHeight = $bgImg.Height; $bgImg.Dispose()

$children = [Win32]::GetChildWindows($mainHandle)
$canvas = $children | Where-Object { $_.ClassName -eq "wxWindowNR" } | Select-Object -First 1
if (!$canvas) { Write-Error "Could not find simulator canvas (wxWindowNR)."; exit 1 }

[Win32]::ShowWindow($mainHandle, 9) | Out-Null
[Win32]::SetForegroundWindow($mainHandle) | Out-Null
Start-Sleep -Milliseconds 400

$winRect = New-Object Win32+RECT
[Win32]::GetWindowRect($mainHandle, [ref]$winRect) | Out-Null
$chromeW = ($winRect.Right - $winRect.Left) - $canvas.Width
$chromeH = ($winRect.Bottom - $winRect.Top) - $canvas.Height
[Win32]::MoveWindow($mainHandle, 80, 10, ($bgWidth + $chromeW + 8), ($bgHeight + $chromeH + 8), $true) | Out-Null
Start-Sleep -Milliseconds 600

$children = [Win32]::GetChildWindows($mainHandle)
$canvas = $children | Where-Object { $_.ClassName -eq "wxWindowNR" } | Select-Object -First 1
$capLeft = $canvas.Left + $displayLoc.x
$capTop = $canvas.Top + $displayLoc.y
$capW = $displayLoc.width
$capH = $displayLoc.height
$round = ($simJson.display.shape -eq "round")
Write-Host "Capture region: ${capLeft},${capTop} ${capW}x${capH} (round=$round)"

# --- capture one frame per whole-second boundary ---
$framesDir = Join-Path $PSScriptRoot "..\bin\preview_frames"
if (Test-Path $framesDir) { Remove-Item "$framesDir\*" -Force -ErrorAction SilentlyContinue } else { New-Item -ItemType Directory -Path $framesDir | Out-Null }

Write-Host "Capturing $Frames frames (one per second)..."
for ($i = 0; $i -lt $Frames; $i++) {
    # sleep to just past the next whole second so we grab a freshly-redrawn frame
    $ms = [DateTime]::Now.Millisecond
    Start-Sleep -Milliseconds ((1000 - $ms) + 150)
    $cap = [Win32]::CaptureRegion($capLeft, $capTop, $capW, $capH)
    $out = [Win32]::ResizeBitmap($cap, $capW, $capH)
    if ($round) { $masked = [Win32]::ApplyCircularMask($out); $out.Dispose(); $out = $masked }
    $name = "frame_{0:D3}.png" -f $i
    $out.Save((Join-Path $framesDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $cap.Dispose(); $out.Dispose()
    Write-Host ("  frame {0}/{1}" -f ($i + 1), $Frames)
}

# --- encode: TRUE to the app -- one captured second held for one real second
#     (no motion interpolation). Input at 1 fps, duplicated up to $Fps only so the
#     container plays smoothly in every player; the watch still updates once/sec. ---
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (!$ffmpeg) { $ffmpeg = "C:\ffmpeg\bin\ffmpeg.exe" }
$outMp4 = Join-Path $PSScriptRoot "..\assets\StarSpangledBanner_preview.mp4"
$vf = "scale=720:720:flags=lanczos,format=yuv420p"
Write-Host "Encoding with ffmpeg (true 1 fps cadence)..."
& $ffmpeg -y -framerate 1 -i (Join-Path $framesDir "frame_%03d.png") -vf $vf -r $Fps -c:v libx264 -crf 18 -movflags +faststart $outMp4
if ($LASTEXITCODE -ne 0) { Write-Error "ffmpeg failed ($LASTEXITCODE)."; exit $LASTEXITCODE }
Write-Host "Saved preview video: $outMp4" -ForegroundColor Green
