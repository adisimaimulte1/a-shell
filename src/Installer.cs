using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Web.Script.Serialization;
[assembly: AssemblyTitle("A-Shell Setup")]
[assembly: AssemblyProduct("A-Shell")]
[assembly: AssemblyVersion("__ASHELL_ASSEMBLY_VERSION__")]
[assembly: AssemblyFileVersion("__ASHELL_ASSEMBLY_VERSION__")]
[assembly: AssemblyInformationalVersion("__ASHELL_VERSION__")]
class Installer {
 const string ExpectedHash="__PAYLOAD_SHA256__";
 const string Version="__ASHELL_VERSION__";
 const string BuildId="__ASHELL_BUILD_ID__";
 const int STD_OUTPUT_HANDLE=-11, ENABLE_VIRTUAL_TERMINAL_PROCESSING=0x0004;
 [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int nStdHandle);
 [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out int mode);
 [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, int mode);
 [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
 [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
 [DllImport("user32.dll",CharSet=CharSet.Auto)] static extern IntPtr SendMessage(IntPtr hWnd,uint msg,IntPtr wParam,IntPtr lParam);
 const uint WM_SETICON=0x0080;
 const int ICON_SMALL=0, ICON_BIG=1;
 static bool Vt;
 static IntPtr MonochromeWindowIcon=IntPtr.Zero, NormalWindowIcon=IntPtr.Zero;
 static void SetShellIdentity(){try{SetCurrentProcessExplicitAppUserModelID("A-Shell.Setup");}catch{}}
 static bool ReadJsonBool(string path,string name,bool fallback) {
  try {
   if(!File.Exists(path))return fallback;
   var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(path));
   object value;if(!data.TryGetValue(name,out value)||value==null)return fallback;
   if(value is bool)return (bool)value;
   bool parsed;return Boolean.TryParse(Convert.ToString(value),out parsed)?parsed:fallback;
  } catch {return fallback;}
 }
 static bool RuntimeIsActive(string root) {
  string runtime=Path.Combine(root,@"state\runtime-state.json");
  if(File.Exists(runtime))return ReadJsonBool(runtime,"active",false);
  return File.Exists(Path.Combine(root,@"state\applied.txt"));
 }
 static bool MonochromeIconsAreActive(string root) {
  if(String.IsNullOrEmpty(root)||!Directory.Exists(root)||!RuntimeIsActive(root))return false;
  return ReadJsonBool(Path.Combine(root,@"state\features.json"),"icons",true);
 }
 static void ApplyWindowIcon(IntPtr icon) {
  try {
   IntPtr window=GetConsoleWindow();if(window==IntPtr.Zero||icon==IntPtr.Zero)return;
   SendMessage(window,WM_SETICON,(IntPtr)ICON_BIG,icon);
   SendMessage(window,WM_SETICON,(IntPtr)ICON_SMALL,icon);
  } catch {}
 }
 static IntPtr LoadWindowIconResource(string resourceName) {
  using(Stream stream=Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName)) {
   if(stream==null)return IntPtr.Zero;
   using(Bitmap source=new Bitmap(stream))
   using(Bitmap bitmap=new Bitmap(256,256,PixelFormat.Format32bppArgb))
   using(Graphics g=Graphics.FromImage(bitmap)) {
    g.Clear(Color.Transparent);
    g.CompositingMode=CompositingMode.SourceCopy;
    g.CompositingQuality=CompositingQuality.HighQuality;
    g.InterpolationMode=InterpolationMode.HighQualityBicubic;
    g.SmoothingMode=SmoothingMode.HighQuality;
    g.PixelOffsetMode=PixelOffsetMode.HighQuality;
    int left=source.Width,top=source.Height,right=-1,bottom=-1;
    for(int y=0;y<source.Height;y++)for(int x=0;x<source.Width;x++)
     if(source.GetPixel(x,y).A>8){left=Math.Min(left,x);top=Math.Min(top,y);right=Math.Max(right,x);bottom=Math.Max(bottom,y);}
    if(right<left)return IntPtr.Zero;
    Rectangle ink=new Rectangle(left,top,right-left+1,bottom-top+1);
    // Full-size orange; monochrome matches the former orange footprint.
    float extent=resourceName=="AShell.Monochrome.png"?187f:256f;
    float scale=Math.Min(extent/ink.Width,extent/ink.Height);
    int width=Math.Max(1,(int)Math.Round(ink.Width*scale));
    int height=Math.Max(1,(int)Math.Round(ink.Height*scale));
    g.DrawImage(source,new Rectangle((256-width)/2,(256-height)/2,width,height),ink,GraphicsUnit.Pixel);
    return bitmap.GetHicon();
   }
  }
 }
 static void ApplyMonochromeWindowIcon() {
  try {if(MonochromeWindowIcon==IntPtr.Zero)MonochromeWindowIcon=LoadWindowIconResource("AShell.Monochrome.png");ApplyWindowIcon(MonochromeWindowIcon);}catch{}
 }
 static void ApplyNormalWindowIcon() {
  try {if(NormalWindowIcon==IntPtr.Zero)NormalWindowIcon=LoadWindowIconResource("AShell.Normal.png");ApplyWindowIcon(NormalWindowIcon);}catch{}
 }
 static void ApplyConfiguredSetupIcon(string root) {
  if(MonochromeIconsAreActive(root))ApplyMonochromeWindowIcon();else ApplyNormalWindowIcon();
 }
 static void ReassertConfiguredSetupIcon(string root) {
  // Windows Terminal/classic-conhost handoff and UAC can finish initializing the
  // visible console after Main begins, which can overwrite WM_SETICON once. Reapply
  // the same icon a few times during that short initialization window; no polling
  // continues after startup and no extra console/taskbar refresh is triggered.
  try {
   var thread=new System.Threading.Thread(delegate() {
    int[] waits=new int[]{120,350,800,1600};
    foreach(int wait in waits){
     System.Threading.Thread.Sleep(wait);
     ApplyConfiguredSetupIcon(root);
    }
   });
   thread.IsBackground=true;
   thread.Name="A-Shell Setup icon";
   thread.Start();
  } catch {}
 }
 static bool SupportsConsoleHostHandoffControl(){
  try {
   string conhost=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"conhost.exe");
   return FileVersionInfo.GetVersionInfo(conhost).FileBuildPart>=22000;
  } catch {return false;}
 }
 static bool NeedsClassicConsoleHost() {
  try {
   if(!SupportsConsoleHostHandoffControl())return false;
   IntPtr window=GetConsoleWindow();
   return !String.IsNullOrEmpty(Environment.GetEnvironmentVariable("WT_SESSION"))||window==IntPtr.Zero||!IsWindowVisible(window);
  } catch {return false;}
 }
 static int RelaunchInClassicConsole(string[] args) {
  string conhost=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"conhost.exe");
  string exe=Assembly.GetExecutingAssembly().Location;
  var command="-ForceNoHandoff -- "+QuoteArgument(exe)+" --ashell-console-hosted";
  foreach(string arg in args)command+=" "+QuoteArgument(arg);
  var psi=new ProcessStartInfo(conhost,command){UseShellExecute=false,WorkingDirectory=Environment.CurrentDirectory};
  using(var p=Process.Start(psi)){if(p==null)throw new Exception("Windows did not start the A-Shell console host.");}
  return 0;
 }
 static bool IsAdministrator() {
  try {using(var id=WindowsIdentity.GetCurrent())return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);}catch{return false;}
 }
 static string QuoteArgument(string value) {return "\""+(value??"").Replace("\"","\\\"")+"\"";}
 static int RelaunchElevated(string target,string sid) {
  string exe=Assembly.GetExecutingAssembly().Location;
  ProcessStartInfo psi;
  if(SupportsConsoleHostHandoffControl()) {
   string conhost=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"conhost.exe");
   psi=new ProcessStartInfo(conhost);
   psi.Arguments="-ForceNoHandoff -- "+QuoteArgument(exe)+" --ashell-console-hosted --ashell-elevated "+QuoteArgument(target)+" "+QuoteArgument(sid);
  } else {
   psi=new ProcessStartInfo(exe);
   psi.Arguments="--ashell-elevated "+QuoteArgument(target)+" "+QuoteArgument(sid);
  }
  psi.UseShellExecute=true;psi.Verb="runas";psi.WorkingDirectory=Environment.CurrentDirectory;
  try {
   using(var p=Process.Start(psi)){if(p==null)throw new Exception("Windows did not start the elevated installer.");return 0;}
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
  Console.WriteLine();Orange("  ["+step+"/"+total+"] "+title);
  if(!String.IsNullOrEmpty(detail))Line("    "+detail,ConsoleColor.DarkGray);
 }
 static void Option(string key,string title,string detail) {
  Orange("  ["+key+"] ",false);Console.WriteLine(title);
  if(!String.IsNullOrEmpty(detail))Line("    "+detail,ConsoleColor.DarkGray);
 }
 static void Field(string name,string value) {
  Orange("  "+name+": ",false);Console.WriteLine(value);
 }
 static string Hash(Stream s) {using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","");}
 static void SafeParents(string path) {
  for(var d=new DirectoryInfo(Path.GetFullPath(path));d!=null;d=d.Parent)
   if(d.Exists && (d.Attributes&FileAttributes.ReparsePoint)!=0)throw new Exception("Choose an install location without linked parent folders: "+d.FullName);
 }
 static Dictionary<string,string> Validate(ZipArchive archive) {
  var manifest=archive.GetEntry("A-Shell/assets/package-manifest.json");
  if(manifest==null)throw new Exception("Package manifest missing.");
  var buildEntry=archive.GetEntry("A-Shell/assets/build-id.txt");
  if(buildEntry==null)throw new Exception("Package build identifier missing.");
  string packagedBuild;
  using(var buildReader=new StreamReader(buildEntry.Open()))packagedBuild=buildReader.ReadToEnd().Trim();
  if(!String.Equals(packagedBuild,BuildId,StringComparison.Ordinal))throw new Exception("Installer/payload build mismatch. Rebuild Setup from a clean source folder.");
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
 static string ReadInstalledVersion(string target) {
  try {
   string versionFile=Path.Combine(target,"VERSION");
   if(File.Exists(versionFile)) {
    string value=File.ReadAllText(versionFile).Trim();System.Version parsed;
    if(System.Version.TryParse(value,out parsed))return value;
   }
   string manifest=Path.Combine(target,@"assets\package-manifest.json");
   if(File.Exists(manifest)) {
    var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(manifest));
    object value;if(data.TryGetValue("version",out value)) {
     string text=Convert.ToString(value);System.Version parsed;
     if(System.Version.TryParse(text,out parsed))return text;
    }
   }
  } catch {}
  return null;
 }
 static int CompareProductVersions(string installed) {
  System.Version installedVersion,currentVersion;
  if(!System.Version.TryParse(installed,out installedVersion)||!System.Version.TryParse(Version,out currentVersion))return 0;
  return installedVersion.CompareTo(currentVersion);
 }
 static HashSet<string> ReadInstalledManifestPaths(string target) {
  var result=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  try {
   string manifest=Path.Combine(target,@"assets\package-manifest.json");
   if(!File.Exists(manifest))return result;
   var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(manifest));
   foreach(object item in (System.Collections.IEnumerable)data["files"]) {
    var file=item as Dictionary<string,object>;if(file==null)continue;
    object path;if(file.TryGetValue("path",out path))result.Add(Convert.ToString(path).Replace('\\','/'));
   }
  } catch {result.Clear();}
  return result;
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
 static bool CursorGuardRunningFrom(string target) {
  string exe=Path.GetFullPath(Path.Combine(target,@"bin\CursorSessionGuard.exe"));
  foreach(var p in Process.GetProcessesByName("CursorSessionGuard"))using(p){
   try {if(String.Equals(Path.GetFullPath(p.MainModule.FileName),exe,StringComparison.OrdinalIgnoreCase))return true;} catch {}
  }
  return false;
 }
 static bool StopExistingCursorGuard(string target) {
  string exe=Path.GetFullPath(Path.Combine(target,@"bin\CursorSessionGuard.exe"));
  bool found=false;
  foreach(var p in Process.GetProcessesByName("CursorSessionGuard"))using(p) {
   try {
    if(!String.Equals(Path.GetFullPath(p.MainModule.FileName),exe,StringComparison.OrdinalIgnoreCase))continue;
    found=true;
    p.Kill();
    if(!p.WaitForExit(5000))throw new Exception("The active A-Shell cursor guard did not stop in time.");
   } catch(System.ComponentModel.Win32Exception e) {
    throw new Exception("Could not pause the active A-Shell cursor guard for the update. "+e.Message);
   } catch(InvalidOperationException) {}
  }
  if(found){
   var deadline=DateTime.UtcNow.AddSeconds(3);
   while(CursorGuardRunningFrom(target)) {
    if(DateTime.UtcNow>=deadline)throw new Exception("CursorSessionGuard.exe is still running and cannot be updated safely.");
    System.Threading.Thread.Sleep(75);
   }
  }
  return found;
 }
 static void StartCursorGuardIfActive(string target) {
  if(!RuntimeIsActive(target)||CursorGuardRunningFrom(target))return;
  string exe=Path.Combine(target,@"bin\CursorSessionGuard.exe");
  if(!File.Exists(exe))return;
  var psi=new ProcessStartInfo(exe,"--guard") {
   UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Path.GetDirectoryName(exe)
  };
  using(var p=Process.Start(psi)){if(p==null)throw new Exception("Windows did not restart the A-Shell cursor guard after the update.");}
  var deadline=DateTime.UtcNow.AddSeconds(2);
  while(!CursorGuardRunningFrom(target) && DateTime.UtcNow<deadline)System.Threading.Thread.Sleep(50);
  if(!CursorGuardRunningFrom(target))throw new Exception("The updated CursorSessionGuard.exe did not stay running.");
 }
 static void ValidateStagedPowerShell(string staging) {
  string scripts=Path.Combine(staging,"scripts");
  if(!Directory.Exists(scripts))throw new Exception("Staged package is missing the scripts folder.");
  string validator=Path.Combine(Path.GetTempPath(),"ashell-ps-validate-"+Guid.NewGuid().ToString("N")+".ps1");
  string body=@"param([string]$Scripts)
$bad=New-Object System.Collections.Generic.List[string]
foreach($file in Get-ChildItem -LiteralPath $Scripts -Filter '*.ps1' -File){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 foreach($e in @($errors)){[void]$bad.Add(('{0}:{1}:{2}: {3}' -f $file.Name,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message))}
}
if($bad.Count){$bad | ForEach-Object {Write-Output $_};exit 41}
exit 0
";
  File.WriteAllText(validator,body);
  try {
   string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
   var psi=new ProcessStartInfo(powershell) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
   psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "+QuoteArgument(validator)+" -Scripts "+QuoteArgument(scripts);
   using(var process=Process.Start(psi)) {
    if(process==null)throw new Exception("Windows PowerShell did not start for package syntax validation.");
    string output=process.StandardOutput.ReadToEnd();
    string error=process.StandardError.ReadToEnd();
    process.WaitForExit();
    if(process.ExitCode!=0) {
     string details=(output+Environment.NewLine+error).Trim();
     if(details.Length>1800)details=details.Substring(0,1800)+"...";
     throw new Exception("Bundled PowerShell syntax validation failed before installation. "+details);
    }
   }
  } finally {try{File.Delete(validator);}catch{}}
 }
 static void CopyFileReplace(string source,string destination) {
  IOException last=null;
  for(int attempt=0;attempt<24;attempt++) {
   try {File.Copy(source,destination,true);return;}
   catch(IOException e) {
    last=e;
    if(attempt==23)break;
    System.Threading.Thread.Sleep(100);
   }
  }
  throw new IOException("Could not replace "+destination+" after waiting for a transient file lock to clear.",last);
 }
 static void CopyHotUpgrade(string staging,string target,bool skipMatrix) {
  foreach(string dir in Directory.GetDirectories(staging,"*",SearchOption.AllDirectories)) {
   string rel=dir.Substring(staging.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   Directory.CreateDirectory(Path.Combine(target,rel));
  }
  foreach(string file in Directory.GetFiles(staging,"*",SearchOption.AllDirectories)) {
   string rel=file.Substring(staging.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   if(skipMatrix && rel.Equals(@"bin\MatrixDesktop.exe",StringComparison.OrdinalIgnoreCase))continue;
   string dest=Path.Combine(target,rel);Directory.CreateDirectory(Path.GetDirectoryName(dest));CopyFileReplace(file,dest);
  }
 }
 static void RemoveStaleProgramFiles(string staging,string target,bool matrixRunning) {
  if(!Directory.Exists(target))return;
  var previouslyPackaged=ReadInstalledManifestPaths(target);
  foreach(string file in Directory.GetFiles(target,"*",SearchOption.AllDirectories)) {
   string rel=file.Substring(target.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   if(rel.StartsWith("state"+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase) ||
      rel.StartsWith("backup"+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase) ||
      rel.Equals(@"assets\icon-map.json",StringComparison.OrdinalIgnoreCase))continue;
   if(rel.StartsWith(@"assets\icons\",StringComparison.OrdinalIgnoreCase) && !File.Exists(Path.Combine(staging,rel)) && !previouslyPackaged.Contains(rel.Replace('\\','/')))continue;
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
  var previouslyPackaged=ReadInstalledManifestPaths(oldRoot);
  if(Directory.Exists(oldIcons))foreach(string file in Directory.GetFiles(oldIcons,"*",SearchOption.AllDirectories)) {
   string rel=file.Substring(oldIcons.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
   string packagePath=("assets/icons/"+rel.Replace('\\','/'));
   if(previouslyPackaged.Contains(packagePath))continue;
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
   // Hash verification proves the bytes are authentic; parse every PowerShell
   // script as well before a fresh install or update is allowed to touch the
   // current A-Shell directory. This catches packaging-time syntax mistakes.
   ValidateStagedPowerShell(staging);
   Line("[OK] Bundled PowerShell scripts passed Windows PowerShell syntax validation.",ConsoleColor.Green);
   SafeParents(parent);
   if(upgrading) {
    bool matrixRunning=MatrixRunningFrom(target);
    bool cursorGuardWasRunning=CursorGuardRunningFrom(target);
    string currentMatrix=Path.Combine(target,@"bin\MatrixDesktop.exe"),newMatrix=Path.Combine(staging,@"bin\MatrixDesktop.exe");
    bool sameMatrix=File.Exists(currentMatrix) && File.Exists(newMatrix) && String.Equals(FileHash(currentMatrix),FileHash(newMatrix),StringComparison.OrdinalIgnoreCase);
    previous=Path.Combine(parent,".ashell-previous-"+Guid.NewGuid().ToString("N"));
    // Snapshot the old installation before pausing anything. Windows permits the
    // running guard executable to be read, just not overwritten/deleted.
    CopyDirectory(target,previous);
    try {
     if(cursorGuardWasRunning) {
      Line("Pausing the windowless cursor guard while its executable is replaced...",ConsoleColor.DarkGray);
      StopExistingCursorGuard(target);
     }
     // An update replaces program/code files only. Matrix rain, saved state and
     // recovery data stay live. CursorSessionGuard is the one executable that
     // continuously maps itself from the install folder, so it is paused for the
     // copy and restarted after startup-task migration. Stopping it does not alter
     // the currently displayed cursor.
     RemoveStaleProgramFiles(staging,target,matrixRunning);
     CopyHotUpgrade(staging,target,matrixRunning);
     if(matrixRunning && !sameMatrix){
      string pending=Path.Combine(target,@"bin\MatrixDesktop.exe.pending");
      CopyFileReplace(newMatrix,pending);
      Line("[OK] New Matrix executable staged; it will replace the live one next time A-Shell starts from a stopped state.",ConsoleColor.Green);
     }
     PreserveUserFiles(previous,target);
     Directory.Delete(staging,true);
     previous="HOT|"+previous;
     Line(matrixRunning?"[OK] Program files updated; current Matrix rain was left untouched.":"[OK] Program files updated; A-Shell remained stopped.",ConsoleColor.Green);
    } catch {
     try {
      CopyHotUpgrade(previous,target,matrixRunning);
      RemoveStaleProgramFiles(previous,target,matrixRunning);
     } catch {}
     try {if(cursorGuardWasRunning)StartCursorGuardIfActive(target);}catch{}
     throw;
    }
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
  bool restartCursorGuard=RuntimeIsActive(target);
  try {
   StopExistingCursorGuard(target);
   if(hot) {
    // MatrixDesktop.exe may still be mapped, so leave it live. The cursor guard
    // is windowless and safe to pause, which guarantees its EXE can roll back.
    CopyHotUpgrade(previous,target,true);
    RemoveStaleProgramFiles(previous,target,true);
    if(restartCursorGuard)StartCursorGuardIfActive(target);
    Line("[OK] Previous A-Shell program files were restored in place; live Matrix rain was left untouched.",ConsoleColor.Green);
   } else {
    if(Directory.Exists(target))Directory.Move(target,failed);
    Directory.Move(previous,target);
    if(restartCursorGuard)StartCursorGuardIfActive(target);
    Line("[OK] Previous A-Shell program files were put back after the failed upgrade.",ConsoleColor.Green);
    if(Directory.Exists(failed))Line("Failed new build retained for logs/inspection at: "+failed,ConsoleColor.Yellow);
   }
   return true;
  } catch(Exception e) {
   Line("Automatic program-file rollback could not finish: "+e.Message,ConsoleColor.Yellow);
   return false;
  }
 }
 static int MigrateStartupTasks(string root,string expectedSid) {
  var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"));
  start.UseShellExecute=false;start.CreateNoWindow=true;start.WorkingDirectory=root;
  start.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+Path.Combine(root,@"scripts\Manage.ps1")+"\" -Action Migrate -ExpectedSid "+expectedSid;
  start.EnvironmentVariables["PSModulePath"]=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\Modules");
  using(var p=Process.Start(start)){p.WaitForExit();return p.ExitCode;}
 }
 static int Setup(string root,bool essentials,bool overridePolicy,string expectedSid) {
  var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"));
  start.UseShellExecute=false;start.WorkingDirectory=root;
  start.Arguments="-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,@"scripts\Setup.ps1")+"\" -Action Apply -ExpectedSid "+expectedSid+(essentials?" -Core":"")+(overridePolicy?" -OverrideLockScreenPolicy":" -DoNotOverrideLockScreenPolicy");
  start.EnvironmentVariables["PSModulePath"]=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\Modules");
  using(var p=Process.Start(start)){p.WaitForExit();return p.ExitCode;}
 }
 static int Main(string[] args) {
  var normalizedArgs=new List<string>(args);
  bool consoleHosted=normalizedArgs.Remove("--ashell-console-hosted");
  args=normalizedArgs.ToArray();
  bool elevatedInteractive=args.Length==3&&args[0]=="--ashell-elevated";
  bool wantsInteractive=args.Length==0||elevatedInteractive;
  if(wantsInteractive&&!consoleHosted&&NeedsClassicConsoleHost())return RelaunchInClassicConsole(args);
  bool interactive=args.Length==0||elevatedInteractive;
  bool suppressPause=false;
  string target=null;
  string previousInstall=null;
  string expectedSid=elevatedInteractive?args[2]:WindowsIdentity.GetCurrent().User.Value;
  try {
   string defaultTarget=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","A-Shell");
   string iconStateRoot=elevatedInteractive?Path.GetFullPath(args[1]):defaultTarget;
   SetShellIdentity();Console.Title="A-Shell Setup "+Version;InitColor();ApplyConfiguredSetupIcon(iconStateRoot);ReassertConfiguredSetupIcon(iconStateRoot);
   Console.WriteLine();Orange("  A - S H E L L   "+Version);
   Line("YOUR DESKTOP. A LITTLE ORANGE RAIN.",ConsoleColor.White);
   Rule();
   bool verify=args.Length==1&&args[0]=="--verify-only";
   bool extract=args.Length==2&&args[0]=="--extract-only";
   if(args.Length==0&&!IsAdministrator()) {
    string originalTarget=defaultTarget;
    Section("ADMINISTRATOR ACCESS");
    Line("Setup requests administrator access once, then hands off to the elevated A-Shell window.",ConsoleColor.Gray);
    suppressPause=true;
    return RelaunchElevated(originalTarget,expectedSid);
   }
   if(elevatedInteractive) {
    if(!IsAdministrator())throw new Exception("The elevated installer did not receive administrator rights.");
    if(!String.Equals(WindowsIdentity.GetCurrent().User.Value,expectedSid,StringComparison.OrdinalIgnoreCase))throw new Exception("Administrator approval switched to another Windows account. Approve Setup with the same account that owns this desktop.");
   }
   if(!interactive&&!verify&&!extract)throw new Exception("Use --verify-only or --extract-only <new folder>.");
   bool essentials=false,overridePolicy=false;
   target=extract?Path.GetFullPath(args[1]):(elevatedInteractive?Path.GetFullPath(args[1]):defaultTarget);
   bool upgradingTarget=!extract && Directory.Exists(target);
   string installedVersion=upgradingTarget?ReadInstalledVersion(target):null;
   if(interactive) {
    if(upgradingTarget) {
     if(!IsARecognizedInstall(target))throw new Exception("The existing install folder is not a recognizable A-Shell installation: "+target);
     CheckOtherMatrixCopies(target);
     Section("UPDATE A-SHELL");
     int versionOrder=CompareProductVersions(installedVersion);
     string updateKind=String.IsNullOrEmpty(installedVersion)?"Repair":(versionOrder<0?"Upgrade":(versionOrder==0?"Same-version reinstall / repair":"Downgrade / repair"));
     Field("Installed version",String.IsNullOrEmpty(installedVersion)?"Unknown or damaged":installedVersion);
     Field("Installer version",Version);
     Field("Action",updateKind);
     Field("Program files","Replace installed code/files");
     Field("Saved data","Keep state/, backup/, mappings and custom icons");
     Field("Runtime","Keep the current started/stopped state and live rain");
     Console.Write("\n  Continue with this "+updateKind.ToLowerInvariant()+"? [Y/N]: ");
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
    Line("[WORKING] Migrating obsolete sign-in startup tasks without touching the current desktop/rain state...",ConsoleColor.DarkGray);
    int migrationExit=MigrateStartupTasks(target,expectedSid);
    if(migrationExit!=0) {
     bool rolledBack=RollbackUpgrade(previousInstall,target);
     if(rolledBack)previousInstall=null;
     throw new Exception("Startup-task migration failed (exit "+migrationExit+"). The previous A-Shell program files were "+(rolledBack?"restored.":"kept for manual recovery."));
    }
    // Migrate normally starts the guard for an active A-Shell session. Keep this
    // direct safety net so a damaged/missing scheduled task cannot leave an update
    // without cursor protection until the next sign-in.
    StartCursorGuardIfActive(target);
    CleanupPrevious(previousInstall);previousInstall=null;
    Stage(3,3,"UPDATE COMPLETE","Program files and startup tasks are current. Saved user data and the existing started/stopped state were not changed.");
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
   // On a fresh Complete install, icons become active while this Setup window is
   // still open. Re-read the saved component state so the live icon switches now.
   ApplyConfiguredSetupIcon(target);ReassertConfiguredSetupIcon(target);
   Stage(4,4,"COMPLETE","Installation and required A-Shell verification finished successfully.");
   Line("[OK] A-Shell is installed and the current program files are up to date.",ConsoleColor.Green);
   Field("Next","Open a new terminal and run: ashell help");
   Field("Start","ashell start");
   Field("Stop","ashell stop");
   Field("Switches","ashell lockscreen | taskbar | icons  on/off");
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
