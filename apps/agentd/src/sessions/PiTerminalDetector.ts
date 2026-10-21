import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import * as fs from 'node:fs';
import * as path from 'node:path';

const execFileAsync = promisify(execFile);
const PI_CLI = /(?:@earendil-works[\\\\/]pi-coding-agent|pi-coding-agent[\\\\/]dist[\\\\/](?:bundle[\\\\/])?cli\.js)/i;

interface PiProcessInfo {
  cwd: string;
  sessionRef?: string;
}

function sessionReference(commandLine: string): string | undefined {
  const match = commandLine.match(/(?:--session(?:=|\s+)|--session-id\s+)(?:"([^"]+)"|(\S+))/i);
  return match?.[1] || match?.[2];
}

function normalize(value: string): string {
  const pathApi = process.platform === 'win32' ? path.win32 : path;
  const resolved = pathApi.resolve(value).replace(/[\\/]+$/, '');
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
}

function matchesCwd(candidate: string, processCwd: string): boolean {
  return normalize(candidate) === normalize(processCwd);
}

const windowsCwdScript = String.raw`
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Diagnostics;
public static class PiFrameProcessDirectory {
  [StructLayout(LayoutKind.Sequential)] public struct BasicInfo {
    public IntPtr Reserved1; public IntPtr PebBaseAddress; public IntPtr Reserved2a;
    public IntPtr Reserved2b; public IntPtr UniqueProcessId; public IntPtr Reserved3;
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, IntPtr size, out IntPtr read);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr process, int infoClass, ref BasicInfo info, int length, out int returned);
  static IntPtr ReadPointer(IntPtr process, IntPtr address) {
    byte[] data = new byte[IntPtr.Size]; IntPtr read;
    if (!ReadProcessMemory(process, address, data, (IntPtr)data.Length, out read) || read.ToInt64() != data.Length) return IntPtr.Zero;
    return IntPtr.Size == 8 ? new IntPtr(BitConverter.ToInt64(data, 0)) : new IntPtr(BitConverter.ToInt32(data, 0));
  }
  public static string Read(int pid) {
    IntPtr process = OpenProcess(0x0410, false, pid);
    if (process == IntPtr.Zero) return null;
    try {
      BasicInfo info = new BasicInfo(); int returned;
      if (NtQueryInformationProcess(process, 0, ref info, Marshal.SizeOf(typeof(BasicInfo)), out returned) != 0) return null;
      IntPtr parameters = ReadPointer(process, IntPtr.Add(info.PebBaseAddress, IntPtr.Size * 4));
      if (parameters == IntPtr.Zero) return null;
      int directoryOffset = IntPtr.Size == 8 ? 0x38 : 0x24;
      byte[] unicode = new byte[IntPtr.Size == 8 ? 16 : 8]; IntPtr read;
      if (!ReadProcessMemory(process, IntPtr.Add(parameters, directoryOffset), unicode, (IntPtr)unicode.Length, out read)) return null;
      int length = BitConverter.ToUInt16(unicode, 0);
      if (length <= 0 || length > 32766) return null;
      IntPtr buffer = IntPtr.Size == 8 ? new IntPtr(BitConverter.ToInt64(unicode, 8)) : new IntPtr(BitConverter.ToInt32(unicode, 4));
      byte[] text = new byte[length];
      if (!ReadProcessMemory(process, buffer, text, (IntPtr)length, out read) || read.ToInt64() != length) return null;
      return Encoding.Unicode.GetString(text);
    } finally { CloseHandle(process); }
  }
}`;

async function windowsPiProcesses(): Promise<PiProcessInfo[] | null> {
  const encodedScript = Buffer.from(`
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
${windowsCwdScript}
'@
$items = @(Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^(node|pi)(\.exe)?$' -and $_.CommandLine -and
  $_.CommandLine -like '*pi-coding-agent*' -and
  $_.CommandLine -notlike '*--mode rpc*'
} | ForEach-Object {
  $directory = [PiFrameProcessDirectory]::Read([int]$_.ProcessId)
  [PSCustomObject]@{ pid = [int]$_.ProcessId; cwd = $directory; commandLine = $_.CommandLine }
})
ConvertTo-Json -InputObject $items -Compress
`, 'utf16le').toString('base64');
  try {
    const { stdout } = await execFileAsync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', encodedScript,
    ], { timeout: 5000, windowsHide: true, maxBuffer: 1024 * 1024 });
    const parsed = JSON.parse(stdout.trim() || '[]');
    const processes = Array.isArray(parsed) ? parsed : [parsed];
    if (processes.some((item) => typeof item.cwd !== 'string' || item.cwd.length === 0)) return null;
    return processes.map((item) => ({ cwd: item.cwd as string, sessionRef: sessionReference(String(item.commandLine ?? '')) }));
  } catch {
    return null;
  }
}

async function linuxPiProcesses(): Promise<PiProcessInfo[] | null> {
  try {
    const processes = fs.readdirSync('/proc').filter((name) => /^\d+$/.test(name));
    const result: PiProcessInfo[] = [];
    for (const pid of processes) {
      try {
        const args = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf8').split('\0');
        const commandLine = args.join(' ');
        if (!PI_CLI.test(commandLine) || /(?:^|\s)--mode\s+rpc(?:\s|$)/.test(commandLine)) continue;
        const sessionIndex = args.findIndex((arg) => arg === '--session' || arg === '--session-id');
        const sessionRef = sessionIndex >= 0 ? args[sessionIndex + 1] : undefined;
        result.push({ cwd: fs.realpathSync(`/proc/${pid}/cwd`), sessionRef });
      } catch { /* Processes can exit while the list is scanned. */ }
    }
    return result;
  } catch {
    return null;
  }
}

async function macPiProcesses(): Promise<PiProcessInfo[] | null> {
  try {
    const { stdout } = await execFileAsync('ps', ['-axo', 'pid=,args='], {
      timeout: 5000, windowsHide: true, maxBuffer: 4 * 1024 * 1024,
    });
    const processes = stdout.split(/\r?\n/).flatMap((line) => {
      const match = line.trim().match(/^(\d+)\s+(.*)$/);
      if (!match || !PI_CLI.test(match[2]) || /(?:^|\s)--mode\s+rpc(?:\s|$)/.test(match[2])) return [];
      return [{ pid: match[1], sessionRef: sessionReference(match[2]) }];
    });
    const cwds = await Promise.all(processes.map(async (process) => {
      try {
        const result = await execFileAsync('lsof', ['-a', '-p', process.pid, '-d', 'cwd', '-Fn'], {
          timeout: 3000, windowsHide: true, maxBuffer: 64 * 1024,
        });
        const cwd = result.stdout.split(/\r?\n/).find((line) => line.startsWith('n'))?.slice(1);
        return cwd ? { cwd, sessionRef: process.sessionRef } : undefined;
      } catch { return undefined; }
    }));
    if (cwds.some((item) => !item)) return null;
    return cwds as PiProcessInfo[];
  } catch {
    return null;
  }
}

/** True means this session is explicitly open. Null means Pi is open in this project, but session identity is unknown. */
export async function hasInteractivePiInCwd(
  cwd: string,
  sessionFile?: string | null,
  sessionId?: string,
): Promise<boolean | null> {
  const processes = process.platform === 'win32'
    ? await windowsPiProcesses()
    : process.platform === 'darwin'
      ? await macPiProcesses()
      : process.platform === 'linux'
        ? await linuxPiProcesses()
        : null;
  if (processes === null) return null;
  let ambiguous = false;
  for (const process of processes) {
    if (!matchesCwd(cwd, process.cwd)) continue;
    if (!process.sessionRef) {
      ambiguous = true;
      continue;
    }
    const ref = process.sessionRef;
    const parsedId = path.basename(ref).match(/(?:^|_)([0-9a-f]{8}-[0-9a-f-]{27,})\.jsonl$/i)?.[1];
    if (ref === sessionId || (sessionFile && normalize(ref) === normalize(sessionFile)) ||
        (sessionId && (path.basename(ref) === sessionId || parsedId === sessionId))) return true;
  }
  return ambiguous ? null : false;
}
