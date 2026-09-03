using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Web.Script.Serialization;
[assembly: AssemblyTitle("A-Shell Setup")]
[assembly: AssemblyProduct("A-Shell")]
[assembly: AssemblyVersion("1.9.3.0")]
[assembly: AssemblyFileVersion("1.9.3.0")]
[assembly: AssemblyInformationalVersion("1.9.3")]
class Installer {
 const string ExpectedHash="__PAYLOAD_SHA256__";
 const string Version="1.9.3";
 const int STD_OUTPUT_HANDLE=-11, ENABLE_VIRTUAL_TERMINAL_PROCESSING=0x0004;
 [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int nStdHandle);
 [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out int mode);
 [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, int mode);
 static bool Vt;
 static bool IsAdministrator() {
  try {using(var id=WindowsIdentity.GetCurrent())return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);}catch{return false;}
 }
 static string QuoteArgument(string value) {return "\""+(value??"").Replace("\"","\\\"")+"\"";}
 static int RelaunchElevated(string target,string sid) {
  string exe=Assembly.GetExecutingAssembly().Location;
  var psi=new ProcessStartInfo(exe);
  psi.UseShellExecute=true;psi.Verb="runas";psi.WorkingDirectory=Environment.CurrentDirectory;
  psi.Arguments="--ashell-elevated "+QuoteArgument(target)+" "+QuoteArgument(sid);
  try {
   using(var p=Process.Start(psi)){if(p==null)throw new Exception("Windows did not start the elevated installer.");p.WaitForExit();return p.ExitCode;}
  } catch(System.ComponentModel.Win32Exception e) {
   if(e.NativeErrorCode==1223){Line("Administrator approval was cancelled.",ConsoleColor.Yellow);return 0;}
   throw;
  }
 }
 static void InitColor(){try{int m;var h=GetStdHandle(STD_OUTPUT_HANDLE);Vt=GetConsoleMode(h,out m)&&SetConsoleMode(h,m|ENABLE_VIRTUAL_TERMINAL_PROCESSING);}catch{Vt=false;}}
 static void Orange(string text,bool newline=true){if(Vt){Console.Write("\x1b[38;2;214;90;0m"+text+"\x1b[0m"+(newline?"\n":""));}else{Console.ForegroundColor=ConsoleColor.DarkYellow;Console.Write(text+(newline?"\n":""));Console.ResetColor();}}
 static void Line(string text,ConsoleColor color) {Console.ForegroundColor=color;Console.WriteLine("  "+text);Console.ResetColor();}
 static void Rule() {Line("------------------------------------------------------------",ConsoleColor.DarkGray);}
 static void Section(string title) {Console.WriteLine();Orange("  "+title);Rule();}
 static void Stage(int step,int total,string title,string detail) {
  Console.WriteLine();
  Orange("  ================================================================");
  Orange("  >>> STEP "+step+" OF "+total+"  |  ",false);Console.WriteLine(title);
  Orange("  ================================================================");
  if(!String.IsNullOrEmpty(detail))Line(detail,ConsoleColor.Gray);
 }
 static void Option(string key,string title,string detail) {
  Console.ForegroundColor=ConsoleColor.Cyan;Console.Write("  ["+key+"] ");Console.ResetColor();Console.WriteLine(title);
  if(!String.IsNullOrEmpty(detail))Line("    "+detail,ConsoleColor.DarkGray);
 }
 static void Field(string name,string value) {
  Console.ForegroundColor=ConsoleColor.Gray;Console.Write("  "+name.PadRight(12)+": ");Console.ResetColor();Console.WriteLine(value);
 }
 static string Hash(Stream s) {using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","");}
 static void SafeParents(string path) {
  for(var d=new DirectoryInfo(Path.GetFullPath(path));d!=null;d=d.Parent)
   if(d.Exists && (d.Attributes&FileAttributes.ReparsePoint)!=0)throw new Exception("Choose an install location without linked parent folders: "+d.FullName);
 }
 static Dictionary<string,string> Validate(ZipArchive archive) {
  var manifest=archive.GetEntry("A-Shell/assets/package-manifest.json");
  if(manifest==null)throw new Exception("Package manifest missing.");
  Dictionary<string,object> data;
  using(var r=new StreamReader(manifest.Open()))data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(r.ReadToEnd());
  var hashes=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
  foreach(Dictionary<string,object> file in (System.Collections.ArrayList)data["files"])
   hashes.Add("A-Shell/"+(string)file["path"],(string)file["sha256"]);
  var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  foreach(var e in archive.Entries) {
   if(!e.FullName.StartsWith("A-Shell/",StringComparison.Ordinal) || e.FullName.Contains("\\") || e.FullName.Contains(":") || e.FullName.Contains("../") || e.FullName.EndsWith("/"))throw new Exception("Unsafe archive path.");
   if(!seen.Add(e.FullName))throw new Exception("Duplicate archive path.");
   if(e==manifest)continue;
   string wanted;if(!hashes.TryGetValue(e.FullName,out wanted))throw new Exception("Unlisted package file: "+e.FullName);
   using(var s=e.Open())if(Hash(s)!=wanted)throw new Exception("File verification failed: "+e.FullName);
  }
  if(seen.Count!=hashes.Count+1)throw new Exception("Incomplete package.");
  return hashes;
 }
 static bool IsARecognizedInstall(string target) {
  return Directory.Exists(target) && File.Exists(Path.Combine(target,"ashell.cmd")) && File.Exists(Path.Combine(target,@"scripts\Setup.ps1"));
 }
 static void StopExistingMatrix(string target) {
  string exe=Path.Combine(target,@"bin\MatrixDesktop.exe");
  if(File.Exists(exe)) {
   try {using(var p=Process.Start(new ProcessStartInfo(exe,"--stop"){UseShellExecute=false,CreateNoWindow=true})){if(p!=null)p.WaitForExit(5000);}} catch {}
  }
  var deadline=DateTime.UtcNow.AddSeconds(6);
  for(;;) {
   bool ours=false;
   foreach(var p in Process.GetProcessesByName("MatrixDesktop"))using(p) {
    try {if(String.Equals(p.MainModule.FileName,exe,StringComparison.OrdinalIgnoreCase)){ours=true;break;}} catch {}
   }
   if(!ours)return;
   if(DateTime.UtcNow>=deadline)throw new Exception("The existing A-Shell rain process did not stop. Run 'ashell rain stop', wait for it to close, then retry the upgrade.");
   System.Threading.Thread.Sleep(150);
  }
 }
 static void CheckOtherMatrixCopies(string target) {
  string wanted=Path.Combine(target,@"bin\MatrixDesktop.exe");
  foreach(var p in Process.GetProcessesByName("MatrixDesktop"))using(p) {
   try {if(!String.Equals(p.MainModule.FileName,wanted,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Another A-Shell copy is running from "+Path.GetDirectoryName(Path.GetDirectoryName(p.MainModule.FileName))+". Stop that copy before installing here.");}
   catch(System.ComponentModel.Win32Exception){throw new Exception("Close the other A-Shell rain process before installing or upgrading this copy.");}
  }
 }
 static void CopyDirectory(string from,string to) {
  if(!Directory.Exists(from))return;
  Directory.CreateDirectory(to);
  foreach(string dir in Directory.GetDirectories(from,"*",SearchOption.AllDirectories)) {
   string rel=dir.Substring(from.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   Directory.CreateDirectory(Path.Combine(to,rel));
  }
  foreach(string file in Directory.GetFiles(from,"*",SearchOption.AllDirectories)) {
   string rel=file.Substring(from.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   string dest=Path.Combine(to,rel);Directory.CreateDirectory(Path.GetDirectoryName(dest));File.Copy(file,dest,true);
  }
 }
 static string FileHash(string path) {using(var f=File.OpenRead(path))return Hash(f);}
 static bool MatrixRunningFrom(string target) {
  string exe=Path.GetFullPath(Path.Combine(target,@"bin\MatrixDesktop.exe"));
  foreach(var p in Process.GetProcessesByName("MatrixDesktop"))using(p){try{if(String.Equals(Path.GetFullPath(p.MainModule.FileName),exe,StringComparison.OrdinalIgnoreCase))return true;}catch{}}
  return false;
 }
 static void CopyHotUpgrade(string staging,string target,bool skipMatrix) {
  foreach(string dir in Directory.GetDirectories(staging,"*",SearchOption.AllDirectories)) {
   string rel=dir.Substring(staging.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   Directory.CreateDirectory(Path.Combine(target,rel));
  }
  foreach(string file in Directory.GetFiles(staging,"*",SearchOption.AllDirectories)) {
   string rel=file.Substring(staging.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   if(skipMatrix && rel.Equals(@"bin\MatrixDesktop.exe",StringComparison.OrdinalIgnoreCase))continue;
   string dest=Path.Combine(target,rel);Directory.CreateDirectory(Path.GetDirectoryName(dest));File.Copy(file,dest,true);
  }
 }
 static void RemoveStaleProgramFiles(string staging,string target,bool matrixRunning) {
  if(!Directory.Exists(target))return;
  foreach(string file in Directory.GetFiles(target,"*",SearchOption.AllDirectories)) {
   string rel=file.Substring(target.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   if(rel.StartsWith("state"+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase) ||
      rel.StartsWith("backup"+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase) ||
      rel.Equals(@"assets\icon-map.json",StringComparison.OrdinalIgnoreCase))continue;
   if(rel.StartsWith(@"assets\icons\",StringComparison.OrdinalIgnoreCase) && !File.Exists(Path.Combine(staging,rel)))continue;
   if(matrixRunning && rel.Equals(@"bin\MatrixDesktop.exe",StringComparison.OrdinalIgnoreCase))continue;
   if(!File.Exists(Path.Combine(staging,rel))) {
    try {File.Delete(file);} catch(Exception e) {throw new Exception("Could not remove stale A-Shell program file: "+rel+". "+e.Message);}
   }
  }
 }
 static void PreserveUserFiles(string oldRoot,string newRoot) {
  CopyDirectory(Path.Combine(oldRoot,"state"),Path.Combine(newRoot,"state"));
  CopyDirectory(Path.Combine(oldRoot,"backup"),Path.Combine(newRoot,"backup"));
  string oldMap=Path.Combine(oldRoot,@"assets\icon-map.json"),newMap=Path.Combine(newRoot,@"assets\icon-map.json");
  if(File.Exists(oldMap)){Directory.CreateDirectory(Path.GetDirectoryName(newMap));File.Copy(oldMap,newMap,true);}
  string oldIcons=Path.Combine(oldRoot,@"assets\icons"),newIcons=Path.Combine(newRoot,@"assets\icons");
  if(Directory.Exists(oldIcons))foreach(string file in Directory.GetFiles(oldIcons,"*",SearchOption.AllDirectories)) {
   string rel=file.Substring(oldIcons.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   string dest=Path.Combine(newIcons,rel);
   Directory.CreateDirectory(Path.GetDirectoryName(dest));if(!File.Exists(dest))File.Copy(file,dest,false);
  }
 }
 static string Extract(ZipArchive archive,string target,bool allowUpgrade) {
  target=Path.GetFullPath(target).TrimEnd(Path.DirectorySeparatorChar);
  if(File.Exists(target))throw new Exception("Install target is a file: "+target);
  bool upgrading=Directory.Exists(target);
  if(upgrading && !allowUpgrade)throw new Exception("The extraction target already exists: "+target);
  if(upgrading && !IsARecognizedInstall(target))throw new Exception("The existing folder is not a recognizable A-Shell installation, so it will not be overwritten: "+target);
  var parent=Path.GetDirectoryName(target);SafeParents(parent);Directory.CreateDirectory(parent);
  string staging=Path.GetFullPath(Path.Combine(parent,".ashell-install-"+Guid.NewGuid().ToString("N")));
  string previous=null;
  Directory.CreateDirectory(staging);
  try {
   int n=0;
   foreach(var e in archive.Entries) {
    var file=Path.GetFullPath(Path.Combine(staging,e.FullName.Substring(8).Replace('/',Path.DirectorySeparatorChar)));
    if(!file.StartsWith(staging+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Path outside installation.");
    Directory.CreateDirectory(Path.GetDirectoryName(file));
    using(var from=e.Open())using(var to=new FileStream(file,FileMode.CreateNew,FileAccess.Write))from.CopyTo(to);
    if(++n%75==0)Line("Files copied: "+n+" / "+archive.Entries.Count,ConsoleColor.DarkGray);
   }
   SafeParents(parent);
   if(upgrading) {
    bool matrixRunning=MatrixRunningFrom(target);
    string currentMatrix=Path.Combine(target,@"bin\MatrixDesktop.exe"),newMatrix=Path.Combine(staging,@"bin\MatrixDesktop.exe");
    bool sameMatrix=File.Exists(currentMatrix) && File.Exists(newMatrix) && String.Equals(FileHash(currentMatrix),FileHash(newMatrix),StringComparison.OrdinalIgnoreCase);
    previous=Path.Combine(parent,".ashell-previous-"+Guid.NewGuid().ToString("N"));
    CopyDirectory(target,previous);
    try {
     // An update replaces program/code files only. Runtime state, recovery data and
     // the live Matrix process are preserved exactly as they were before Setup ran.
     RemoveStaleProgramFiles(staging,target,matrixRunning);
     CopyHotUpgrade(staging,target,matrixRunning);
     if(matrixRunning && !sameMatrix){
      string pending=Path.Combine(target,@"bin\MatrixDesktop.exe.pending");
      File.Copy(newMatrix,pending,true);
      Line("[OK] New Matrix executable staged; it will replace the live one next time A-Shell starts from a stopped state.",ConsoleColor.Green);
     }
     PreserveUserFiles(previous,target);
     Directory.Delete(staging,true);
     previous="HOT|"+previous;
     Line(matrixRunning?"[OK] Program files updated; current Matrix rain was left untouched.":"[OK] Program files updated; A-Shell remained stopped.",ConsoleColor.Green);
    } catch {try {CopyHotUpgrade(previous,target,matrixRunning);}catch{};throw;}
   } else Directory.Move(staging,target);
   return previous;
  } catch {
   if(Directory.Exists(staging))Line("Incomplete extraction retained for inspection: "+staging,ConsoleColor.Yellow);
   throw;
  }
 }
 static void CleanupPrevious(string previous) {
  if(String.IsNullOrEmpty(previous))return;
  if(previous.StartsWith("HOT|",StringComparison.Ordinal))previous=previous.Substring(4);
  if(!Directory.Exists(previous))return;
  try {Directory.Delete(previous,true);}
  catch {Line("Previous program files were left at "+previous+". They are not active and can be deleted later.",ConsoleColor.Yellow);}
 }
 static bool RollbackUpgrade(string previous,string target) {
  if(String.IsNullOrEmpty(previous))return false;
  bool hot=previous.StartsWith("HOT|",StringComparison.Ordinal);if(hot)previous=previous.Substring(4);
  if(!Directory.Exists(previous))return false;
  string failed=Path.Combine(Path.GetDirectoryName(target),".ashell-failed-"+Guid.NewGuid().ToString("N"));
  try {
   if(hot) {
    // MatrixDesktop.exe is byte-identical in hot mode and may still be mapped;
    // restore every surrounding file without disturbing that live process.
    CopyHotUpgrade(previous,target,true);
    Line("[OK] Previous A-Shell program files were restored in place; Matrix rain was left untouched.",ConsoleColor.Green);
   } else {
    if(Directory.Exists(target))Directory.Move(target,failed);
    Directory.Move(previous,target);
    Line("[OK] Previous A-Shell program files were put back after the failed upgrade.",ConsoleColor.Green);
    if(Directory.Exists(failed))Line("Failed new build retained for logs/inspection at: "+failed,ConsoleColor.Yellow);
   }
   return true;
  } catch(Exception e) {
   Line("Automatic program-file rollback could not finish: "+e.Message,ConsoleColor.Yellow);
   return false;
  }
 }
 static int Setup(string root,bool essentials,bool overridePolicy,string expectedSid) {
  var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"));
  start.UseShellExecute=false;start.WorkingDirectory=root;
  start.Arguments="-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,@"scripts\Setup.ps1")+"\" -Action Apply -ExpectedSid "+expectedSid+(essentials?" -Core":"")+(overridePolicy?" -OverrideLockScreenPolicy":" -DoNotOverrideLockScreenPolicy");
  start.EnvironmentVariables["PSModulePath"]=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\Modules");
  using(var p=Process.Start(start)){p.WaitForExit();return p.ExitCode;}
 }
 static int Main(string[] args) {
  bool elevatedInteractive=args.Length==3&&args[0]=="--ashell-elevated";
  bool interactive=args.Length==0||elevatedInteractive;
  bool suppressPause=false;
  string target=null;
  string previousInstall=null;
  string expectedSid=elevatedInteractive?args[2]:WindowsIdentity.GetCurrent().User.Value;
  try {
   Console.Title="A-Shell Setup "+Version;InitColor();
   Console.WriteLine();Orange("  A - S H E L L   "+Version);
   Line("YOUR DESKTOP. A LITTLE ORANGE RAIN.",ConsoleColor.White);
   Rule();
   bool verify=args.Length==1&&args[0]=="--verify-only";
   bool extract=args.Length==2&&args[0]=="--extract-only";
   if(args.Length==0&&!IsAdministrator()) {
    string originalTarget=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","A-Shell");
    Section("ADMINISTRATOR ACCESS");
    Line("Setup requests administrator access once, before installation or update begins.",ConsoleColor.Gray);
    suppressPause=true;
    return RelaunchElevated(originalTarget,expectedSid);
   }
   if(elevatedInteractive) {
    if(!IsAdministrator())throw new Exception("The elevated installer did not receive administrator rights.");
    if(!String.Equals(WindowsIdentity.GetCurrent().User.Value,expectedSid,StringComparison.OrdinalIgnoreCase))throw new Exception("Administrator approval switched to another Windows account. Approve Setup with the same account that owns this desktop.");
   }
   if(!interactive&&!verify&&!extract)throw new Exception("Use --verify-only or --extract-only <new folder>.");
   bool essentials=false,overridePolicy=false;
   target=extract?Path.GetFullPath(args[1]):(elevatedInteractive?Path.GetFullPath(args[1]):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","A-Shell"));
   bool upgradingTarget=!extract && Directory.Exists(target);
   if(interactive) {
    if(upgradingTarget) {
     if(!IsARecognizedInstall(target))throw new Exception("The existing install folder is not a recognizable A-Shell installation: "+target);
     CheckOtherMatrixCopies(target);
     Section("UPDATE A-SHELL");
     Field("Version",Version);
     Field("Program files","Replace installed code/files");
     Field("Saved data","Keep state/, backup/, mappings and custom icons");
     Field("Runtime","Keep the current started/stopped state and live rain");
     Console.Write("\n  Update this installation? [Y/N]: ");
     if(!string.Equals(Console.ReadLine(),"Y",StringComparison.OrdinalIgnoreCase))return 0;
    } else {
     Section("CHOOSE INSTALLATION");
     Option("1","Complete experience  (recommended)","Desktop, rain, cursors, taskbar/icons and raw lock/sign-in styling.");
     Option("2","Essentials only","Rain, backgrounds, cursors and colors; no Windhawk visual mods.");
     Option("3","Verify installer","Check bundled files only.");
     Option("0","Exit","");
     Console.Write("\n  Choose [0-3]: ");var answer=Console.ReadLine();
     if(answer=="0")return 0;
     if(answer!="1"&&answer!="2"&&answer!="3")throw new Exception("Choose 1, 2, 3 or 0.");
     verify=answer=="3";essentials=answer=="2";
     if(!verify) {
      CheckOtherMatrixCopies(target);
      Section("LOCK-SCREEN CONSENT");
      Line("A-Shell can temporarily override lock-screen personalization blockers and restore them later.",ConsoleColor.Gray);
      Console.Write("\n  Allow lock-screen policy override when needed? [Y/N]: ");
      overridePolicy=string.Equals(Console.ReadLine(),"Y",StringComparison.OrdinalIgnoreCase);
      Section("INSTALL SUMMARY");
      Field("Mode",essentials?"Essentials only":"Complete experience");
      Field("Location",target);
      Field("Desktop","Icon-free while A-Shell is on; personal files stay put");
      Field("Background","Shared desktop + lock/login image when screen is on");
      Field("Backup","Capture wallpaper, lock image, cursors, layout and policies first");
      Console.Write("\n  Install A-Shell? [Y/N]: ");
      if(!string.Equals(Console.ReadLine(),"Y",StringComparison.OrdinalIgnoreCase))return 0;
     }
    }
   }
   int stageTotal=upgradingTarget?3:4;
   if(verify)Section("VERIFY INSTALLER");else Stage(1,stageTotal,"VERIFY PACKAGE","Checking the bundled A-Shell files.");
   using(var payload=Assembly.GetExecutingAssembly().GetManifestResourceStream("AShell.Payload.zip")) {
    if(payload==null||Hash(payload)!=ExpectedHash)throw new Exception("Installer payload failed verification.");
    payload.Position=0;
    using(var archive=new ZipArchive(payload,ZipArchiveMode.Read)) {
     Validate(archive);Line("[OK] Installer and bundled files are intact.",ConsoleColor.Green);
     if(verify){Line("No files were installed and no Windows settings were changed.",ConsoleColor.Gray);return 0;}
     if(extract)Stage(2,2,"EXTRACT FILES","Writing the verified package to the requested new folder; Windows settings are not changed.");
     else if(upgradingTarget)Stage(2,stageTotal,"UPDATE FILES","Replacing program files while preserving saved state and the current runtime state.");
     else Stage(2,stageTotal,"INSTALL FILES","Copying A-Shell into your local Programs folder.");
     previousInstall=Extract(archive,target,!extract);
    }
   }
   Line("[OK] Files installed to "+target,ConsoleColor.Green);
   if(extract){Line("Extraction only: Windows settings were not changed.",ConsoleColor.Gray);return 0;}
   if(upgradingTarget){
    CleanupPrevious(previousInstall);previousInstall=null;
    Stage(3,3,"UPDATE COMPLETE","Program files are current. Saved user data and the existing started/stopped state were not changed.");
    Field("Next","Run: ashell version");
    return 0;
   }
   Stage(3,4,"APPLY WINDOWS CHANGES","Capturing originals, then applying A-Shell for the first installation.");
   int setupExit=Setup(target,essentials,overridePolicy,expectedSid);
   if(setupExit!=0) {
    if(!String.IsNullOrEmpty(previousInstall) && RollbackUpgrade(previousInstall,target))previousInstall=null;
    throw new Exception("A-Shell setup stopped before completion. Appearance rollback was requested by Setup and the previous installed program files were restored when this was an upgrade. See state\\setup.log or the retained failed-build folder for details.");
   }
   CleanupPrevious(previousInstall);
   Stage(4,4,"COMPLETE","Installation and required A-Shell verification finished successfully.");
   Line("[OK] A-Shell is installed and the current program files are up to date.",ConsoleColor.Green);
   Field("Next","Open a new terminal and run: ashell help");
   Field("Start","ashell start");
   Field("Stop","ashell stop");
   Field("Switches","ashell screen | taskbar | icons  on/off");
   Field("Remove","ashell uninstall");
   return 0;
  } catch(Exception e){
   Section("SETUP STOPPED");
   Line("[ERROR] "+e.Message,ConsoleColor.Red);
   if(!String.IsNullOrEmpty(target))Line("Install location: "+target,ConsoleColor.DarkGray);
   if(!String.IsNullOrEmpty(previousInstall)){var shown=previousInstall.StartsWith("HOT|",StringComparison.Ordinal)?previousInstall.Substring(4):previousInstall;if(Directory.Exists(shown))Line("Previous program files preserved at: "+shown,ConsoleColor.Yellow);}
   return 1;
  }
  finally {if(interactive&&!suppressPause){Console.Write("\n  Press Enter to close...");Console.ReadLine();}}
 }
}
