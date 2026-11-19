using System;
using System.Diagnostics;
using System.IO;
using Dataplat.Dbatools.dbaSystem;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.dbaSystem.Test
{
    /// <summary>
    /// TB-003 coverage for ReplicationLibrary.Load, the C# parity port of
    /// private/functions/Add-ReplicationLibrary.ps1, following the TB-002 pattern:
    /// each load lifecycle scenario runs in a DEDICATED FRESH CHILD PROCESS per TFM
    /// (edition-matched PowerShell host loading the built dbatools.dll), because
    /// assembly loading is process-global and irreversible. RMO has no NuGet package
    /// and does not ship into the test output, so the FAILURE-leg roots are built from
    /// the repo's vendored assemblies at var/misc/both (the same files the
    /// dbatools.replication satellite compiles against), located by walking up from
    /// the test output to the repo root; they prove the Rmo-before-Replication load
    /// order via asymmetric missing files. The SUCCESS legs assert BOTH assemblies'
    /// exact load locations under the complete fake root, then idempotence, using
    /// loadable stand-ins (see NewStandInRoot for why the real mixed-mode
    /// Replication.dll cannot load on machines without SQL native components).
    /// </summary>
    [TestClass]
    public class ReplicationLibraryTest
    {
        private static string VendoredDir()
        {
            string walker = AppDomain.CurrentDomain.BaseDirectory;
            while (walker != null)
            {
                string candidate = Path.Combine(walker, "var", "misc", "both");
                if (File.Exists(Path.Combine(candidate, "Microsoft.SqlServer.Rmo.dll")))
                    return candidate;
                walker = Path.GetDirectoryName(walker);
            }
            throw new DirectoryNotFoundException("vendored var/misc/both not found above " + AppDomain.CurrentDomain.BaseDirectory);
        }

        private static string NewRoot(bool withRmo, bool withReplication)
        {
            string root = Path.Combine(Path.GetTempPath(), "dbatools-tests-rmo-" + Guid.NewGuid().ToString("N"));
            string lib = Path.Combine(root, "lib");
            Directory.CreateDirectory(lib);
            string vendored = VendoredDir();
            if (withRmo)
                File.Copy(Path.Combine(vendored, "Microsoft.SqlServer.Rmo.dll"), Path.Combine(lib, "Microsoft.SqlServer.Rmo.dll"));
            if (withReplication)
                File.Copy(Path.Combine(vendored, "Microsoft.SqlServer.Replication.dll"), Path.Combine(lib, "Microsoft.SqlServer.Replication.dll"));
            return root;
        }

        // Microsoft.SqlServer.Replication.dll is a mixed-mode assembly whose NATIVE
        // dependency chain only exists on machines with SQL Server client components -
        // probed 2026-07-16 on the workstation VM: LoadFrom fails "module could not be
        // found" with the file present, in BOTH editions, even from the production
        // dbatools.library lib folder. The PS helper hits its Stop-Function catch on
        // such machines the same way (that is what its warning message is about), and
        // live replication behavior belongs to the lab gate. The success legs therefore
        // prove the loader's path/order/idempotence contract with LOADABLE stand-ins:
        // the DMF assemblies the test output already ships, copied under the RMO file
        // names. The child script is location-keyed, never name-keyed, so stand-ins
        // exercise the identical code path.
        private static string NewStandInRoot()
        {
            string root = Path.Combine(Path.GetTempPath(), "dbatools-tests-rmo-" + Guid.NewGuid().ToString("N"));
            string lib = Path.Combine(root, "lib");
            Directory.CreateDirectory(lib);
            string binDir = AppDomain.CurrentDomain.BaseDirectory;
            File.Copy(Path.Combine(binDir, "Microsoft.SqlServer.Dmf.Common.dll"), Path.Combine(lib, "Microsoft.SqlServer.Rmo.dll"));
            File.Copy(Path.Combine(binDir, "Microsoft.SqlServer.Dmf.dll"), Path.Combine(lib, "Microsoft.SqlServer.Replication.dll"));
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

        // Location-keyed checks make the child independent of assembly-name assumptions;
        // it runs on the Windows PS hosts, so path comparisons are OrdinalIgnoreCase.
        private const string ChildLifecycleScript = @"
param([string]$DbatoolsDll, [string]$Mode, [string]$RmoMissingRoot, [string]$ReplicationMissingRoot, [string]$CompleteRoot)
$ErrorActionPreference = ""Stop""
function Fail([string]$reason) { Write-Output (""FAIL: "" + $reason); exit 1 }
function Get-LoadedByLocation([string]$path) {
    $full = [System.IO.Path]::GetFullPath($path)
    [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
        $_.Location -and [String]::Equals([System.IO.Path]::GetFullPath($_.Location), $full, [StringComparison]::OrdinalIgnoreCase)
    }
}
function Get-FileNotFound($caught) {
    $walker = $caught
    while ($walker -and -not ($walker -is [System.IO.FileNotFoundException])) { $walker = $walker.InnerException }
    $walker
}
Add-Type -Path $DbatoolsDll

if ($Mode -eq ""failures"") {
    # Leg 1: Rmo missing, Replication present -> the FIRST load fails; the Replication
    # file must remain unloaded, proving Load never reached the second file (Rmo-first).
    $caught = $null
    try { [Dataplat.Dbatools.dbaSystem.ReplicationLibrary]::Load($RmoMissingRoot) } catch { $caught = $_.Exception }
    $notFound = Get-FileNotFound $caught
    if (-not $notFound) { Fail ""leg1: expected FileNotFoundException for missing Rmo"" }
    if ($notFound.FileName -notlike ""*Rmo.dll*"") { Fail (""leg1: wrong file failed: "" + $notFound.FileName) }
    if (Get-LoadedByLocation (Join-Path (Join-Path $RmoMissingRoot ""lib"") ""Microsoft.SqlServer.Replication.dll"")) {
        Fail ""leg1: Replication loaded despite Rmo failing first - order broken""
    }

    # Leg 2: Rmo present, Replication missing -> Rmo loads (first), then the SECOND load
    # fails. Rmo's exact-location load afterward proves it was attempted before the failure.
    $caught = $null
    try { [Dataplat.Dbatools.dbaSystem.ReplicationLibrary]::Load($ReplicationMissingRoot) } catch { $caught = $_.Exception }
    $notFound = Get-FileNotFound $caught
    if (-not $notFound) { Fail ""leg2: expected FileNotFoundException for missing Replication"" }
    if ($notFound.FileName -notlike ""*Replication.dll*"") { Fail (""leg2: wrong file failed: "" + $notFound.FileName) }
    if ($notFound.FileName -like ""*Rmo.dll*"") { Fail ""leg2: failure should be the Replication load, not Rmo"" }
    if (-not (Get-LoadedByLocation (Join-Path (Join-Path $ReplicationMissingRoot ""lib"") ""Microsoft.SqlServer.Rmo.dll""))) {
        Fail ""leg2: Rmo not loaded from its exact path before the Replication failure - order broken""
    }
} else {
    # Success legs in a FRESH process: BOTH assemblies must load from the exact
    # complete-root lib paths.
    [Dataplat.Dbatools.dbaSystem.ReplicationLibrary]::Load($CompleteRoot)
    if (-not (Get-LoadedByLocation (Join-Path (Join-Path $CompleteRoot ""lib"") ""Microsoft.SqlServer.Rmo.dll""))) {
        Fail ""success: Rmo not loaded from the exact lib path""
    }
    if (-not (Get-LoadedByLocation (Join-Path (Join-Path $CompleteRoot ""lib"") ""Microsoft.SqlServer.Replication.dll""))) {
        Fail ""success: Replication not loaded from the exact lib path""
    }

    # Idempotence - re-running with everything loaded succeeds, like re-running the
    # helper's Add-Type calls.
    [Dataplat.Dbatools.dbaSystem.ReplicationLibrary]::Load($CompleteRoot)
}
Write-Output ""ALL-LEGS-PASS""
exit 0
";

        private static void RunLifecycleChild(string mode, string rmoMissing, string replicationMissing, string complete)
        {
            string script = Path.Combine(Path.GetTempPath(), "dbatools-tests-rmo-child-" + Guid.NewGuid().ToString("N") + ".ps1");
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
                    "-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -DbatoolsDll \"{1}\" -Mode {2} -RmoMissingRoot \"{3}\" -ReplicationMissingRoot \"{4}\" -CompleteRoot \"{5}\"",
                    script, dbatoolsDll, mode, rmoMissing, replicationMissing, complete);
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
        public void Load_FailureLegs_ProveRmoLoadsFirst()
        {
            string rmoMissing = NewRoot(false, true);
            string replicationMissing = NewRoot(true, false);
            try
            {
                RunLifecycleChild("failures", rmoMissing, replicationMissing, "unused");
            }
            finally
            {
                TryRemove(rmoMissing);
                TryRemove(replicationMissing);
            }
        }

        [TestMethod]
        public void Load_SuccessLegs_LoadBothFromExactLibPathsAndStayIdempotent()
        {
            string complete = NewStandInRoot();
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
            // In PS a failed Get-DbatoolsLibraryPath still lands in the same catch ->
            // Stop-Function flow; the port surfaces it as ArgumentNullException before
            // touching the disk.
            Assert.ThrowsException<ArgumentNullException>(delegate { ReplicationLibrary.Load(null); });
            Assert.ThrowsException<ArgumentNullException>(delegate { ReplicationLibrary.Load(String.Empty); });
        }
    }
}
