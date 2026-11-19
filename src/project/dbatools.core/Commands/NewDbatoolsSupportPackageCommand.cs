#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a diagnostic support-package zip (message log, errors, console buffer, CIM
/// system facts, history, modules, assemblies, optional variables). Port of
/// public/New-DbatoolsSupportPackage.ps1 (W1-031). The COLLECTION body runs VERBATIM as a
/// module-scoped nested script (W1-025 pattern): Get-ShellBuffer reads the REAL host
/// buffer, Get-History/Get-Module/Get-PSSnapin see the live session, Write-ProgressHelper
/// and Stop-Function resolve as the private module functions, and the nested script
/// declares an $EnableException parameter so Stop-Function's dynamic-scope default picks
/// up this cmdlet's value exactly like the function's scope chain did. Nested
/// Stop-Function warning attribution differs (the accepted nested-source-tag class). The
/// begin-block messages, the ShouldProcess gate, and the Critical announcement ride the
/// cmdlet natively with proper FunctionName attribution.
/// Surface pinned by migration/baselines/New-DbatoolsSupportPackage.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbatoolsSupportPackage", SupportsShouldProcess = true)]
public sealed class NewDbatoolsSupportPackageCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Position = 0)]
    public string? Path { get; set; }

    [Parameter(Position = 1)]
    public string[]? Variables { get; set; }

    [Parameter]
    public SwitchParameter PassThru { get; set; }

    protected override void BeginProcessing()
    {
        // PS param default: [string]$Path = "$($env:USERPROFILE)\Desktop" at bind time.
        if (!TestBound("Path"))
            Path = Environment.GetEnvironmentVariable("USERPROFILE") + "\\Desktop";

        // PS: if (-not (Test-Path $Path)) { $Path = $home }
        System.Collections.Hashtable testParams = new();
        testParams["Path"] = Path;
        bool pathExists = false;
        foreach (PSObject item in NestedCommand.Invoke(this, "Test-Path", testParams))
        {
            if (LanguagePrimitives.IsTrue(item))
                pathExists = true;
        }
        if (!pathExists)
            Path = LanguagePrimitives.ConvertTo<string>(SessionState.PSVariable.GetValue("home"));

        WriteMessage(MessageLevel.InternalComment, "Starting");
        WriteMessage(MessageLevel.Verbose, "Bound parameters: " + string.Join(", ", MyInvocation.BoundParameters.Keys));
    }

    protected override void ProcessRecord()
    {
        if (ShouldProcess("Creating a Support Package for diagnosing Dbatools"))
        {
            // PS: [IO.Path]::Combine($Path, "dbatools_support_pack_$(Get-Date -Format "yyyy_MM_dd-HH_mm_ss").xml")
            string filePathXml = System.IO.Path.Combine(Path ?? "", "dbatools_support_pack_" + DateTime.Now.ToString("yyyy_MM_dd-HH_mm_ss") + ".xml");
            string filePathZip = System.Text.RegularExpressions.Regex.Replace(filePathXml, "\\.xml$", ".zip");

            WriteMessage(MessageLevel.Critical, "Will write the final output to: " + filePathZip + @"
Please submit this file to the team, to help with troubleshooting whatever issue you encountered. Be aware that this package contains a lot of information including your input history in the console. Please make sure no sensitive data (such as passwords) can be caught this way.
Ideally start a new console, perform the minimal steps required to reproduce the issue, then run this command. This will make it easier for us to troubleshoot and you won't be sending us the keys to your castle.");

            foreach (PSObject item in NestedCommand.InvokeScoped(this, CollectAndPackScript, filePathXml, filePathZip, Variables, TestBound("Variables"), EnableException.ToBool()))
                WriteObject(item);
        }
    }

    protected override void EndProcessing()
    {
        WriteMessage(MessageLevel.InternalComment, "Ending");
    }

    // The collection body is VERBATIM from the function's process block (comments
    // included); the $EnableException parameter feeds Stop-Function's dynamic-scope
    // default just like the function's own scope did.
    private const string CollectAndPackScript = """
param($filePathXml, $filePathZip, $Variables, $VariablesBound, $EnableException)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($filePathXml, $filePathZip, $Variables, $VariablesBound, $EnableException)

    #region Helper functions
    function Get-ShellBuffer {
        [CmdletBinding()]
        param ()

        try {
            # Define limits
            $rec = New-Object System.Management.Automation.Host.Rectangle
            $rec.Left = 0
            $rec.Right = $host.ui.rawui.BufferSize.Width - 1
            $rec.Top = 0
            $rec.Bottom = $host.ui.rawui.BufferSize.Height - 1

            # Load buffer
            $buffer = $host.ui.rawui.GetBufferContents($rec)

            # Convert Buffer to list of strings
            $int = 0
            $lines = @()
            while ($int -le $rec.Bottom) {
                $n = 0
                $line = ""
                while ($n -le $rec.Right) {
                    $line += $buffer[$int, $n].Character
                    $n++
                }
                $line = $line.TrimEnd()
                $lines += $line
                $int++
            }

            # Measure empty lines at the beginning
            $int = 0
            $temp = $lines[$int]
            while ($temp -eq "") { $int++; $temp = $lines[$int] }

            # Measure empty lines at the end
            $z = $rec.Bottom
            $temp = $lines[$z]
            while ($temp -eq "") { $z--; $temp = $lines[$z] }

            # Skip the line launching this very function
            $z--

            # Measure empty lines at the end (continued)
            $temp = $lines[$z]
            while ($temp -eq "") { $z--; $temp = $lines[$z] }

            # Cut results to the limit and return them
            return $lines[$int .. $z]
        } catch {
            # here to avoid an empty catch
            $null = 1
        }
    }
    #endregion Helper functions

    $stepCounter = 0
    $hash = @{ }
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting dbatools logged messages (Get-DbatoolsLog)"
    $hash["Messages"] = Get-DbatoolsLog
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting dbatools logged errors (Get-DbatoolsLog -Errors)"
    $hash["Errors"] = Get-DbatoolsLog -Errors
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting copy of console buffer (what you can see on your console)"
    $hash["ConsoleBuffer"] = Get-ShellBuffer
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting Operating System information (Win32_OperatingSystem)"
    $hash["OperatingSystem"] = Get-DbaCmObject -ClassName Win32_OperatingSystem
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting CPU information (Win32_Processor)"
    $hash["CPU"] = Get-DbaCmObject -ClassName Win32_Processor
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting Ram information (Win32_PhysicalMemory)"
    $hash["Ram"] = Get-DbaCmObject -ClassName Win32_PhysicalMemory
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting PowerShell & .NET Version (`$PSVersionTable)"
    $hash["PSVersion"] = $PSVersionTable
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting Input history (Get-History)"
    $hash["History"] = Get-History
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting list of loaded modules (Get-Module)"
    $hash["Modules"] = Get-Module
    # Snapins not supported in Core: https://github.com/PowerShell/PowerShell/issues/6135
    if ($PSVersionTable.PSEdition -ne 'Core') {
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting list of loaded snapins (Get-PSSnapin)"
        $hash["SnapIns"] = Get-PSSnapin
    }
    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting list of loaded assemblies (Name, Version, and Location)"
    $hash["Assemblies"] = [appdomain]::CurrentDomain.GetAssemblies() | Select-Object CodeBase, FullName, Location, ImageRuntimeVersion, GlobalAssemblyCache, IsDynamic

    if ($VariablesBound) {
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding variables specified for export: $($Variables -join ", ")"
        $hash["Variables"] = $Variables | Get-Variable -ErrorAction Ignore
    }

    $data = [PSCustomObject]$hash

    try {
        $data | Export-Clixml -Path $filePathXml -ErrorAction Stop
    } catch {
        Stop-Function -Message "Failed to export dump to file." -ErrorRecord $_ -Target $filePathXml
        return
    }

    try {
        Compress-Archive -Path $filePathXml -DestinationPath $filePathZip -ErrorAction Stop
        Get-ChildItem -Path $filePathZip
    } catch {
        Stop-Function -Message "Failed to pack dump-file into a zip archive. Please do so manually before submitting the results as the unpacked xml file will be rather large." -ErrorRecord $_ -Target $filePathZip
        return
    }
    Remove-Item -Path $filePathXml -ErrorAction Ignore
} $filePathXml $filePathZip $Variables $VariablesBound $EnableException
""";
}
