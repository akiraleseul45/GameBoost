# Test REEL des ecrans pour GameBoost 3.0 (a lancer par l'utilisateur, sans droits administrateur)
# Chaque ecran NON principal est eteint 3 secondes par chaque methode (veille DDC, detacher, voile noir), puis rallume.
# Resultat sur le Bureau : Test_Ecrans_GameBoost.txt
param([switch]$ASec, [string]$Sortie = '')   # -ASec : verification du script seulement (rien n'est envoye aux ecrans sauf le voile)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$cs = @'

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

// Un ecran actif : nom Windows (\\.\DISPLAYn), nom lisible, zone, mode d'affichage exact
public class GBMonInfo {
    public string Device = "", Name = "", Path = "";
    public bool Primary, Internal;
    public int X, Y, W, H, Hz, Bpp, Orient, Tech = -1;
}
// Mode d'un ecran a remettre (W = 0 : ecran detache du bureau)
public class GBMonMode {
    public string Device = "";
    public int X, Y, W, H, Hz, Bpp, Orient;
    public bool Primary;
}

public static class GBMon {
    public static bool DryRun = false;                        // test : rien n'est envoye a Windows, les appels sont notes
    public static List<string> Calls = new List<string>();

    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct MONITORINFOEX {
        public int cbSize; public RECT rcMonitor; public RECT rcWork; public int dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice; }
    delegate bool MonEnumProc(IntPtr h, IntPtr hdc, ref RECT r, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonEnumProc cb, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr h, ref MONITORINFOEX mi);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency,
        dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct DISPLAY_DEVICE { public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE dd, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW")] static extern int ChangeDisplaySettingsApply(IntPtr dev, IntPtr dm, IntPtr hwnd, int flags, IntPtr p);

    // QueryDisplayConfig : nom du modele et type de branchement (dalle interne ou non)
    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PATH_TARGET { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling;
        public uint refreshNum; public uint refreshDen; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PATH_INFO { public PATH_SOURCE src; public PATH_TARGET tgt; public uint flags; }
    [StructLayout(LayoutKind.Sequential, Size = 64)] struct MODE_INFO { public uint infoType; public uint id; public LUID adapterId; }
    [StructLayout(LayoutKind.Sequential)] struct DI_HEADER { public uint type; public uint size; public LUID adapterId; public uint id; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct SOURCE_NAME { public DI_HEADER h;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string gdi; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct TARGET_NAME { public DI_HEADER h; public uint flags; public uint tech; public ushort edidMan; public ushort edidProd; public uint connector;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string friendly; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string path; }
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint np, out uint nm);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint np, [Out] PATH_INFO[] p, ref uint nm, [Out] MODE_INFO[] m, IntPtr topo);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SOURCE_NAME r);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME r);

    // DDC/CI (dxva2) : commande d'alimentation 0xD6 de l'ecran
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 1)] struct PHYS { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string desc; }
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMon, out uint n);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMon, uint n, [Out] PHYS[] arr);
    [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint n, PHYS[] arr);
    [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, IntPtr type, out uint cur, out uint max);
    [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint val);

    const int DM_POSITION = 0x20, DM_ORIENT = 0x80, DM_BPP = 0x40000, DM_W = 0x80000, DM_H = 0x100000, DM_HZ = 0x400000;
    const int CDS_UPDATEREGISTRY = 1, CDS_SET_PRIMARY = 0x10, CDS_NORESET = 0x10000000, CDS_RESET = 0x40000000;

    // Ecrans actifs (ceux du bureau)
    public static GBMonInfo[] List() {
        List<GBMonInfo> r = new List<GBMonInfo>();
        Dictionary<string, TARGET_NAME> names = new Dictionary<string, TARGET_NAME>(StringComparer.OrdinalIgnoreCase);
        try { Targets(2, names, null); } catch { }
        List<IntPtr> hs = new List<IntPtr>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr h, IntPtr hdc, ref RECT rc, IntPtr d) { hs.Add(h); return true; }, IntPtr.Zero);
        foreach (IntPtr h in hs) {
            MONITORINFOEX mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(mi);
            if (!GetMonitorInfo(h, ref mi)) continue;
            GBMonInfo m = new GBMonInfo();
            m.Device = mi.szDevice; m.Primary = (mi.dwFlags & 1) != 0;
            m.X = mi.rcMonitor.L; m.Y = mi.rcMonitor.T; m.W = mi.rcMonitor.R - mi.rcMonitor.L; m.H = mi.rcMonitor.B - mi.rcMonitor.T;
            DEVMODE dm = NewMode();
            if (EnumDisplaySettings(m.Device, -1, ref dm)) { m.Hz = dm.dmDisplayFrequency; m.Bpp = dm.dmBitsPerPel; m.Orient = dm.dmDisplayOrientation; }
            TARGET_NAME t;
            if (names.TryGetValue(m.Device, out t)) {
                m.Name = (t.friendly ?? "").Trim(); m.Path = t.path ?? ""; m.Tech = (int)t.tech;
                m.Internal = IsInternalTech(t.tech);
            }
            r.Add(m);
        }
        return r.ToArray();
    }
    // Dalle de portable : interne, eDP (DisplayPort embarque), UDI embarque, ou LVDS (anciens portables)
    public static bool IsInternalTech(uint tech) { return tech == 0x80000000 || tech == 11 || tech == 13 || tech == 6; }

    // flags 2 = chemins actifs, 1 = tous ; available : chemins des ecrans branches (pour savoir si un ecran detache est encore la)
    static void Targets(uint flags, Dictionary<string, TARGET_NAME> byGdi, List<string> available) {
        uint np, nm;
        if (GetDisplayConfigBufferSizes(flags, out np, out nm) != 0) return;
        PATH_INFO[] paths = new PATH_INFO[np]; MODE_INFO[] modes = new MODE_INFO[nm];
        if (QueryDisplayConfig(flags, ref np, paths, ref nm, modes, IntPtr.Zero) != 0) return;
        for (int i = 0; i < np; i++) {
            TARGET_NAME t = new TARGET_NAME(); t.h.type = 2; t.h.size = (uint)Marshal.SizeOf(typeof(TARGET_NAME)); t.h.adapterId = paths[i].tgt.adapterId; t.h.id = paths[i].tgt.id;
            if (DisplayConfigGetDeviceInfo(ref t) != 0) continue;
            if (available != null && paths[i].tgt.targetAvailable != 0 && !string.IsNullOrEmpty(t.path) && !available.Contains(t.path)) available.Add(t.path);
            if (byGdi == null) continue;
            SOURCE_NAME s = new SOURCE_NAME(); s.h.type = 1; s.h.size = (uint)Marshal.SizeOf(typeof(SOURCE_NAME)); s.h.adapterId = paths[i].src.adapterId; s.h.id = paths[i].src.id;
            if (DisplayConfigGetDeviceInfo(ref s) != 0 || string.IsNullOrEmpty(s.gdi)) continue;
            if (!byGdi.ContainsKey(s.gdi)) byGdi[s.gdi] = t;
        }
    }
    // Ecran encore branche ? (chemin du moniteur connu : QueryDisplayConfig ; sinon moniteur rattache a la sortie)
    public static bool IsConnected(string dev, string path) {
        try {
            if (!string.IsNullOrEmpty(path)) {
                List<string> av = new List<string>(); Targets(1, null, av);
                foreach (string p in av) if (string.Equals(p, path, StringComparison.OrdinalIgnoreCase)) return true;
                return false;
            }
            DISPLAY_DEVICE d = new DISPLAY_DEVICE(); d.cb = Marshal.SizeOf(d);
            return EnumDisplayDevices(dev, 0, ref d, 0) && (d.StateFlags & 3) != 0;
        } catch { return true; }
    }
    // Signature rapide des ecrans actifs (pour voir un branchement / debranchement)
    public static string Signature() {
        List<string> r = new List<string>();
        foreach (Screen s in Screen.AllScreens) r.Add(s.DeviceName + "=" + s.Bounds.X + "," + s.Bounds.Y + "," + s.Bounds.Width + "x" + s.Bounds.Height + (s.Primary ? "*" : ""));
        r.Sort(StringComparer.Ordinal);
        return string.Join(";", r.ToArray());
    }

    static DEVMODE NewMode() { DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return dm; }
    // Mode actuel exact (null si l'ecran n'est pas sur le bureau)
    public static GBMonMode GetMode(string dev) {
        DEVMODE dm = NewMode();
        if (!EnumDisplaySettings(dev, -1, ref dm) || dm.dmPelsWidth <= 0) return null;
        bool active = false;
        foreach (Screen s in Screen.AllScreens) if (string.Equals(s.DeviceName, dev, StringComparison.OrdinalIgnoreCase)) active = true;
        if (!active) return null;
        GBMonMode m = new GBMonMode();
        m.Device = dev; m.X = dm.dmPositionX; m.Y = dm.dmPositionY; m.W = dm.dmPelsWidth; m.H = dm.dmPelsHeight;
        m.Hz = dm.dmDisplayFrequency; m.Bpp = dm.dmBitsPerPel; m.Orient = dm.dmDisplayOrientation;
        foreach (Screen s in Screen.AllScreens) if (s.Primary && string.Equals(s.DeviceName, dev, StringComparison.OrdinalIgnoreCase)) m.Primary = true;
        return m;
    }
    // Applique plusieurs ecrans d'un coup (W = 0 : detacher), puis un seul appel global : 0 = reussi
    public static int ApplyLayout(GBMonMode[] list) {
        int first = 0;
        foreach (GBMonMode m in list) {
            DEVMODE dm = NewMode();
            int flags = CDS_UPDATEREGISTRY | CDS_NORESET;
            if (m.W <= 0) { dm.dmFields = DM_POSITION | DM_W | DM_H; }
            else {
                dm.dmFields = DM_POSITION | DM_W | DM_H | DM_ORIENT;
                dm.dmPositionX = m.X; dm.dmPositionY = m.Y; dm.dmPelsWidth = m.W; dm.dmPelsHeight = m.H; dm.dmDisplayOrientation = m.Orient;
                if (m.Hz > 1) { dm.dmFields |= DM_HZ; dm.dmDisplayFrequency = m.Hz; }
                if (m.Bpp > 0) { dm.dmFields |= DM_BPP; dm.dmBitsPerPel = m.Bpp; }
                if (m.Primary) flags |= CDS_SET_PRIMARY;
            }
            int rc = 0;
            if (DryRun) Calls.Add("CDS " + m.Device + " fields=0x" + dm.dmFields.ToString("X") + " pos=" + dm.dmPositionX + "," + dm.dmPositionY + " size=" + dm.dmPelsWidth + "x" + dm.dmPelsHeight +
                                   " hz=" + dm.dmDisplayFrequency + " bpp=" + dm.dmBitsPerPel + " orient=" + dm.dmDisplayOrientation + " flags=0x" + flags.ToString("X"));
            else rc = ChangeDisplaySettingsEx(m.Device, ref dm, IntPtr.Zero, flags, IntPtr.Zero);
            if (rc != 0 && first == 0) first = rc;
        }
        int g = 0;
        if (DryRun) Calls.Add("CDS appliquer (global)");
        else g = ChangeDisplaySettingsApply(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        return first != 0 ? first : g;
    }
    // Remet le mode actuel tel quel (nouvelle synchro du signal : reveille un ecran reste en veille)
    public static int Resync(string dev) {
        DEVMODE dm = NewMode();
        if (!EnumDisplaySettings(dev, -1, ref dm)) return -99;
        dm.dmFields = DM_W | DM_H | DM_HZ;
        if (DryRun) { Calls.Add("CDS resync " + dev); return 0; }
        return ChangeDisplaySettingsEx(dev, ref dm, IntPtr.Zero, CDS_RESET, IntPtr.Zero);
    }

    static IntPtr HMonOf(string dev) {
        IntPtr found = IntPtr.Zero;
        List<IntPtr> hs = new List<IntPtr>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr h, IntPtr hdc, ref RECT rc, IntPtr d) { hs.Add(h); return true; }, IntPtr.Zero);
        foreach (IntPtr h in hs) {
            MONITORINFOEX mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(mi);
            if (GetMonitorInfo(h, ref mi) && string.Equals(mi.szDevice, dev, StringComparison.OrdinalIgnoreCase)) found = h;
        }
        return found;
    }
    static PHYS[] Phys(string dev) {
        IntPtr hm = HMonOf(dev); uint n;
        if (hm == IntPtr.Zero || !GetNumberOfPhysicalMonitorsFromHMONITOR(hm, out n) || n == 0) return null;
        PHYS[] a = new PHYS[n];
        if (!GetPhysicalMonitorsFromHMONITOR(hm, n, a)) return null;
        return a;
    }
    // Lecture seule de 0xD6 : -1 = DDC impossible, sinon l'etat (1 allume, 4/5 eteint)
    public static int DdcRead(string dev) {
        PHYS[] a = null;
        try {
            a = Phys(dev); if (a == null) return -1;
            for (int i = 0; i < a.Length; i++) { uint cur, max; if (GetVCPFeatureAndVCPFeatureReply(a[i].h, 0xD6, IntPtr.Zero, out cur, out max)) return (int)cur; }
            return -1;
        } catch { return -1; } finally { if (a != null) try { DestroyPhysicalMonitors((uint)a.Length, a); } catch { } }
    }
    public static bool DdcSet(string dev, int value) {
        if (DryRun) { Calls.Add("DDC " + dev + " D6=" + value); return true; }
        PHYS[] a = null;
        try {
            a = Phys(dev); if (a == null) return false;
            bool ok = false;
            for (int i = 0; i < a.Length; i++) if (SetVCPFeature(a[i].h, 0xD6, (uint)value)) ok = true;
            return ok;
        } catch { return false; } finally { if (a != null) try { DestroyPhysicalMonitors((uint)a.Length, a); } catch { } }
    }
    // Capacite DDC lue en arriere-plan (une lecture DDC peut prendre 50 a 500 ms)
    static readonly Dictionary<string, int> _ddc = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
    public static int DdcKnown(string dev) { lock (_ddc) { int v; return _ddc.TryGetValue(dev, out v) ? v : -2; } }
    public static void DdcRemember(string dev, int v) { lock (_ddc) { _ddc[dev] = v; } }
    public static void DdcReset() { lock (_ddc) { _ddc.Clear(); } }
    public static void ProbeDdcAsync(string[] devs) {
        ThreadPool.QueueUserWorkItem(delegate {
            foreach (string d in devs) { if (DdcKnown(d) != -2) continue; int v = DdcRead(d); DdcRemember(d, v); }
        });
    }
}

// Voile noir plein ecran : double-clic ou Echap pour le retirer, petit texte discret qui s'efface
public class GBMonVeil : Form {
    public string Device = "";
    public bool ByUser;
    public string Hint = "Ecran eteint par GameBoost - double-clic pour rallumer";
    readonly Rectangle _b;
    readonly int _auto, _fadeMs;
    readonly System.Windows.Forms.Timer _t = new System.Windows.Forms.Timer();
    readonly Stopwatch _sw = Stopwatch.StartNew();
    double _hintAt = 0;     // debut de l'affichage du texte (ms)
    bool _hintIn = false;   // texte qui revient (souris bougee)
    float _hint = 1f;
    Point _last = new Point(-10000, -10000);
    Font _f;
    public GBMonVeil(Rectangle bounds, int autoCloseMs, int fadeMs) {
        _b = bounds; _auto = autoCloseMs; _fadeMs = fadeMs;
        FormBorderStyle = FormBorderStyle.None; BackColor = Color.Black; ForeColor = Color.Gray; ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual; Bounds = bounds; TopMost = true; KeyPreview = true; DoubleBuffered = true;
        Text = "GameBoost - ecran eteint"; AutoScaleMode = AutoScaleMode.None;
        _f = new Font("Segoe UI", 10f);
        if (_fadeMs > 0) Opacity = 0.0;
        _t.Interval = 15; _t.Tick += Tick;
    }
    protected override bool ShowWithoutActivation { get { return true; } }   // ne vole pas le clavier au jeu
    protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80; return cp; } }   // hors Alt+Tab
    protected override void OnShown(EventArgs e) { base.OnShown(e); Bounds = _b; _t.Start(); }
    static float Out(double p) { if (p <= 0) return 0f; if (p >= 1) return 1f; double q = 1 - p; return (float)(1 - q * q * q); }
    void Tick(object s, EventArgs e) {
        double now = _sw.Elapsed.TotalMilliseconds;
        bool busy = false;
        if (_fadeMs > 0 && Opacity < 1.0) { double p = now / _fadeMs; Opacity = p >= 1 ? 1.0 : Math.Max(0.01, Out(p)); busy = true; }
        double t = now - _hintAt; float h;
        if (_hintIn && t < 200) h = Math.Max(_hint, Out(t / 200.0));
        else if (t < 2800) { h = 1f; _hintIn = false; }
        else h = 1f - Out((t - 2800) / 900.0);
        if (Math.Abs(h - _hint) > 0.004f) { _hint = h; Invalidate(); }
        if (_hint > 0.004f) busy = true;
        if (_auto > 0 && now >= _auto) { ByUser = false; Close(); return; }
        _t.Interval = busy ? 15 : 400;
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        if (_hint <= 0.004f) return;
        int v = (int)(118 * _hint);
        using (SolidBrush br = new SolidBrush(Color.FromArgb(v, v, v))) {
            SizeF sz = e.Graphics.MeasureString(Hint, _f);
            e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            e.Graphics.DrawString(Hint, _f, br, (ClientSize.Width - sz.Width) / 2f, ClientSize.Height * 0.86f - sz.Height / 2f);
        }
    }
    // La souris bouge sur le voile : le texte revient un instant
    protected override void OnMouseMove(MouseEventArgs e) {
        base.OnMouseMove(e);
        if (Math.Abs(e.X - _last.X) + Math.Abs(e.Y - _last.Y) > 24) {
            bool first = _last.X == -10000; _last = e.Location;
            if (!first && _hint < 0.6f) { _hintIn = true; _hintAt = _sw.Elapsed.TotalMilliseconds; _t.Interval = 15; }
        }
    }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); try { Activate(); } catch { } }
    protected override void OnMouseDoubleClick(MouseEventArgs e) { base.OnMouseDoubleClick(e); ByUser = true; Close(); }
    protected override void OnKeyDown(KeyEventArgs e) { base.OnKeyDown(e); if (e.KeyCode == Keys.Escape) { ByUser = true; Close(); } }
    protected override void Dispose(bool disposing) { if (disposing) { _t.Stop(); _t.Dispose(); if (_f != null) _f.Dispose(); } base.Dispose(disposing); }
}
'@
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Test_Ecrans_GameBoost.txt'; if ($Sortie) { $out = $Sortie }
$L = New-Object System.Collections.ArrayList
function W($m) { [void]$L.Add($m); Write-Host $m }
function Save { try { [IO.File]::WriteAllLines($out, [string[]]$L, (New-Object Text.UTF8Encoding($true))) } catch {} }
function Pause-UI([int]$ms) { $t0 = [Environment]::TickCount; while (([Environment]::TickCount - $t0) -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
function ModeText($m) { if (-not $m) { return '(detache)' }; return ("" + $m.X + "," + $m.Y + " " + $m.W + "x" + $m.H + " " + $m.Hz + " Hz orient " + $m.Orient + $(if ($m.Primary) { " principal" } else { "" })) }
function Same($a, $b) { return ($a -and $b -and $a.X -eq $b.X -and $a.Y -eq $b.Y -and $a.W -eq $b.W -and $a.H -eq $b.H -and $a.Hz -eq $b.Hz -and $a.Orient -eq $b.Orient -and $a.Primary -eq $b.Primary) }

W ("Test des ecrans GameBoost - " + (Get-Date) + " - PC " + $env:COMPUTERNAME + " - Windows " + [Environment]::OSVersion.Version)
try { [void][System.Windows.Forms.Application]::EnableVisualStyles() } catch {}
try { Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction Stop }
catch { W ("ECHEC : composant ecrans non compile : " + $_.Exception.Message); Save; exit 1 }
try { Add-Type -Namespace GBT -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'; [void][GBT.Dpi]::SetProcessDPIAware() } catch {}

$list = @([GBMon]::List())
W ("Ecrans trouves : " + $list.Count)
foreach ($m in $list) { W ("  " + $m.Device + "  '" + $m.Name + "'  interne=" + $m.Internal + "  principal=" + $m.Primary + "  " + $m.X + "," + $m.Y + " " + $m.W + "x" + $m.H + " " + $m.Hz + " Hz") }
$orig = @{}; foreach ($m in $list) { $orig[$m.Device] = [GBMon]::GetMode($m.Device) }
$sig0 = [GBMon]::Signature()
$targets = @($list | Where-Object { -not $_.Primary })
$single = ($targets.Count -eq 0)
$msg = "Ce test va eteindre chaque ecran secondaire 3 secondes avec chaque methode (veille DDC, detacher du bureau, voile noir), puis le rallumer.`r`n`r`nNe touche a rien pendant le test (environ 20 secondes par ecran).`r`nLe resultat sera ecrit sur le Bureau : Test_Ecrans_GameBoost.txt`r`n`r`nContinuer ?"
if ($single) { $msg = "Un seul ecran detecte : seul le voile noir sera teste (3 secondes sur cet ecran).`r`n`r`nContinuer ?" }
if ($ASec) { [GBMon]::DryRun = $true; W '(mode a sec : aucune commande envoyee aux ecrans, sauf le voile)' }
elseif ([System.Windows.Forms.MessageBox]::Show($msg, "GameBoost - test des ecrans", 'OKCancel', 'Information') -ne 'OK') { W "Test annule par l'utilisateur."; Save; exit 0 }

$res = @{ Ok = 0; Ko = 0 }
function Add-Res($label, $ok, $detail) { if ($ok) { $res.Ok++ } else { $res.Ko++ }; W ("  [" + $(if ($ok) { 'OK' } else { 'ECHEC' }) + "] " + $label + $(if ($detail) { " : " + $detail } else { "" })); Save }
function Test-Veil($m) {
    $v = New-Object GBMonVeil((New-Object System.Drawing.Rectangle($m.X, $m.Y, $m.W, $m.H)), 3000, 160)
    $st = @{ Closed = $false }; $v.Add_FormClosed({ $st.Closed = $true })
    $v.Show(); Pause-UI 1500
    $px = $null
    try { $bm = New-Object System.Drawing.Bitmap(8, 8); $g = [System.Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen(($m.X + [int]($m.W / 2)), ($m.Y + [int]($m.H / 3)), 0, 0, $bm.Size); $g.Dispose(); $px = $bm.GetPixel(4, 4); $bm.Dispose() } catch {}
    $t0 = [Environment]::TickCount; while (-not $st.Closed -and ([Environment]::TickCount - $t0) -lt 4000) { Pause-UI 50 }
    if (-not $st.Closed) { $v.Close() }
    Add-Res "voile noir 3 s puis retrait automatique" ($st.Closed -and $px -and $px.R -lt 10 -and $px.G -lt 10 -and $px.B -lt 10) ("pixel au centre pendant le voile = " + $px)
}
try {
    if ($single) { W ""; W ("Ecran " + $list[0].Device + " (" + $list[0].Name + ")"); Test-Veil $list[0] }
    foreach ($m in $targets) {
        W ""; W ("Ecran " + $m.Device + " (" + $m.Name + ")" + $(if ($m.Internal) { " - dalle du portable" } else { "" }))
        # 1. Veille DDC/CI
        $d0 = -1; if (-not $m.Internal) { $d0 = [GBMon]::DdcRead($m.Device) }
        if ($d0 -lt 0) { W ("  [--] veille DDC : non disponible sur cet ecran" + $(if ($m.Internal) { " (dalle de portable)" } else { " (DDC/CI coupe dans le menu de l'ecran ?)" })) }
        else {
            $ok4 = [GBMon]::DdcSet($m.Device, 4); Pause-UI 1500
            $mid = [GBMon]::DdcRead($m.Device); Pause-UI 1500
            $ok1 = [GBMon]::DdcSet($m.Device, 1); Pause-UI 2000
            $after = [GBMon]::DdcRead($m.Device)
            if ($after -ne 1) { [void][GBMon]::Resync($m.Device); Pause-UI 1500; $after = [GBMon]::DdcRead($m.Device) }
            Add-Res "veille DDC : commande d'extinction acceptee" $ok4 ("etat lu avant = " + $d0 + ", pendant = " + $mid + $(if ($mid -eq 1) { " (l'ecran s'est rallume tout seul : GameBoost passera a la methode suivante)" } else { "" }))
            Add-Res "veille DDC : rallumage" ($ok1 -and $after -eq 1) ("etat lu apres = " + $after)
        }
        Pause-UI 1000
        # 2. Detacher du bureau, puis remise exacte (position, resolution, frequence, orientation)
        $saved = [GBMon]::GetMode($m.Device)
        $det = New-Object GBMonMode; $det.Device = $m.Device; $det.W = 0
        $rc = [GBMon]::ApplyLayout([GBMonMode[]]@($det)); Pause-UI 1200
        $gone = ($null -eq [GBMon]::GetMode($m.Device))
        Add-Res "detacher du bureau" ($rc -eq 0 -and $gone) ("code Windows " + $rc)
        Pause-UI 1800
        $rc2 = [GBMon]::ApplyLayout([GBMonMode[]]@($saved)); Pause-UI 2000
        $back = [GBMon]::GetMode($m.Device)
        Add-Res "rattacher a l'identique" ((Same $back $saved)) ("avant " + (ModeText $saved) + " / apres " + (ModeText $back) + " (code " + $rc2 + ")")
        Pause-UI 1000
        # 3. Voile noir
        Test-Veil $m
    }
} catch { W ("ERREUR pendant le test : " + $_.Exception.Message) }
finally {
    # Filet de securite : tout est remis exactement comme au debut
    if ([GBMon]::Signature() -ne $sig0) {
        $all = @(); foreach ($k in $orig.Keys) { if ($orig[$k]) { $all += $orig[$k] } }
        $rc = [GBMon]::ApplyLayout([GBMonMode[]]$all); Pause-UI 2000
        W ("Remise de la disposition d'origine : code " + $rc + " -> " + $(if ([GBMon]::Signature() -eq $sig0) { "identique au debut" } else { "DIFFERENTE, verifie Parametres > Affichage" }))
    }
    foreach ($m in $list) { if (-not $m.Internal -and [GBMon]::DdcRead($m.Device) -ge 2) { [void][GBMon]::DdcSet($m.Device, 1) } }
}
W ""; W ("Resultat : " + $res.Ok + " OK, " + $res.Ko + " echec(s). Disposition finale " + $(if ([GBMon]::Signature() -eq $sig0) { "identique au debut." } else { "differente du debut !" }))
W "Envoie ce fichier a Claude pour la suite."
Save
if (-not $ASec) { try { Start-Process notepad.exe -ArgumentList ('"' + $out + '"') } catch {} }
