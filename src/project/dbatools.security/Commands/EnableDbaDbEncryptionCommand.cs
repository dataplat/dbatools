#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Enables Transparent Data Encryption on one or more databases, creating an encryption key if needed.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that encryption-key creation,
/// the SMO Alter, the output shape, and dbatools stream and error handling stay observable-identical to
/// the script implementation.
/// </para>
/// <para>
/// The command is process-only, so it ships as a single hop per record. Database objects piped through
/// InputObject bind per record; when SqlInstance is supplied instead, the body fills InputObject from
/// Get-DbaDatabase within that record - so no cross-record state is carried. Force and EnableException
/// are switch parameters on the cmdlet but are carried into the hop as plain (untyped) values, because
/// a [switch] parameter in the inner [CmdletBinding()] scriptblock is excluded from positional binding
/// and would shift every following argument. Output streams out of the hop object by object rather than
/// being buffered, so each database's result reaches the pipeline before a later database in the same
/// record can raise a terminating -EnableException failure; a buffered collection would be discarded on
/// that throw and lose the earlier databases' output.
/// </para>
/// </remarks>
[Cmdlet(VerbsLifecycle.Enable, "DbaDbEncryption", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class EnableDbaDbEncryptionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases to enable encryption on.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The certificate used to encrypt the database encryption key.</summary>
    [Parameter(Position = 3)]
    [Alias("Certificate", "CertificateName")]
    public string? EncryptorName { get; set; }

    /// <summary>Database objects, typically piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Forces creation of the encryption key even when the certificate has not been backed up.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Enables encryption for one pipeline record.</summary>
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
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, EncryptorName, InputObject, Force.ToBool(),
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet and -FunctionName
    // on the direct Stop-Function/Write-Message calls (no nested named helper). Force and
    // EnableException are received as plain (untyped) params - never re-typed [switch] - because a
    // [switch] in the inner [CmdletBinding()] scriptblock is excluded from positional binding.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $EncryptorName, $InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [string]$EncryptorName, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($SqlInstance) {
        if (-not $Database) {
            Stop-Function -Message "You must specify Database or ExcludeDatabase when using SqlInstance" -FunctionName Enable-DbaDbEncryption
            return
        }
        # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
        $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
    }

    foreach ($db in $InputObject) {
        if ($db.DatabaseEncryptionKey) {
            $null = $db.DatabaseEncryptionKey.Refresh()
        }
        $server = $db.Parent
        if ($__realCmdlet.ShouldProcess($server.Name, "Enabling encryption on $($db.Name)")) {
            try {
                if (-not $db.DatabaseEncryptionKey.EncryptionAlgorithm) {
                    Write-Message -Level Verbose -Message "No Encryption Key found, creating one" -FunctionName Enable-DbaDbEncryption -ModuleName "dbatools"
                    $null = $db | New-DbaDbEncryptionKey -Force:$Force -EncryptorName $EncryptorName -EnableException
                }
                $db.EncryptionEnabled = $true
                $db.Alter()
                if ($db.DatabaseEncryptionKey) {
                    $null = $db.DatabaseEncryptionKey.Refresh()
                }
                $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Name as DatabaseName', EncryptionEnabled
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Enable-DbaDbEncryption
            }
        }
    }
} $SqlInstance $SqlCredential $Database $EncryptorName $InputObject $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
