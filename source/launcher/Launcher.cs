// GameBoost.exe : l'application GameBoost.
// Le programme (script PowerShell + PresentMon) est integre dans l'exe. L'exe heberge lui-meme le moteur PowerShell
// de Windows : aucun powershell.exe n'est lance, GameBoost apparait sous son nom dans la barre des taches et le
// Gestionnaire des taches.
//
// Droits administrateur (services, plan d'alimentation, registre) :
//   - GameBoost installe avec l'option "sans confirmation" : demarrage par la tache planifiee creee par l'installateur ;
//   - sinon : Windows demande la confirmation habituelle (UAC).
// Les fichiers extraits vont dans ProgramData\GameBoost\app, un dossier que seuls les administrateurs peuvent modifier.
using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("GameBoost")]
[assembly: AssemblyProduct("GameBoost")]
[assembly: AssemblyDescription("GameBoost - optimiseur de jeu pour Windows 10 / 11")]
[assembly: AssemblyCompany("GameBoost (open source)")]
[assembly: AssemblyVersion("3.2.0.0")]
[assembly: AssemblyFileVersion("3.2.0.0")]

static class Program {
    const string Title = "GameBoost";
    public const string TaskFolder = "\\GameBoost";
    public const string TaskName = "Lancer GameBoost";
    static readonly string[] Files = { "GameBoost.ps1", "PresentMon-x64.exe", "PresentMon-x86.exe", "PresentMon-LICENCE.txt" };

    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int processId);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);

    [STAThread]
    static int Main(string[] args) {
        try { return Run(args); }
        catch (Exception ex) { Error("Impossible de lancer GameBoost :\r\n" + ex.Message); return 1; }
    }

    static bool IsAdmin() {
        try { using (WindowsIdentity id = WindowsIdentity.GetCurrent()) return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator); }
        catch { return false; }
    }

    static int Run(string[] args) {
        bool minimized = false; string edition = ""; int waitPid = 0;
        foreach (string a in args) {
            string low = a.ToLowerInvariant();
            if (low == "-minimized" || low == "/minimized") minimized = true;
            else if (low.StartsWith("/edition:") || low.StartsWith("-edition:")) {
                string v = low.Substring(9);
                if (v == "nexus" || v == "arena" || v == "pure") edition = v;
            } else if (low.StartsWith("/waitpid:") || low.StartsWith("-waitpid:")) {
                int n; if (int.TryParse(low.Substring(9), out n) && n > 0) waitPid = n;
            }
        }

        // Windows 10 / 11 uniquement
        int build = 0;
        try { using (RegistryKey k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion")) { int.TryParse(Convert.ToString(k.GetValue("CurrentBuildNumber")), out build); } } catch { }
        if (build > 0 && build < 10240) { Error("GameBoost fonctionne sur Windows 10 et Windows 11."); return 2; }

        string exe = Application.ExecutablePath;
        // Lance depuis le .zip (dossier temporaire) : le lancement au demarrage de Windows ne marcherait pas
        string temp = Path.GetTempPath();
        if (!minimized && exe.StartsWith(temp, StringComparison.OrdinalIgnoreCase) && exe.IndexOf(".zip", StringComparison.OrdinalIgnoreCase) >= 0) {
            DialogResult r = MessageBox.Show("Tu as lance GameBoost directement depuis le fichier .zip.\r\n\r\nExtrais d'abord le dossier (clic droit sur le .zip > Extraire tout), puis lance GameBoost.exe depuis le dossier extrait. " +
                "Sinon, le lancement au demarrage de Windows ne marchera pas.\r\n\r\nContinuer quand meme ?", Title, MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (r != DialogResult.Yes) return 0;
        }

#if !TEST
        if (!IsAdmin()) {
            // Le double-clic donne le droit de passer au premier plan : on le transmet a la fenetre de GameBoost
            try { AllowSetForegroundWindow(-1); } catch { }
            // Installe "sans confirmation" : la tache planifiee lance ce meme exe avec les droits administrateur
            if (!minimized && edition.Length == 0 && waitPid == 0 && RunElevatedTask(exe)) return 0;
            // Sinon : confirmation habituelle de Windows
            try {
                ProcessStartInfo el = new ProcessStartInfo(exe);
                el.Arguments = string.Join(" ", args); el.UseShellExecute = true; el.Verb = "runas";
                Process.Start(el);
            } catch (System.ComponentModel.Win32Exception) {
                Error("GameBoost a besoin des droits administrateur pour regler Windows (services, alimentation, carte graphique).\r\n\r\nRelance GameBoost et reponds Oui a la question de Windows.");
                return 4;
            }
            return 0;
        }
#endif

        // Barre des taches : GameBoost a sa propre identite (icone, nom, epinglage)
        try { SetCurrentProcessExplicitAppUserModelID("GameBoost.App"); } catch { }

        string script;
#if TEST
        // Version de test : execute le script indique, sans droits administrateur et sans rien extraire
        script = Environment.GetEnvironmentVariable("GAMEBOOST_TEST_SCRIPT");
        if (string.IsNullOrEmpty(script) || !File.Exists(script)) { Error("GAMEBOOST_TEST_SCRIPT manquant"); return 9; }
        string root = Path.GetDirectoryName(script);
#else
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GameBoost");
        string dir = Path.Combine(root, "app");
        try { SecureDir(root); Directory.CreateDirectory(dir); }
        catch (Exception ex) { Error("Impossible de creer le dossier de GameBoost :\r\n" + dir + "\r\n\r\n" + ex.Message); return 1; }

        // Copie des fichiers integres (seulement s'ils ont change : PresentMon peut etre en cours d'utilisation)
        Assembly asm = Assembly.GetExecutingAssembly();
        foreach (string f in Files) {
            string dest = Path.Combine(dir, f);
            byte[] data;
            using (Stream s = asm.GetManifestResourceStream(f)) {
                if (s == null) continue;
                data = new byte[s.Length]; int read = 0; while (read < data.Length) { int n = s.Read(data, read, data.Length - read); if (n <= 0) break; read += n; }
            }
            if (File.Exists(dest) && SameContent(dest, data)) continue;
            try { File.WriteAllBytes(dest, data); }
            catch (Exception ex) {
                if (f.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase)) {
                    Error("GameBoost est peut-etre deja ouvert, ou un antivirus bloque le dossier :\r\n" + dir + "\r\n\r\n" + ex.Message +
                          "\r\n\r\nSi ton antivirus a bloque GameBoost, ajoute ce dossier en exception :\r\n" + dir);
                    return 1;
                }
            }
        }
        script = Path.Combine(dir, "GameBoost.ps1");
#endif

        string errFile = Path.Combine(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "GameBoost"), "erreur_demarrage.txt");
        try { if (File.Exists(errFile)) File.Delete(errFile); } catch { }

        int code = 0; string fail = "";
        try {
            InitialSessionState iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            iss.ApartmentState = ApartmentState.STA;
            iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss)) {
                rs.Open();
                try { Directory.SetCurrentDirectory(Path.GetDirectoryName(script)); rs.SessionStateProxy.Path.SetLocation(Path.GetDirectoryName(script)); } catch { }
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = rs;
                    // false = dans la portee globale, comme "powershell -File" : les fonctions du script restent visibles
                    // depuis les gestionnaires d'evenements crees avec GetNewClosure()
                    ps.AddCommand(script, false).AddParameter("IconPath", exe);
                    if (minimized) ps.AddParameter("Minimized");
                    if (edition.Length > 0) ps.AddParameter("Edition", edition);
                    if (waitPid > 0) ps.AddParameter("WaitPid", waitPid);
                    try { ps.Invoke(); }
                    catch (RuntimeException ex) {
                        fail = ex.Message;
                        try { if (ex.ErrorRecord != null && ex.ErrorRecord.InvocationInfo != null) fail += "\r\n(ligne " + ex.ErrorRecord.InvocationInfo.ScriptLineNumber + ")"; } catch { }
                        code = 1;
                    }
                    try { object lec = rs.SessionStateProxy.GetVariable("LASTEXITCODE"); if (lec != null && code == 0) code = Convert.ToInt32(lec); } catch { }
                }
            }
        } catch (Exception ex) { fail = ex.Message; code = 1; }

        if (code != 0) {
            string why = "";
            try { if (File.Exists(errFile)) why = File.ReadAllText(errFile).Trim(); } catch { }
            if (why.Length > 0) Error("GameBoost n'a pas pu demarrer :\r\n\r\n" + why + "\r\n\r\nGameBoost ne peut pas fonctionner tant que ce blocage est actif.");
            else if (fail.Length > 0) Error("GameBoost s'est arrete a cause d'une erreur :\r\n\r\n" + fail);
        }
        return code;
    }

    // Tache planifiee creee par l'installateur (droits administrateur, sans question de Windows).
    // Elle n'est utilisee que si elle lance bien CET exe.
    static bool RunElevatedTask(string exe) {
        try {
            Type t = Type.GetTypeFromProgID("Schedule.Service");
            if (t == null) return false;
            dynamic svc = Activator.CreateInstance(t);
            svc.Connect();
            dynamic task = svc.GetFolder(TaskFolder).GetTask(TaskName);
            if (!(bool)task.Enabled) return false;
            bool mine = false;
            foreach (dynamic act in task.Definition.Actions) {
                string p = Convert.ToString(act.Path).Trim('"');
                if (string.Equals(Path.GetFullPath(p), Path.GetFullPath(exe), StringComparison.OrdinalIgnoreCase)) mine = true;
            }
            if (!mine) return false;
            task.Run(null);
            return true;
        } catch { return false; }
    }

    // Dossier reserve aux administrateurs et au systeme (memes regles que le cache du script : New-GBSecureDir)
    static readonly string[] Trusted = { "S-1-5-32-544", "S-1-5-18" };
    static bool IsSecure(string path) {
        try {
            DirectorySecurity acl = Directory.GetAccessControl(path);
            string owner = acl.GetOwner(typeof(SecurityIdentifier)).Value;
            if (Array.IndexOf(Trusted, owner) < 0) return false;
            if (!acl.AreAccessRulesProtected) return false;
            foreach (FileSystemAccessRule r in acl.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                if (r.AccessControlType == AccessControlType.Allow && Array.IndexOf(Trusted, r.IdentityReference.Value) < 0) return false;
            return true;
        } catch { return false; }
    }
    static void SecureDir(string path) {
        if (Directory.Exists(path) && !IsSecure(path)) Directory.Delete(path, true);
        if (!Directory.Exists(path)) {
            DirectorySecurity acl = new DirectorySecurity();
            acl.SetAccessRuleProtection(true, false);
            foreach (string sid in Trusted)
                acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(sid), FileSystemRights.FullControl,
                    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
            acl.SetOwner(new SecurityIdentifier("S-1-5-32-544"));
            Directory.CreateDirectory(path, acl);
        }
        if (!IsSecure(path)) throw new IOException("Le dossier " + path + " n'a pas pu etre protege.");
    }

    static bool SameContent(string path, byte[] data) {
        try {
            FileInfo fi = new FileInfo(path);
            if (fi.Length != data.Length) return false;
            using (SHA256 sha = SHA256.Create()) {
                byte[] a = sha.ComputeHash(File.ReadAllBytes(path)); byte[] b = sha.ComputeHash(data);
                for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            }
            return true;
        } catch { return false; }
    }

    static void Error(string msg) { MessageBox.Show(msg, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
}
