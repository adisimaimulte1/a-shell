using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Text;
using System.Runtime.InteropServices;

public static class AShellBranding {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr BeginUpdateResource(string p,bool d);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateResource(IntPtr h,IntPtr t,IntPtr n,ushort l,byte[] b,uint c);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool EndUpdateResource(IntPtr h,bool d);

 static void Pad(BinaryWriter w){while(w.BaseStream.Position%4!=0)w.Write((byte)0);}

 static byte[] Block(string name,byte[] value,bool text,params byte[][] children){
  using(var m=new MemoryStream())using(var w=new BinaryWriter(m)){
   w.Write((ushort)0);w.Write((ushort)(text?value.Length/2:value.Length));w.Write((ushort)(text?1:0));
   w.Write(Encoding.Unicode.GetBytes(name+"\0"));Pad(w);w.Write(value);Pad(w);
   foreach(var child in children){w.Write(child);Pad(w);}
   var b=m.ToArray();Array.Copy(BitConverter.GetBytes((ushort)b.Length),b,2);return b;
  }
 }

 static byte[] Version(string file,string description){
  var names=new string[]{"CompanyName","FileDescription","FileVersion","InternalName","OriginalFilename","ProductName","ProductVersion","LegalCopyright"};
  var values=new string[]{"Adrian Contras",description,"1.9.3.0",Path.GetFileNameWithoutExtension(file),Path.GetFileName(file),"A-Shell","1.9.3.0","GPL-3.0; artwork retains its original terms"};
  var strings=new byte[names.Length][];
  for(int i=0;i<names.Length;i++)strings[i]=Block(names[i],Encoding.Unicode.GetBytes(values[i]+"\0"),true);
  byte[] fixedInfo;
  using(var m=new MemoryStream())using(var w=new BinaryWriter(m)){
   foreach(uint v in new uint[]{0xFEEF04BD,0x10000,0x10001,0,0x10001,0,0x3f,0,0x40004,1,0,0,0})w.Write(v);
   fixedInfo=m.ToArray();
  }
  return Block("VS_VERSION_INFO",fixedInfo,false,
   Block("StringFileInfo",new byte[0],true,Block("040904b0",new byte[0],true,strings)),
   Block("VarFileInfo",new byte[0],true,Block("Translation",new byte[]{9,4,176,4},false)));
 }

 public static void Apply(string exe,string png,string ico,string description){
  var sizes=new int[]{16,24,32,48,64,128,256};
  var images=new byte[sizes.Length][];

  using(var original=Image.FromFile(png)){
   for(int i=0;i<sizes.Length;i++){
    int size=sizes[i];
    using(var bitmap=new Bitmap(size,size,PixelFormat.Format32bppArgb)){
     using(var g=Graphics.FromImage(bitmap)){
      g.Clear(Color.Transparent);
      g.CompositingMode=CompositingMode.SourceCopy;
      g.CompositingQuality=CompositingQuality.HighQuality;
      g.InterpolationMode=InterpolationMode.HighQualityBicubic;
      g.SmoothingMode=SmoothingMode.HighQuality;
      g.PixelOffsetMode=PixelOffsetMode.HighQuality;

      float scale=Math.Min(size/(float)original.Width,size/(float)original.Height);
      int width=Math.Max(1,(int)Math.Round(original.Width*scale));
      int height=Math.Max(1,(int)Math.Round(original.Height*scale));
      int x=(size-width)/2;
      int y=(size-height)/2;

      // Deliberately use the simple Rectangle overload. It is available in the
      // .NET Framework compiler used by Windows PowerShell 5.1 and still honors
      // the high-quality interpolation settings above.
      g.DrawImage(original,new Rectangle(x,y,width,height));
     }
     using(var m=new MemoryStream()){
      bitmap.Save(m,ImageFormat.Png);
      images[i]=m.ToArray();
     }
    }
   }
  }

  using(var m=File.Create(ico))using(var w=new BinaryWriter(m)){
   w.Write((ushort)0);w.Write((ushort)1);w.Write((ushort)sizes.Length);
   int offset=6+16*sizes.Length;
   for(int i=0;i<sizes.Length;i++){
    w.Write((byte)(sizes[i]==256?0:sizes[i]));w.Write((byte)(sizes[i]==256?0:sizes[i]));
    w.Write((ushort)0);w.Write((ushort)1);w.Write((ushort)32);
    w.Write(images[i].Length);w.Write(offset);offset+=images[i].Length;
   }
   foreach(var b in images)w.Write(b);
  }

  IntPtr handle=BeginUpdateResource(exe,false);
  if(handle==IntPtr.Zero)throw new IOException("Cannot open executable resources");
  bool done=false;
  try{
   using(var m=new MemoryStream())using(var w=new BinaryWriter(m)){
    w.Write((ushort)0);w.Write((ushort)1);w.Write((ushort)sizes.Length);
    for(int i=0;i<sizes.Length;i++){
     if(!UpdateResource(handle,(IntPtr)3,(IntPtr)(i+1),0,images[i],(uint)images[i].Length))throw new IOException("Icon resource failed");
     w.Write((byte)(sizes[i]==256?0:sizes[i]));w.Write((byte)(sizes[i]==256?0:sizes[i]));
     w.Write((ushort)0);w.Write((ushort)1);w.Write((ushort)32);
     w.Write(images[i].Length);w.Write((ushort)(i+1));
    }
    byte[] b=m.ToArray();
    if(!UpdateResource(handle,(IntPtr)14,(IntPtr)1,0,b,(uint)b.Length))throw new IOException("Icon group failed");
   }
   byte[] v=Version(exe,description);
   if(!UpdateResource(handle,(IntPtr)16,(IntPtr)1,0,v,(uint)v.Length))throw new IOException("Version resource failed");
   done=EndUpdateResource(handle,false);
   if(!done)throw new IOException("Saving resources failed");
  }finally{
   if(!done)EndUpdateResource(handle,true);
  }
 }
}
