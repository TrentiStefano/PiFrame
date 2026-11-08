param(
  [int]$Width = 0,
  [int]$Height = 0,
  [int]$ScalePercent = 0,
  [int]$Hz = 0,
  [switch]$Show
)
# Changes primary display resolution and DPI scale live (no sign-out).
# DPI uses the undocumented DisplayConfig get/set DPI scale packets (-3 / -4).
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Disp {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
 public struct DEVMODE { [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmDeviceName; public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra; public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput; public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight; public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight; }
 [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string d, int m, ref DEVMODE dm);
 [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
 public static string Cur(){ var dm=new DEVMODE(); dm.dmSize=(short)Marshal.SizeOf(dm); EnumDisplaySettings(null,-1,ref dm); return dm.dmPelsWidth+"x"+dm.dmPelsHeight+"@"+dm.dmDisplayFrequency; }
 public static int Set(int w,int h,int hz){ var dm=new DEVMODE(); dm.dmSize=(short)Marshal.SizeOf(dm); EnumDisplaySettings(null,-1,ref dm); dm.dmPelsWidth=w; dm.dmPelsHeight=h; dm.dmFields=0x80000|0x100000; if(hz>0){dm.dmDisplayFrequency=hz; dm.dmFields|=0x400000;} return ChangeDisplaySettings(ref dm, 0); }

 [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Low; public int High; }
 [StructLayout(LayoutKind.Sequential)] public struct HDR { public int type; public int size; public LUID adapterId; public uint id; }
 [StructLayout(LayoutKind.Sequential)] public struct GETDPI { public HDR h; public int minScaleRel; public int curScaleRel; public int maxScaleRel; }
 [StructLayout(LayoutKind.Sequential)] public struct SETDPI { public HDR h; public int scaleRel; }
 [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint f, out uint p, out uint m);
 [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint f, ref uint np, [Out] byte[] paths, ref uint nm, [Out] byte[] modes, IntPtr t);
 [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref GETDPI p);
 [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref SETDPI p);
 public static int[] Steps = {100,125,150,175,200,225,250,300,350,400,450,500};
 static HDR Source(){ uint np,nm; GetDisplayConfigBufferSizes(2,out np,out nm); byte[] p=new byte[np*72]; byte[] m=new byte[nm*64]; QueryDisplayConfig(2,ref np,p,ref nm,m,IntPtr.Zero);
   var h=new HDR(); h.adapterId.Low=BitConverter.ToUInt32(p,0); h.adapterId.High=BitConverter.ToInt32(p,4); h.id=BitConverter.ToUInt32(p,8); return h; }
 public static int[] GetDpi(){ var g=new GETDPI(); g.h=Source(); g.h.type=-3; g.h.size=Marshal.SizeOf(typeof(GETDPI)); DisplayConfigGetDeviceInfo(ref g); return new int[]{g.minScaleRel,g.curScaleRel,g.maxScaleRel}; }
 public static int SetDpi(int pct){ var cur=GetDpi(); int recIdx=Math.Abs(cur[0]); int target=Array.IndexOf(Steps,pct); if(target<0) return -1; var s=new SETDPI(); s.h=Source(); s.h.type=-4; s.h.size=Marshal.SizeOf(typeof(SETDPI)); s.scaleRel=target-recIdx; return DisplayConfigSetDeviceInfo(ref s); }
 public static int CurPct(){ var c=GetDpi(); int recIdx=Math.Abs(c[0]); return Steps[recIdx+c[1]]; }
}
"@
if ($Width -gt 0) { "resolution -> $([Disp]::Set($Width, $Height, $Hz))"; Start-Sleep -Seconds 2 }
if ($ScalePercent -gt 0) { "scale -> $([Disp]::SetDpi($ScalePercent))"; Start-Sleep -Seconds 2 }
"current: $([Disp]::Cur()) scale=$([Disp]::CurPct())% raw=$([Disp]::GetDpi() -join ',')"
