#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes user databases with the source's three-method fallback (KillDatabase ->
/// single_user+DROP -> SMO Drop). Port of public/Remove-DbaDatabase.ps1 (W3-074). The
/// process body rides one VERBATIM module hop per record; every record is SELF-CONTAINED
/// because the parameter sets are mutually exclusive: in the "instance" set process fires
/// once and $InputObject accumulates only within that invocation's SqlInstance loop; in
/// the "databases" set the piped $InputObject rebinds every record - so no sentinel and
/// no rebind discriminator are needed (the W3-063 shape). PARAMETER SETS mirrored from
/// the baseline including the PHANTOM default set: DefaultParameterSetName "Default" has
/// NO member parameters, so a zero-argument invocation resolves to Default, binds
/// nothing, and the command silently does nothing - source quirk preserved. Three
/// $Pscmdlet.ShouldProcess gates route to the REAL cmdlet (ConfirmImpact HIGH mirrored);
/// the interpolated single_user/DROP T-SQL, the private Remove-TeppCacheItem and
/// Get-ErrorMessage calls, and the system-db exclusion ride the hop verbatim. NO
/// WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Remove-DbaDatabase.json (no positions, Database object[] Alias
/// Name Mandatory instance-set, InputObject Database[] Mandatory VFP databases-set).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class RemoveDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "instance")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The user database(s) to remove.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "instance")]
    [Alias("Name")]
    public object[]? Database { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, ParameterSetName = "databases")]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, InputObject, EnableException.ToBool(),
            this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only: $Pscmdlet ->
    // $__realCmdlet and explicit -FunctionName Remove-DbaDatabase on Stop-Function/
    // Write-Message (W1-090). The system-db exclusion comment, the interpolated
    // single_user/DROP T-SQL, and the private Remove-TeppCacheItem/Get-ErrorMessage
    // calls ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaDatabase
        }
        $InputObject += $server.Databases | Where-Object { $_.Name -in $Database }
    }

    # Excludes system databases as these cannot be deleted
    $system_dbs = @( "master", "model", "tempdb", "resource", "msdb" )
    $InputObject = $InputObject | Where-Object { $_.Name -notin $system_dbs }

    foreach ($db in $InputObject) {
        try {
            $server = $db.Parent
            if ($__realCmdlet.ShouldProcess("$db on $server", "KillDatabase")) {
                $server.KillDatabase($db.name)
                $server.Refresh()
                Remove-TeppCacheItem -SqlInstance $server -Type database -Name $db.name

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $db.name
                    Status       = "Dropped"
                }
            }
        } catch {
            try {
                if ($__realCmdlet.ShouldProcess("$db on $server", "alter db set single_user with rollback immediate then drop")) {
                    $null = $server.Query("IF EXISTS (SELECT * FROM sys.databases WHERE name = '$($db.name)' AND state = 0) ALTER DATABASE $db SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $db")

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Status       = "Dropped"
                    }
                }
            } catch {
                try {
                    if ($__realCmdlet.ShouldProcess("$db on $server", "SMO drop")) {
                        $dbName = $db.Name
                        $db.Parent.databases[$dbName].Drop()
                        $server.Refresh()

                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Status       = "Dropped"
                        }
                    }
                } catch {
                    Write-Message -Level Verbose -Message "Could not drop database $db on $server" -FunctionName Remove-DbaDatabase -ModuleName "dbatools"

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Status       = (Get-ErrorMessage -Record $_)
                    }
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
