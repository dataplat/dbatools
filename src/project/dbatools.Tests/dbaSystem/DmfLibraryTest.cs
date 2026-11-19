using System;
using System.Diagnostics;
using System.IO;
using Dataplat.Dbatools.dbaSystem;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.dbaSystem.Test
{
    /// <summary>
    /// TB-002 coverage for DmfLibrary.Load, the C# parity port of
    /// private/functions/Add-PbmLibrary.ps1. Assembly loading is process-global and
    /// irreversible, so each lifecycle scenario runs in a DEDICATED FRESH CHILD PROCESS
    /// per TFM - the edition-matched PowerShell host (Windows PowerShell 5.1 for net472,
    /// pwsh 7 for net8.0, both gate currency per COORDINATION.md 7.1) loading the built
    /// dbatools.dll exactly like production. The failure legs (asymmetric missing files
    /// proving Common-before-Dmf order) and the success legs (exact load locations of
    /// BOTH assemblies under the complete fake root, then idempotence) each get their
    /// own child so no leg inherits loaded state from another. The fake roots are built
    /// from the DMF assemblies the SqlManagementObjects package ships into the test
    /// output for both TFMs.
    /// </summary>
    [TestClass]
    public class DmfLibraryTest
    {
        private static string NewRoot(bool withCommon, bool withDmf)
        {
            string root = Path.Combine(Path.GetTempPath(), "dbatools-tests-dmf-" + Guid.NewGuid().ToString("N"));
            string lib = Path.Combine(root, "lib");
            Directory.CreateDirectory(lib);
            string binDir = AppDomain.CurrentDomain.BaseDirectory;
            if (withCommon)
                File.Copy(Path.Combine(binDir, "Microsoft.SqlServer.Dmf.Common.dll"), Path.Combine(lib, "Microsoft.SqlServer.Dmf.Common.DLL"));
            if (withDmf)
                File.Copy(Path.Combine(binDir, "Microsoft.SqlServer.Dmf.dll"), Path.Combine(lib, "Microsoft.SqlServer.Dmf.dll"));
            return root;
        }

        private static void TryRemove(string path)
        {
            try
            {
                if (Directory.Exists(path))
                    Directory.Delete(path, true);
                else if (File.Exists(path))
                    File.Delete(path);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }

        // The child runs on Windows (the file-copy scheme and both PS hosts are
        // Windows-bound), so path comparisons are OrdinalIgnoreCase.
        private const string ChildLifecycleScript = @"
param([string]$DbatoolsDll, [string]$Mode, [string]$CommonMissingRoot, [string]$DmfMissingRoot, [string]$CompleteRoot)
$ErrorActionPreference = ""Stop""
function Fail([string]$reason) { Write-Output (""FAIL: "" + $reason); exit 1 }
function Get-DmfLoaded([string]$name) {
    [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq $name }
}
function Get-FileNotFound($caught) {
    $walker = $caught
    while ($walker -and -not ($walker -is [System.IO.FileNotFoundException])) { $walker = $walker.InnerException }
    $walker
}
function Assert-ExactLocation($assembly, [string]$root, [string]$fileName) {
    $expected = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $root ""lib"") $fileName))
    $actual = [System.IO.Path]::GetFullPath($assembly.Location)
    if (-not [String]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) {
        Fail ($assembly.GetName().Name + "" loaded from '"" + $actual + ""' expected '"" + $expected + ""'"")
    }
}
Add-Type -Path $DbatoolsDll

if ($Mode -eq ""failures"") {
    # Leg 1: Common missing, Dmf present -> the FIRST load fails and Dmf stays unloaded,
    # proving Load never reached the second file (Common-first order).
    $caught = $null
    try { [Dataplat.Dbatools.dbaSystem.DmfLibrary]::Load($CommonMissingRoot) } catch { $caught = $_.Exception }
    $notFound = Get-FileNotFound $caught
    if (-not $notFound) { Fail ""leg1: expected FileNotFoundException for missing Dmf.Common"" }
    if ($notFound.FileName -notlike ""*Dmf.Common*"") { Fail (""leg1: wrong file failed: "" + $notFound.FileName) }
    if (Get-DmfLoaded ""Microsoft.SqlServer.Dmf"") { Fail ""leg1: Dmf loaded despite Common failing first - order broken"" }
    if (Get-DmfLoaded ""Microsoft.SqlServer.Dmf.Common"") { Fail ""leg1: Common unexpectedly loaded"" }

    # Leg 2: Common present, Dmf missing -> Common loads (first), then the SECOND load
    # fails on Dmf. Common being loaded afterward proves it was attempted before the failure.
    $caught = $null
    try { [Dataplat.Dbatools.dbaSystem.DmfLibrary]::Load($DmfMissingRoot) } catch { $caught = $_.Exception }
    $notFound = Get-FileNotFound $caught
    if (-not $notFound) { Fail ""leg2: expected FileNotFoundException for missing Dmf"" }
    if ($notFound.FileName -like ""*Dmf.Common*"") { Fail ""leg2: failure should be the Dmf load, not Common"" }
    $common = Get-DmfLoaded ""Microsoft.SqlServer.Dmf.Common""
    if (-not $common) { Fail ""leg2: Common not loaded before the Dmf failure - order broken"" }
    Assert-ExactLocation $common $DmfMissingRoot ""Microsoft.SqlServer.Dmf.Common.DLL""
    if (Get-DmfLoaded ""Microsoft.SqlServer.Dmf"") { Fail ""leg2: Dmf unexpectedly loaded"" }
} else {
    # Success legs in a FRESH process: nothing DMF is loaded yet, so BOTH assemblies
    # must load from the exact complete-root lib paths.
    [Dataplat.Dbatools.dbaSystem.DmfLibrary]::Load($CompleteRoot)
    $common = Get-DmfLoaded ""Microsoft.SqlServer.Dmf.Common""
    if (-not $common) { Fail ""success: Common not loaded"" }
    Assert-ExactLocation $common $CompleteRoot ""Microsoft.SqlServer.Dmf.Common.DLL""
    $dmf = Get-DmfLoaded ""Microsoft.SqlServer.Dmf""
    if (-not $dmf) { Fail ""success: Dmf not loaded"" }
    Assert-ExactLocation $dmf $CompleteRoot ""Microsoft.SqlServer.Dmf.dll""

    # Idempotence - re-running with everything loaded succeeds, like re-running the
    # helper's Add-Type calls.
    [Dataplat.Dbatools.dbaSystem.DmfLibrary]::Load($CompleteRoot)
}
Write-Output ""ALL-LEGS-PASS""
exit 0
";

        private static void RunLifecycleChild(string mode, string commonMissing, string dmfMissing, string complete)
        {
            string script = Path.Combine(Path.GetTempPath(), "dbatools-tests-dmf-child-" + Guid.NewGuid().ToString("N") + ".ps1");
            File.WriteAllText(script, ChildLifecycleScript);
            try
            {
#if NETFRAMEWORK
                // Windows PowerShell hosts the net472 build, mirroring production.
                string shell = "powershell.exe";
#else
                // pwsh 7 hosts the net8.0 build, mirroring production.
                string shell = "pwsh";
#endif
                string dbatoolsDll = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "dbatools.dll");
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = shell;
                startInfo.Arguments = String.Format(
                    "-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -DbatoolsDll \"{1}\" -Mode {2} -CommonMissingRoot \"{3}\" -DmfMissingRoot \"{4}\" -CompleteRoot \"{5}\"",
                    script, dbatoolsDll, mode, commonMissing, dmfMissing, complete);
                startInfo.UseShellExecute = false;
                startInfo.RedirectStandardOutput = true;
                startInfo.RedirectStandardError = true;
                startInfo.CreateNoWindow = true;

                using (Process child = Process.Start(startInfo))
                {
                    // Drain both pipes asynchronously so the timeout is real and full
                    // pipes can never deadlock the child.
                    System.Threading.Tasks.Task<string> stdoutTask = child.StandardOutput.ReadToEndAsync();
                    System.Threading.Tasks.Task<string> stderrTask = child.StandardError.ReadToEndAsync();
                    if (!child.WaitForExit(120000))
                    {
                        try { child.Kill(); } catch (InvalidOperationException) { }
                        child.WaitForExit();
                        Assert.Fail("child lifecycle process timed out. stdout: " + stdoutTask.Result + " stderr: " + stderrTask.Result);
                    }
                    string stdout = stdoutTask.Result;
                    string stderr = stderrTask.Result;
                    Assert.AreEqual(0, child.ExitCode, "child lifecycle failed. stdout: " + stdout + " stderr: " + stderr);
                    // The helper emits no messages, and the script prints only the
                    // sentinel on success - the streams carry exactly that and nothing else.
                    Assert.AreEqual("ALL-LEGS-PASS" + Environment.NewLine, stdout, "unexpected child stdout: " + stdout);
                    Assert.AreEqual(String.Empty, stderr, "unexpected child stderr: " + stderr);
                }
            }
            finally
            {
                TryRemove(script);
            }
        }

        [TestMethod]
        public void Load_FailureLegs_ProveCommonLoadsFirst()
        {
            string commonMissing = NewRoot(false, true);
            string dmfMissing = NewRoot(true, false);
            try
            {
                RunLifecycleChild("failures", commonMissing, dmfMissing, "unused");
            }
            finally
            {
                TryRemove(commonMissing);
                TryRemove(dmfMissing);
            }
        }

        [TestMethod]
        public void Load_SuccessLegs_LoadBothFromExactLibPathsAndStayIdempotent()
        {
            string complete = NewRoot(true, true);
            try
            {
                RunLifecycleChild("success", "unused", "unused", complete);
            }
            finally
            {
                TryRemove(complete);
            }
        }

        [TestMethod]
        public void Load_NullOrEmptyRootSurfacesAFailureLikeTheHelper()
        {
            // In PS a missing $script:libraryroot still lands in the same catch -> Stop-Function
            // flow; the port surfaces it as ArgumentNullException before touching the disk.
            Assert.ThrowsException<ArgumentNullException>(delegate { DmfLibrary.Load(null); });
            Assert.ThrowsException<ArgumentNullException>(delegate { DmfLibrary.Load(String.Empty); });
        }
    }
}
