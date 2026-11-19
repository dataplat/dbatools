#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes backup files from disk by retention policy. Port of public/Remove-DbaBackup.ps1
/// (W3-070). LAB-FREE row: pure filesystem, no SQL instance. No pipeline-bound parameters,
/// so ProcessRecord fires once per invocation - no sentinel, no F1 discriminator, no
/// Test-Bound reads (the source has none). TWO hops: the begin-block leading-period
/// warning rides a real BEGIN hop (the function emits it even when later pipeline input
/// fails to bind - a process-hop-top placement would lose that ordering), and the process
/// body rides one VERBATIM process hop. $PSCmdlet.ShouldProcess routes to the REAL cmdlet
/// (default ConfirmImpact Medium mirrored by omission, pinned by the suite's
/// CommandMetadata unit test). The hardcoded -EnableException on the inner Find-DbaBackup
/// call is SOURCE-VERBATIM (its validation throws terminate both worlds identically
/// regardless of the outer switch). [PsStringCast] on the three MANDATORY strings
/// (W1-032 class: null binds to "" and trips the same empty-string mandatory rejection
/// the script binder produces). NO WarningAction carrier (codex W3-005 r3). Surface
/// pinned by migration/baselines/Remove-DbaBackup.json (implicit positions 0-2, Path
/// Alias BackupFolder, HelpMessages verbatim incl. the source's unclosed-paren quirk).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaBackup", SupportsShouldProcess = true)]
public sealed class RemoveDbaBackupCommand : DbaBaseCmdlet
{
    /// <summary>Root directory searched recursively for backup files.</summary>
    [Parameter(Mandatory = true, Position = 0, HelpMessage = "Full path to the root level backup folder (ex. 'C:\\SQL\\Backups'")]
    [Alias("BackupFolder")]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>Backup file extension to remove, without the period.</summary>
    [Parameter(Mandatory = true, Position = 1, HelpMessage = "Backup File extension to remove (ex. bak, trn, dif)")]
    [PsStringCast]
    public string? BackupFileExtension { get; set; }

    /// <summary>Retention period (ex. 24h, 7d, 4w, 6m).</summary>
    [Parameter(Mandatory = true, Position = 2, HelpMessage = "Backup retention period. (ex. 24h, 7d, 4w, 6m)")]
    [PsStringCast]
    public string? RetentionPeriod { get; set; }

    /// <summary>Skip files whose Archive bit indicates they have not been archived yet.</summary>
    [Parameter]
    public SwitchParameter CheckArchiveBit { get; set; }

    /// <summary>Remove directories left empty after file cleanup.</summary>
    [Parameter]
    public SwitchParameter RemoveEmptyBackupFolder { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            BackupFileExtension,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            Path, BackupFileExtension, RetentionPeriod, CheckArchiveBit.ToBool(),
            RemoveEmptyBackupFolder.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block VERBATIM. Substitution only: explicit -FunctionName
    // Remove-DbaBackup on Write-Message (W1-090).
    private const string BeginScript = """
param($BackupFileExtension, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$BackupFileExtension, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Ensure BackupFileExtension does not begin with a .
    if ($BackupFileExtension -match "^[.]") {
        Write-Message -Level Warning -Message "Parameter -BackupFileExtension begins with a period '$BackupFileExtension'. A period is automatically prepended to -BackupFileExtension and need not be passed in." -FunctionName Remove-DbaBackup -ModuleName "dbatools"
    }
} $BackupFileExtension $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the ENTIRE process body VERBATIM. Substitutions only: $PSCmdlet ->
    // $__realCmdlet and explicit -FunctionName Remove-DbaBackup on Write-Message
    // (W1-090). The hardcoded -EnableException on Find-DbaBackup, the -EA alias,
    // and the stale-$Contents-on-enumeration-failure quirk all ride as-is.
    private const string ProcessScript = """
param($Path, $BackupFileExtension, $RetentionPeriod, $CheckArchiveBit, $RemoveEmptyBackupFolder, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path, [string]$BackupFileExtension, [string]$RetentionPeriod, $CheckArchiveBit, $RemoveEmptyBackupFolder, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Process stuff
    Write-Message -Message "Removing backups from $Path" -Level Verbose -FunctionName Remove-DbaBackup -ModuleName "dbatools"
    Find-DbaBackup -Path $Path -BackupFileExtension $BackupFileExtension -RetentionPeriod $RetentionPeriod -CheckArchiveBit:$CheckArchiveBit -EnableException |
        ForEach-Object {
            $file = $_
            if ($__realCmdlet.ShouldProcess($file.Directory.FullName, "Removing backup file $($file.Name)")) {
                try {
                    $file | Remove-Item -Force -EA Stop
                } catch {
                    Write-Message -Message "Failed to remove $file." -Level Warning -ErrorRecord $_ -FunctionName Remove-DbaBackup -ModuleName "dbatools"
                }
            }
        }
    Write-Message -Message "File Cleaning ended." -Level Verbose -FunctionName Remove-DbaBackup -ModuleName "dbatools"
    # Cleanup empty backup folders.
    if ($RemoveEmptyBackupFolder) {
        Write-Message -Message "Removing empty folders." -Level Verbose -FunctionName Remove-DbaBackup -ModuleName "dbatools"
        (Get-ChildItem -Directory -Path $Path -Recurse -ErrorAction SilentlyContinue -ErrorVariable EnumErrors).FullName |
            Sort-Object -Descending |
            ForEach-Object {
                $OrigPath = $_
                try {
                    $Contents = @(Get-ChildItem -Force $OrigPath -ErrorAction Stop)
                } catch {
                    Write-Message -Message "Can't enumerate $OrigPath." -Level Warning -ErrorRecord $_ -FunctionName Remove-DbaBackup -ModuleName "dbatools"
                }
                if ($Contents.Count -eq 0) {
                    return $_
                }
            } |
            ForEach-Object {
                $FolderPath = $_
                if ($__realCmdlet.ShouldProcess($Path, "Removing empty folder .$($FolderPath.Replace($Path, ''))")) {
                    try {
                        $FolderPath | Remove-Item -ErrorAction Stop
                    } catch {
                        Write-Message -Message "Failed to remove $FolderPath." -Level Warning -ErrorRecord $_ -FunctionName Remove-DbaBackup -ModuleName "dbatools"
                    }
                }
            }
        if ($EnumErrors) {
            Write-Message "Errors encountered enumerating folders." -Level Warning -ErrorRecord $EnumErrors -FunctionName Remove-DbaBackup -ModuleName "dbatools"
        }
        Write-Message -Message "Removed empty folders." -Level Verbose -FunctionName Remove-DbaBackup -ModuleName "dbatools"
    }
} $Path $BackupFileExtension $RetentionPeriod $CheckArchiveBit $RemoveEmptyBackupFolder $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
