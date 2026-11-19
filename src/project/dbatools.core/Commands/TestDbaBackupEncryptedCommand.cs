#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Analyzes backup files to determine encryption status (backup encryption or TDE). Port of
/// public/Test-DbaBackupEncrypted.ps1 (W3-105). The function is process-only with no begin/end;
/// each pipeline record rides ONE module hop in ProcessRecord (GetDbaExtendedProtection
/// precedent): connect, then the per-$FilePath loop running RESTORE HEADERONLY / FILELISTONLY
/// and emitting one PSCustomObject per file (Convert-ByteToHexString, [dbnull] comparisons, the
/// thumbprint-exception branch). ONE piece of cross-record state (codex): the conditionally
/// assigned $results persists across records in the function world, so the hop seeds/harvests it
/// through the __dbatoolsTbeResultsCarrier sentinel with an assigned flag; the hop body is
/// otherwise verbatim, and there are no $PSBoundParameters reads. Surface pinned by migration/baselines/Test-DbaBackupEncrypted.json (SqlInstance
/// pos0 VFPBPN; SqlCredential pos1; FilePath pos2 mandatory VFPBPN alias FullName/Path; no SSP;
/// no OutputType).
///
/// DEF-001: the per-file Stop-Function -Continue (RESTORE HEADERONLY failure) throws under
/// -EnableException mid-loop, so objects already emitted for earlier files would be lost by a
/// buffered foreach - delivered via InvokeScopedStreaming, the streaming graft.
///
/// DEF-006: every hop-level Write-Message carries -FunctionName Test-DbaBackupEncrypted
/// -ModuleName "dbatools" (explicit -FunctionName suppresses frame auto-resolution, so
/// -ModuleName must be restored or it logs &lt;Unknown&gt;); the two Stop-Function calls carry
/// -FunctionName Test-DbaBackupEncrypted. No helpers, so every site is hop-level.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaBackupEncrypted")]
public sealed class TestDbaBackupEncryptedCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0, ValueFromPipelineByPropertyName = true)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The backup file path(s) to analyze for encryption status.</summary>
    [Parameter(Position = 2, Mandatory = true, ValueFromPipelineByPropertyName = true)]
    [Alias("FullName", "Path")]
    public string[]? FilePath { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item?.Properties["__dbatoolsTbeResultsCarrier"] is not null &&
                     LanguagePrimitives.IsTrue(item.Properties["__dbatoolsTbeResultsCarrier"].Value))
            {
                // DEF-011/012: $results cross-record persistence (see ProcessScript note).
                _carriedResults = item.Properties["Results"]?.Value;
                _carriedResultsAssigned = item.Properties["ResultsAssigned"]?.Value;
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, FilePath, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"),
            _carriedResults, _carriedResultsAssigned);
    }

    private object? _carriedResults;
    private object? _carriedResultsAssigned;

    // PS: process body per record (single hop; no begin/end). Intentional rewrites: DEF-006
    // attribution on Write-Message + -FunctionName on Stop-Function; [CmdletBinding()] on the
    // module hop for common-parameter propagation; and the $results cross-record carrier
    // (seed from $__carriedResults when assigned, emit via the sentinel below).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $FilePath, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug, $__carriedResults, $__carriedResultsAssigned)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$FilePath, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug, $__carriedResults, $__carriedResultsAssigned)
    # DEF-011/012 (codex): $results is conditionally assigned and the function world's process
    # scope carries the prior record's value; seed ONLY when the carrier says it was assigned
    # (restoring null unconditionally would break unassigned scope-walk semantics).
    if ($null -ne $__carriedResultsAssigned -and [bool]$__carriedResultsAssigned) { $results = $__carriedResults }
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Test-DbaBackupEncrypted
        return
    }

    #for each database, create custom object for return set.
    foreach ($file in $FilePath) {
        $encrypted = $false
        $thumbprint = $null
        try {
            $file = $file.Replace("'", "''")
            $sql = "RESTORE HEADERONLY FROM DISK = N'$file'"
            Write-Message -Level Verbose -Message "SQL Query: $sql" -FunctionName Test-DbaBackupEncrypted -ModuleName "dbatools"
            $results = $server.Query($sql)
        } catch {
            Stop-Function -Message "Failure on $SqlInstance" -ErrorRecord $PSItem -Target $SqlInstance -Continue -FunctionName Test-DbaBackupEncrypted
        }

        if ($results.KeyAlgorithm -isnot [dbnull] -or
            $results.EncryptorThumbprint -isnot [dbnull] -or
            $results.EncryptorType -isnot [dbnull]) {

            Write-Message -Level Verbose -Message "KeyAlgorithm or EncryptorThumbprint or EncryptorType is not null" -FunctionName Test-DbaBackupEncrypted -ModuleName "dbatools"
            $encrypted = $true
        }

        try {
            $sql = "RESTORE FILELISTONLY FROM DISK = N'$file'"
            $filelistonly = $server.Query($sql)
            $thumb = ($filelistonly | Where-Object TDEThumbprint | Select-Object -First 1).TDEThumbprint

            if ($thumb.Length -gt 1) {
                Write-Message -Level Verbose -Message "Thumbprint found: $($filelistonly.TDEThumbprint)" -FunctionName Test-DbaBackupEncrypted -ModuleName "dbatools"
                $encrypted = $true
                $thumbprint = Convert-ByteToHexString $thumb
            }
        } catch {
            if ($PSItem -match "thumbprint") {
                Write-Message -Level Verbose -Message "Thumbprint referenced in exception" -FunctionName Test-DbaBackupEncrypted -ModuleName "dbatools"
                $encrypted = $true
            } else {
                Write-Message -Level Verbose -Message "Caught exception: $PSItem" -FunctionName Test-DbaBackupEncrypted -ModuleName "dbatools"
            }
        }

        Write-Message -Level Verbose -Message "Checking $file" -FunctionName Test-DbaBackupEncrypted -ModuleName "dbatools"
        [PSCustomObject]@{
            ComputerName        = $server.ComputerName
            InstanceName        = $server.ServiceName
            SqlInstance         = $server.DomainInstanceName
            FilePath            = $file
            BackupName          = $results.BackupName | Select-Object -First 1
            Encrypted           = $encrypted
            KeyAlgorithm        = $results.KeyAlgorithm | Select-Object -First 1
            EncryptorThumbprint = $results.EncryptorThumbprint | Select-Object -First 1
            EncryptorType       = $results.EncryptorType | Select-Object -First 1
            TDEThumbprint       = $thumbprint
            Compressed          = ($results | Select-Object -First 1).Compressed -eq $true
        }
    }
    [pscustomobject]@{ __dbatoolsTbeResultsCarrier = $true; Results = $results; ResultsAssigned = [bool](Get-Variable results -Scope 0 -ErrorAction SilentlyContinue) }
} $SqlInstance $SqlCredential $FilePath $EnableException $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug $__carriedResults $__carriedResultsAssigned @__commonParameters 3>&1 2>&1
""";
}
