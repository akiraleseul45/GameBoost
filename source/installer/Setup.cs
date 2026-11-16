// GameBoost-Setup.exe : installe GameBoost comme une application Windows classique.
//   - copie GameBoost.exe dans C:\Program Files\GameBoost
//   - raccourcis (menu Demarrer, Bureau), entree dans "Applications installees" avec desinstallation
//   - en option : tache planifiee qui lance GameBoost avec les droits administrateur sans la question de Windows
// Le meme exe, copie sous le nom Desinstaller.exe, sert a desinstaller (/uninstall).
// Options : /silent (aucune fenetre), /uninstall.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Installation de GameBoost")]
[assembly: AssemblyProduct("GameBoost")]
[assembly: AssemblyDescription("Installe ou desinstalle GameBoost")]
[assembly: AssemblyCompany("GameBoost (open source)")]
[assembly: AssemblyVersion("3.2.0.0")]
[assembly: AssemblyFileVersion("3.2.0.0")]

static class Setup {
    const string Title = "GameBoost";
    const string Version = "3.2";
    const string TaskFolder = "\\GameBoost";
    const string TaskName = "Lancer GameBoost";
    const string UninstallKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GameBoost";

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool MoveFileEx(string from, string to, int flags);

    // Emplacements (la version de test ecrit dans un dossier d'essai et dans le registre du compte, sans droits administrateur)
    static string InstallDir, StartMenuDir, DesktopDir;
    static RegistryKey RegRoot;
#if TEST
    const bool TestMode = true;
#else
    const bool TestMode = false;
#endif

    static void InitPaths() {
#if TEST
        string t = Environment.GetEnvironmentVariable("GAMEBOOST_SETUP_TESTDIR");
        if (string.IsNullOrEmpty(t)) throw new Exception("GAMEBOOST_SETUP_TESTDIR manquant");
        InstallDir = Path.Combine(t, "Program Files", "GameBoost");
        StartMenuDir = Path.Combine(t, "MenuDemarrer"); DesktopDir = Path.Combine(t, "Bureau");
        Directory.CreateDirectory(StartMenuDir); Directory.CreateDirectory(DesktopDir);
        RegRoot = Registry.CurrentUser.CreateSubKey(@"Software\GameBoostSetupTest");
#else
        InstallDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "GameBoost");
        StartMenuDir = Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms);
        DesktopDir = Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory);
        RegRoot = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
#endif
    }

    [STAThread]
    static int Main(string[] args) {
        bool silent = false, uninstall = false, cleanup = false;
        foreach (string a in args) {
            string l = a.ToLowerInvariant();
            if (l == "/silent" || l == "-silent") silent = true;
            else if (l == "/uninstall" || l == "-uninstall") uninstall = true;
            else if (l == "/uninstall-run") { uninstall = true; cleanup = true; }
        }
        Application.EnableVisualStyles();
        try {
            InitPaths();
            if (uninstall) return Uninstall(silent, cleanup);
            if (silent) { Install(true, true, null); return 0; }
            Application.Run(new InstallForm());
            return 0;
        } catch (Exception ex) {
            if (!silent) MessageBox.Show("L'operation a echoue :\r\n\r\n" + ex.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
    }

    // ---------------------------------------------------------------- installation
    public static string ExePath { get { return Path.Combine(InstallDir, "GameBoost.exe"); } }
    static string UninstallerPath { get { return Path.Combine(InstallDir, "Desinstaller.exe"); } }

    static byte[] Resource(string name) {
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if (s == null) throw new Exception("Fichier manquant dans l'installateur : " + name);
            byte[] d = new byte[s.Length]; int r = 0; while (r < d.Length) { int n = s.Read(d, r, d.Length - r); if (n <= 0) break; r += n; }
            return d;
        }
    }

    // GameBoost ouvert depuis le dossier d'installation ? (il faut le fermer pour remplacer le fichier)
    static bool IsRunning() {
        foreach (Process p in Process.GetProcessesByName("GameBoost")) {
            try { if (string.Equals(p.MainModule.FileName, ExePath, StringComparison.OrdinalIgnoreCase)) return true; } catch { return true; }
            finally { p.Dispose(); }
        }
        return false;
    }

    // Les etapes de l'installation. "step" recoit l'avancement (0 a 100) et le texte a afficher.
    // startup : true = GameBoost se lance avec Windows, false = non, null = ne rien changer (installation silencieuse)
    public static void Install(bool desktopShortcut, bool noPrompt, bool? startup, Action<int, string> step = null) {
        if (step == null) step = delegate { };
        step(4, "Verification...");
        if (IsRunning()) throw new Exception("GameBoost est ouvert. Ferme-le (clic droit sur son icone pres de l'horloge > Quitter), puis relance l'installation.");
        Directory.CreateDirectory(InstallDir);
        step(15, "Copie de GameBoost.exe...");
        File.WriteAllBytes(ExePath, Resource("GameBoost.exe"));
        step(40, "Copie du mode d'emploi...");
        File.WriteAllBytes(Path.Combine(InstallDir, "LISEZ-MOI.txt"), Resource("LISEZ-MOI.txt"));
        File.WriteAllBytes(Path.Combine(InstallDir, "LICENCE.txt"), Resource("LICENCE.txt"));
        step(50, "Copie du desinstallateur...");
        string self = Application.ExecutablePath;
        if (!string.Equals(self, UninstallerPath, StringComparison.OrdinalIgnoreCase)) File.Copy(self, UninstallerPath, true);

        step(65, "Creation des raccourcis...");
        Shortcut(Path.Combine(StartMenuDir, "GameBoost.lnk"), ExePath, "Optimiseur de jeu pour Windows");
        string desk = Path.Combine(DesktopDir, "GameBoost.lnk");
        if (desktopShortcut) Shortcut(desk, ExePath, "Optimiseur de jeu pour Windows"); else TryDelete(desk);

        step(80, "Enregistrement dans Windows...");
        using (RegistryKey k = RegRoot.CreateSubKey(UninstallKey)) {
            k.SetValue("DisplayName", "GameBoost");
            k.SetValue("DisplayVersion", Version);
            k.SetValue("Publisher", "GameBoost (open source)");
            k.SetValue("DisplayIcon", ExePath);
            k.SetValue("InstallLocation", InstallDir);
            k.SetValue("UninstallString", "\"" + UninstallerPath + "\" /uninstall");
            k.SetValue("QuietUninstallString", "\"" + UninstallerPath + "\" /uninstall /silent");
            k.SetValue("NoModify", 1, RegistryValueKind.DWord);
            k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            long size = 0; foreach (string f in Directory.GetFiles(InstallDir)) size += new FileInfo(f).Length;
            k.SetValue("EstimatedSize", (int)(size / 1024), RegistryValueKind.DWord);
        }

        step(92, noPrompt ? "Reglage du lancement sans question..." : "Derniers reglages...");
        if (!TestMode) {
            if (noPrompt) RegisterTask(); else RemoveTask(TaskName);
            if (startup == true) RegisterStartupTask(); else if (startup == false) RemoveStartupTask();
        }
        step(100, "Termine");
    }
    static void Shortcut(string lnk, string target, string description) {
        Type t = Type.GetTypeFromProgID("WScript.Shell");
        dynamic sh = Activator.CreateInstance(t);
        dynamic s = sh.CreateShortcut(lnk);
        s.TargetPath = target; s.WorkingDirectory = Path.GetDirectoryName(target); s.Description = description; s.IconLocation = target + ",0";
        s.Save();
    }

    // Tache "Lancer GameBoost" : demarre GameBoost.exe avec les droits administrateur pour le compte qui installe.
    // GameBoost.exe (lance normalement) la declenche au lieu d'afficher la question de Windows.
    static void RegisterTask() {
        string sid = WindowsIdentity.GetCurrent().User.Value;
        string xml =
            "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\r\n" +
            "<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\r\n" +
            "  <RegistrationInfo><Description>Lance GameBoost avec les droits administrateur (cree par l'installateur de GameBoost)</Description></RegistrationInfo>\r\n" +
            "  <Triggers />\r\n" +
            "  <Principals><Principal id=\"Author\"><UserId>" + sid + "</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>\r\n" +
            "  <Settings>\r\n" +
            "    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>\r\n" +
            "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\r\n" +
            "    <AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>false</StartWhenAvailable>\r\n" +
            "    <AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>false</Hidden>\r\n" +
            "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>4</Priority>\r\n" +
            "  </Settings>\r\n" +
            "  <Actions Context=\"Author\"><Exec><Command>" + System.Security.SecurityElement.Escape(ExePath) + "</Command></Exec></Actions>\r\n" +
            "</Task>";
        dynamic svc = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
        svc.Connect();
        dynamic root = svc.GetFolder("\\");
        dynamic folder;
        try { folder = svc.GetFolder(TaskFolder); } catch { folder = root.CreateFolder(TaskFolder.TrimStart('\\')); }
        folder.RegisterTask(TaskName, xml, 6 /* creer ou mettre a jour */, null, null, 3 /* session ouverte */, null);
    }

    // Tache "GameBoost" (racine) : la meme que l'option "Lancer GameBoost avec Windows" de l'application.
    // A l'ouverture de session, GameBoost demarre reduit pres de l'horloge, avec les droits administrateur.
    const string StartupTask = "GameBoost";
    static void RegisterStartupTask() {
        string sid = WindowsIdentity.GetCurrent().User.Value;
        string xml =
            "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\r\n" +
            "<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\r\n" +
            "  <RegistrationInfo><Description>Lance GameBoost (reduit) a l'ouverture de session</Description></RegistrationInfo>\r\n" +
            "  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>" + sid + "</UserId><Delay>PT20S</Delay></LogonTrigger></Triggers>\r\n" +
            "  <Principals><Principal id=\"Author\"><UserId>" + sid + "</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>\r\n" +
            "  <Settings>\r\n" +
            "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\r\n" +
            "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\r\n" +
            "    <AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>false</StartWhenAvailable>\r\n" +
            "    <AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>false</Hidden>\r\n" +
            "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>4</Priority>\r\n" +
            "  </Settings>\r\n" +
            "  <Actions Context=\"Author\"><Exec><Command>" + System.Security.SecurityElement.Escape(ExePath) + "</Command><Arguments>-Minimized</Arguments></Exec></Actions>\r\n" +
            "</Task>";
        dynamic svc = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
        svc.Connect();
        svc.GetFolder("\\").RegisterTask(StartupTask, xml, 6, null, null, 3, null);
    }
    static void RemoveStartupTask() {
        try {
            dynamic svc = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
            svc.Connect();
            svc.GetFolder("\\").DeleteTask(StartupTask, 0);
        } catch { }
    }
    // GameBoost se lance-t-il deja avec Windows ? (case cochee d'avance lors d'une mise a jour)
    public static bool HasStartupTask() {
        try {
            dynamic svc = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
            svc.Connect();
            dynamic task = svc.GetFolder("\\").GetTask(StartupTask);
            return (bool)task.Enabled;
        } catch { return false; }
    }

    static void RemoveTask(string name) {
        try {
            dynamic svc = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
            svc.Connect();
            svc.GetFolder(TaskFolder).DeleteTask(name, 0);
        } catch { }
    }

    // ---------------------------------------------------------------- desinstallation
    static int Uninstall(bool silent, bool cleanup) {
        if (!cleanup) {
            bool settings = false;
            if (!silent) {
                using (UninstallForm f = new UninstallForm()) {
                    if (f.ShowDialog() != DialogResult.OK) return 0;
                    settings = f.RemoveSettings;
                }
            }
            if (IsRunning()) {
                if (!silent) MessageBox.Show("GameBoost est ouvert. Ferme-le (clic droit sur son icone pres de l'horloge > Quitter), puis relance la desinstallation.", Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 2;
            }
            // Un programme ne peut pas supprimer son propre fichier : la suite tourne depuis une copie temporaire
            string tmp = Path.Combine(Path.GetTempPath(), "GameBoost-Desinstaller-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".exe");
            File.Copy(Application.ExecutablePath, tmp, true);
            ProcessStartInfo psi = new ProcessStartInfo(tmp, "/uninstall-run" + (silent ? " /silent" : "") + (settings ? " /settings" : ""));
            psi.UseShellExecute = false;
#if TEST
            psi.EnvironmentVariables["GAMEBOOST_SETUP_TESTDIR"] = Environment.GetEnvironmentVariable("GAMEBOOST_SETUP_TESTDIR");
#endif
            Process.Start(psi);
            return 0;
        }

        bool removeSettings = Array.IndexOf(Environment.GetCommandLineArgs(), "/settings") >= 0;
        Thread.Sleep(600);   // le temps que Desinstaller.exe se ferme
        if (!TestMode) {
            // Taches planifiees de GameBoost : lancement sans question, demarrage avec Windows, automatisations
            try {
                dynamic svc = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
                svc.Connect();
                try {
                    dynamic folder = svc.GetFolder(TaskFolder);
                    foreach (dynamic t in folder.GetTasks(1)) { try { folder.DeleteTask(Convert.ToString(t.Name), 0); } catch { } }
                    svc.GetFolder("\\").DeleteFolder(TaskFolder.TrimStart('\\'), 0);
                } catch { }
                try {
                    dynamic root = svc.GetFolder("\\");
                    dynamic boot = root.GetTask("GameBoost");
                    bool ours = false;
                    foreach (dynamic act in boot.Definition.Actions) if (Convert.ToString(act.Path).Trim('"').StartsWith(InstallDir, StringComparison.OrdinalIgnoreCase)) ours = true;
                    if (ours) root.DeleteTask("GameBoost", 0);
                } catch { }
            } catch { }
            // Fichiers internes (programme extrait, cache, scripts des automatisations)
            TryDeleteDir(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GameBoost"));
            if (removeSettings) TryDeleteDir(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "GameBoost"));
        }
        TryDelete(Path.Combine(StartMenuDir, "GameBoost.lnk"));
        TryDelete(Path.Combine(DesktopDir, "GameBoost.lnk"));
        try { RegRoot.DeleteSubKeyTree(UninstallKey, false); } catch { }
        for (int i = 0; i < 10 && Directory.Exists(InstallDir); i++) { TryDeleteDir(InstallDir); if (Directory.Exists(InstallDir)) Thread.Sleep(300); }
        // La copie temporaire est effacee par Windows au prochain redemarrage
        try { MoveFileEx(Application.ExecutablePath, null, 4); } catch { }
        if (Array.IndexOf(Environment.GetCommandLineArgs(), "/silent") < 0)
            MessageBox.Show(Directory.Exists(InstallDir) ? "GameBoost est desinstalle, mais ce dossier n'a pas pu etre supprime :\r\n" + InstallDir : "GameBoost est desinstalle.", Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
        return 0;
    }

    static void TryDelete(string f) { try { if (File.Exists(f)) File.Delete(f); } catch { } }
    static void TryDeleteDir(string d) { try { if (Directory.Exists(d)) Directory.Delete(d, true); } catch { } }

    // ---------------------------------------------------------------- fenetres
    static readonly Color Bg = Color.FromArgb(14, 18, 32), Panel = Color.FromArgb(22, 28, 48), Txt = Color.FromArgb(232, 238, 248),
        Muted = Color.FromArgb(150, 160, 182), Accent = Color.FromArgb(46, 232, 143);

    static Button MakeButton(string text, bool primary) {
        Button b = new Button();
        b.Text = text; b.FlatStyle = FlatStyle.Flat; b.Font = new Font("Segoe UI", 10f, primary ? FontStyle.Bold : FontStyle.Regular);
        b.BackColor = primary ? Accent : Panel; b.ForeColor = primary ? Color.FromArgb(8, 20, 14) : Txt;
        b.FlatAppearance.BorderColor = primary ? Accent : Color.FromArgb(60, 70, 100); b.Cursor = Cursors.Hand;
        return b;
    }
    static CheckBox MakeCheck(string text, bool on) {
        CheckBox c = new CheckBox();
        c.Text = text; c.Checked = on; c.ForeColor = Txt; c.Font = new Font("Segoe UI", 9.5f); c.AutoSize = false; c.FlatStyle = FlatStyle.Standard;
        return c;
    }
    static Label MakeLabel(string text, int x, int y, int w, int h, float size, FontStyle style, Color color) {
        Label l = new Label(); l.Text = text; l.SetBounds(x, y, w, h); l.Font = new Font("Segoe UI", size, style); l.ForeColor = color; l.BackColor = Color.Transparent;
        return l;
    }

    // Barre de progression aux couleurs de GameBoost
    class Bar : Control {
        double v;
        public double Value { get { return v; } set { v = Math.Max(0, Math.Min(1, value)); Invalidate(); } }
        public Bar() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
        static System.Drawing.Drawing2D.GraphicsPath Pill(RectangleF r) {
            System.Drawing.Drawing2D.GraphicsPath p = new System.Drawing.Drawing2D.GraphicsPath();
            float d = r.Height;
            p.AddArc(r.X, r.Y, d, d, 90, 180); p.AddArc(r.Right - d, r.Y, d, d, 270, 180); p.CloseFigure();
            return p;
        }
        protected override void OnPaint(PaintEventArgs e) {
            Graphics g = e.Graphics; g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias; g.Clear(Bg);
            RectangleF all = new RectangleF(0, 0, Width - 1, Height - 1);
            using (System.Drawing.Drawing2D.GraphicsPath p = Pill(all)) using (SolidBrush b = new SolidBrush(Color.FromArgb(34, 42, 68))) g.FillPath(b, p);
            float w = (float)(all.Width * v);
            if (w >= all.Height) {
                RectangleF fill = new RectangleF(0, 0, w, all.Height);
                using (System.Drawing.Drawing2D.GraphicsPath p = Pill(fill))
                using (System.Drawing.Drawing2D.LinearGradientBrush b = new System.Drawing.Drawing2D.LinearGradientBrush(new RectangleF(0, 0, all.Width + 1, all.Height + 1), Color.FromArgb(34, 211, 238), Accent, 0f))
                    g.FillPath(b, p);
            }
        }
    }

    // Trois pages dans la meme fenetre : options, progression, fin
    class InstallForm : Form {
        bool busy;
        public InstallForm() {
            Form f = this;
            Text = "Installation de GameBoost"; AutoScaleMode = AutoScaleMode.Dpi; ClientSize = new Size(520, 384); FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false; StartPosition = FormStartPosition.CenterScreen; BackColor = Bg; ForeColor = Txt; Font = new Font("Segoe UI", 9.5f);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            PictureBox logo = new PictureBox(); logo.SetBounds(24, 22, 64, 64); logo.SizeMode = PictureBoxSizeMode.Zoom;
            try { using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("logo.png")) logo.Image = Image.FromStream(s); } catch { }
            f.Controls.Add(logo);
            f.Controls.Add(MakeLabel("GameBoost " + Version, 104, 22, 390, 34, 17f, FontStyle.Bold, Txt));
            f.Controls.Add(MakeLabel("Optimiseur de jeu pour Windows 10 et 11", 106, 58, 390, 22, 9.5f, FontStyle.Regular, Muted));

            // --- page 1 : options
            Panel p1 = new Panel(); p1.SetBounds(0, 100, 520, 284); p1.BackColor = Bg; f.Controls.Add(p1);
            p1.Controls.Add(MakeLabel("GameBoost sera installe dans :", 24, 8, 470, 20, 9.5f, FontStyle.Regular, Muted));
            p1.Controls.Add(MakeLabel(InstallDir, 24, 28, 470, 22, 9.5f, FontStyle.Bold, Txt));
            CheckBox cDesk = MakeCheck("Creer un raccourci sur le Bureau", true); cDesk.SetBounds(24, 72, 470, 24); p1.Controls.Add(cDesk);
            CheckBox cTask = MakeCheck("Lancer GameBoost sans la question de Windows a chaque fois", true); cTask.SetBounds(24, 104, 470, 24); p1.Controls.Add(cTask);
            p1.Controls.Add(MakeLabel("GameBoost a besoin des droits administrateur pour regler Windows. Avec cette option, Windows ne redemande plus la confirmation a chaque lancement.",
                43, 128, 452, 38, 8.5f, FontStyle.Regular, Muted));
            CheckBox cStart = MakeCheck("Lancer GameBoost au demarrage de Windows", !TestMode && HasStartupTask()); cStart.SetBounds(24, 170, 470, 24); p1.Controls.Add(cStart);
            p1.Controls.Add(MakeLabel("Il demarre reduit pres de l'horloge. Modifiable ensuite dans GameBoost.", 43, 194, 452, 20, 8.5f, FontStyle.Regular, Muted));
            Button ok = MakeButton("Installer", true); ok.SetBounds(274, 226, 110, 36); p1.Controls.Add(ok);
            Button cancel = MakeButton("Annuler", false); cancel.SetBounds(394, 226, 102, 36); p1.Controls.Add(cancel);

            // --- page 2 : progression
            Panel p2 = new Panel(); p2.SetBounds(0, 100, 520, 284); p2.BackColor = Bg; p2.Visible = false; f.Controls.Add(p2);
            p2.Controls.Add(MakeLabel("Installation en cours...", 24, 30, 470, 28, 13f, FontStyle.Bold, Txt));
            Label status = MakeLabel("", 24, 68, 380, 22, 9.5f, FontStyle.Regular, Muted); p2.Controls.Add(status);
            Label pct = MakeLabel("0 %", 416, 68, 80, 22, 9.5f, FontStyle.Bold, Txt); pct.TextAlign = ContentAlignment.TopRight; p2.Controls.Add(pct);
            Bar bar = new Bar(); bar.SetBounds(24, 98, 472, 14); p2.Controls.Add(bar);
            p2.Controls.Add(MakeLabel("Ne ferme pas cette fenetre.", 24, 126, 470, 20, 8.5f, FontStyle.Regular, Muted));

            // --- page 3 : fin
            Panel p3 = new Panel(); p3.SetBounds(0, 100, 520, 284); p3.BackColor = Bg; p3.Visible = false; f.Controls.Add(p3);
            Panel tick = new Panel(); tick.SetBounds(24, 22, 44, 44); tick.BackColor = Bg; p3.Controls.Add(tick);
            tick.Paint += delegate(object s, PaintEventArgs e) {
                Graphics g = e.Graphics; g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                float w = tick.Width - 1, u = w / 44f;
                using (SolidBrush b = new SolidBrush(Accent)) g.FillEllipse(b, 0, 0, w, w);
                using (Pen pen = new Pen(Color.FromArgb(8, 20, 14), 4.2f * u)) {
                    pen.StartCap = System.Drawing.Drawing2D.LineCap.Round; pen.EndCap = System.Drawing.Drawing2D.LineCap.Round; pen.LineJoin = System.Drawing.Drawing2D.LineJoin.Round;
                    g.DrawLines(pen, new PointF[] { new PointF(12 * u, 23 * u), new PointF(19 * u, 30 * u), new PointF(32 * u, 15 * u) });
                }
            };
            p3.Controls.Add(MakeLabel("Installation terminee", 82, 20, 410, 30, 14f, FontStyle.Bold, Txt));
            p3.Controls.Add(MakeLabel("GameBoost est installe sur ce PC.", 84, 50, 410, 22, 9.5f, FontStyle.Regular, Muted));
            Label where = MakeLabel("", 24, 92, 472, 62, 9.5f, FontStyle.Regular, Txt); p3.Controls.Add(where);
            CheckBox cRun = MakeCheck("Ouvrir GameBoost maintenant", true); cRun.SetBounds(24, 166, 470, 24); p3.Controls.Add(cRun);
            Button done = MakeButton("Terminer", true); done.SetBounds(386, 226, 110, 36); p3.Controls.Add(done);

            f.AcceptButton = ok; f.CancelButton = cancel;
            cancel.Click += delegate { f.Close(); };
            f.FormClosing += delegate(object s, FormClosingEventArgs e) { if (busy) e.Cancel = true; };
            done.Click += delegate {
                if (cRun.Checked && !TestMode) { try { Process.Start(new ProcessStartInfo(ExePath) { UseShellExecute = true }); } catch { } }
                f.Close();
            };

            ok.Click += delegate {
                busy = true; f.AcceptButton = null; f.CancelButton = null;
                p1.Visible = false; p2.Visible = true; f.Cursor = Cursors.AppStarting; Application.DoEvents();
                try {
                    Install(cDesk.Checked, cTask.Checked, cStart.Checked, delegate(int percent, string text) {
                        // La barre avance en douceur jusqu'a l'etape en cours
                        status.Text = text;
                        double from = bar.Value, to = percent / 100.0;
                        for (int i = 1; i <= 16; i++) {
                            bar.Value = from + (to - from) * i / 16.0;
                            pct.Text = ((int)Math.Round(bar.Value * 100)) + " %";
                            Application.DoEvents(); Thread.Sleep(16);
                        }
                    });
                    Thread.Sleep(350);
                    busy = false; f.Cursor = Cursors.Default;
                    where.Text = "Tu le trouves dans le menu Demarrer" + (cDesk.Checked ? " et sur le Bureau" : "") + "." + (cStart.Checked ? " Il se lancera avec Windows." : "") + "\r\n" +
                                 "Pour le desinstaller : Parametres > Applications > Applications installees.";
                    p2.Visible = false; p3.Visible = true; f.AcceptButton = done; done.Focus();
                } catch (Exception ex) {
                    busy = false; f.Cursor = Cursors.Default;
                    MessageBox.Show(f, "L'installation a echoue :\r\n\r\n" + ex.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    bar.Value = 0; pct.Text = "0 %"; status.Text = "";
                    p2.Visible = false; p1.Visible = true; f.AcceptButton = ok; f.CancelButton = cancel;
                }
            };
        }
    }
    class UninstallForm : Form {
        public bool RemoveSettings;
        public UninstallForm() {
            Form f = this;
            Text = "Desinstaller GameBoost"; AutoScaleMode = AutoScaleMode.Dpi; ClientSize = new Size(500, 250); FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false; StartPosition = FormStartPosition.CenterScreen; BackColor = Bg; ForeColor = Txt; Font = new Font("Segoe UI", 9.5f);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            f.Controls.Add(MakeLabel("Desinstaller GameBoost ?", 24, 20, 450, 30, 14f, FontStyle.Bold, Txt));
            f.Controls.Add(MakeLabel("Les reglages que GameBoost a appliques a Windows restent en place. Pour remettre Windows comme avant, ouvre d'abord GameBoost et clique sur TOUT RESTAURER, puis reviens ici.",
                24, 58, 452, 60, 9.5f, FontStyle.Regular, Muted));
            CheckBox c = MakeCheck("Supprimer aussi mes reglages, mes jeux et mes sauvegardes GameBoost", false); c.SetBounds(24, 128, 460, 24); f.Controls.Add(c);
            Button ok = MakeButton("Desinstaller", true); ok.SetBounds(236, 192, 128, 36); f.Controls.Add(ok);
            Button cancel = MakeButton("Annuler", false); cancel.SetBounds(374, 192, 102, 36); f.Controls.Add(cancel);
            f.AcceptButton = cancel; f.CancelButton = cancel;
            ok.Click += delegate { RemoveSettings = c.Checked; f.DialogResult = DialogResult.OK; f.Close(); };
            cancel.Click += delegate { f.DialogResult = DialogResult.Cancel; f.Close(); };
        }
    }
}
