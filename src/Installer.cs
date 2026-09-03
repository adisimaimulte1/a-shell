using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Web.Script.Serialization;
[assembly: AssemblyTitle("A-Shell Setup")]
[assembly: AssemblyProduct("A-Shell")]
[assembly: AssemblyVersion("1.2.0.0")]
class Installer {
 const string ExpectedHash="__PAYLOAD_SHA256__";
 static void Line(string text,ConsoleColor color) {Console.ForegroundColor=color;Console.WriteLine("  "+text);Console.ResetColor();}
 static string Hash(Stream s) {using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","");}
 static void SafeParents(string path) {
  for(var d=new DirectoryInfo(Path.GetFullPath(path));d!=null;d=d.Parent)
   if(d.Exists && (d.Attributes&FileAttributes.ReparsePoint)!=0)throw new Exception("Choose a location without linked folders: "+d.FullName);
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
 static void Extract(ZipArchive archive,string target) {
  target=Path.GetFullPath(target).TrimEnd(Path.DirectorySeparatorChar);
  if(Directory.Exists(target)||File.Exists(target))throw new Exception("Destination already exists. Your files were not changed: "+target);
  var parent=Path.GetDirectoryName(target);SafeParents(parent);Directory.CreateDirectory(parent);
  string staging=Path.GetFullPath(Path.Combine(parent,".ashell-install-"+Guid.NewGuid().ToString("N")));
  if(Path.GetDirectoryName(staging)!=parent)throw new Exception("Invalid staging location.");
  Directory.CreateDirectory(staging);
  try {
   int n=0;
   foreach(var e in archive.Entries) {
    var file=Path.GetFullPath(Path.Combine(staging,e.FullName.Substring(8).Replace('/',Path.DirectorySeparatorChar)));
    if(!file.StartsWith(staging+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Path outside installation.");
    Directory.CreateDirectory(Path.GetDirectoryName(file));
    using(var from=e.Open())using(var to=new FileStream(file,FileMode.CreateNew,FileAccess.Write))from.CopyTo(to);
    if(++n%50==0)Line("Installing files  "+n+" / "+archive.Entries.Count,ConsoleColor.DarkGray);
   }
   // Both absolute paths share the explicitly chosen parent; never merge.
   SafeParents(parent);Directory.Move(staging,target);
  } catch {Line("Incomplete files retained for inspection: "+staging,ConsoleColor.Yellow);throw;}
 }
 static int Setup(string root,bool core) {
  var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"));
  start.UseShellExecute=false;start.WorkingDirectory=root;
  start.Arguments="-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,@"scripts\Setup.ps1")+"\" -Action Apply"+(core?" -Core":"");
  start.EnvironmentVariables["PSModulePath"]=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\Modules");
  using(var p=Process.Start(start)){p.WaitForExit();return p.ExitCode;}
 }
 static int Main(string[] args) {
  bool interactive=args.Length==0;
  try {
   Console.Title="A-Shell Setup";
   Console.WriteLine();Line("A - S H E L L",ConsoleColor.DarkYellow);
   Line("YOUR DESKTOP. A LITTLE ORANGE RAIN.",ConsoleColor.White);
   Line("--------------------------------------------------",ConsoleColor.DarkGray);
   bool verify=args.Length==1&&args[0]=="--verify-only";
   bool extract=args.Length==2&&args[0]=="--extract-only";
   if(!interactive&&!verify&&!extract)throw new Exception("Use --verify-only or --extract-only <new folder>.");
   bool core=false;
   string target=extract?Path.GetFullPath(args[1]):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","A-Shell");
   if(interactive) {
    Line("[1] Full appearance     [2] Core only",ConsoleColor.Cyan);
    Line("[3] Verify download     [0] Exit",ConsoleColor.Cyan);
    Console.Write("\n  Choose: ");var answer=Console.ReadLine();
    if(answer=="0")return 0;
    if(answer!="1"&&answer!="2"&&answer!="3")throw new Exception("Choose 1, 2, 3 or 0.");
    verify=answer=="3";core=answer=="2";
    if(!verify) {
     if(Directory.Exists(target))throw new Exception("Already installed at "+target+". Use ashell setup to reapply it. This installer never overwrites your saved state.");
     foreach(var p in Process.GetProcessesByName("MatrixDesktop"))using(p) {
      try {throw new InvalidOperationException("A-Shell is already running from "+Path.GetDirectoryName(Path.GetDirectoryName(p.MainModule.FileName))+". Use its existing setup; a second installation was not created.");}
      catch(System.ComponentModel.Win32Exception){throw new Exception("Close the existing A-Shell installation before installing another copy.");}
     }
     Line("Install to: "+target,ConsoleColor.White);
     Line("Your current appearance is backed up. Personal Desktop",ConsoleColor.Gray);
     Line("contents move to Documents\\original_desktop. Undo is included.",ConsoleColor.Gray);
     Line("Windows will request administrator approval for setup.",ConsoleColor.Gray);
     Console.Write("\n  Install? [Y/N]: ");if(!string.Equals(Console.ReadLine(),"Y",StringComparison.OrdinalIgnoreCase))return 0;
    }
   }
   using(var payload=Assembly.GetExecutingAssembly().GetManifestResourceStream("AShell.Payload.zip")) {
    if(payload==null||Hash(payload)!=ExpectedHash)throw new Exception("Installer payload failed verification.");
    payload.Position=0;
    using(var archive=new ZipArchive(payload,ZipArchiveMode.Read)) {
     Validate(archive);Line("[OK] All bundled files verified.",ConsoleColor.Green);
     if(verify)return 0;
     Extract(archive,target);
    }
   }
   Line("[OK] Installed files: "+target,ConsoleColor.Green);
   if(extract){Line("Extraction only: no Windows settings changed.",ConsoleColor.Gray);return 0;}
   Line("Applying your appearance...",ConsoleColor.DarkYellow);
   if(Setup(target,core)!=0)throw new Exception("Setup needs attention. Files and logs are at "+target+". Run Setup.cmd there to retry, or Undo A-Shell.cmd to restore.");
   Line("[READY] Open a new terminal and run: ashell help",ConsoleColor.Green);
   Line("Undo anytime: ashell restore",ConsoleColor.Cyan);return 0;
  } catch(Exception e){Line("[ERROR] "+e.Message,ConsoleColor.Red);return 1;}
  finally {if(interactive){Console.Write("\n  Press Enter to close...");Console.ReadLine();}}
 }
}
