#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests whether @@servername matches the instance's actual network name (rename
/// detection). Port of public/Test-DbaInstanceName.ps1 (W3-109). WHOLE-RECORD verbatim
/// hop (single process block, no begin/end). CLASSIFICATION TABLE (SqlInstance is the
/// VFP; promoted question answered): NO param mutations; all locals per-iteration - no
/// sentinel. PRESERVED SOURCE QUIRKS, smoke-pinned: the SSRS branch is DEAD CODE - the
/// guard reads UNDECLARED $SkipSsrs/$NoWarning (stale from a parameter rename; the
/// live -ExcludeSsrs switch is itself unread), `$null -eq $false` is False on both
/// sides so Get-DbaService is NEVER called and Warnings is always "N/A" (the smoke
/// shadow pins zero Get-DbaService calls in both worlds); the "Checking for..."
/// verbose interpolates the likewise-undeclared $serverName/$netBiosName (empty). In
/// the hop those undeclared reads scope-walk exactly like the function's (both end at
/// module scope). NO ShouldProcess (plain CmdletBinding, no WhatIf/Confirm plumbing);
/// no Test-FunctionInterrupt; the single Stop-Function uses -Continue INSIDE the
/// per-record foreach (the W3-102 relay and W3-103 latch classes verified N/A).
/// Hop-frame Stop-Function/Write-Message carry -FunctionName (W1-090). No bind-time
/// casts. [OutputType(typeof(System.Collections.ArrayList))] mirrored - part of the
/// pinned surface. Surface pinned by migration/baselines/Test-DbaInstanceName.json
/// (no sets, implicit positions: SqlInstance DbaInstanceParameter[] Mandatory pos0
/// VFP, SqlCredential pos1).
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaInstanceName")]
[OutputType(typeof(ArrayList))]
public sealed class TestDbaInstanceNameCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Credential for SQL Server authentication.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Skips the SSRS check (unread in the source - preserved as-is).</summary>
    [Parameter]
    public SwitchParameter ExcludeSsrs { get; set; }

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
            SqlInstance, SqlCredential, ExcludeSsrs.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only: explicit
    // -FunctionName Test-DbaInstanceName on hop-frame Stop-Function/Write-Message
    // (W1-090). The dead SSRS guard, its undeclared $SkipSsrs/$NoWarning reads, and
    // the undeclared $serverName/$netBiosName verbose ride AS-IS.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $ExcludeSsrs, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, $ExcludeSsrs, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaInstanceName
            }

            if ($server.IsClustered) {
                Write-Message -Level Warning -Message "$instance is a cluster. Renaming clusters is not supported by Microsoft." -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            }

            $configuredServerName = $server.Query("SELECT @@servername AS ServerName").ServerName
            Write-Message -Level Verbose -Message "configuredServerName from @@servername is $configuredServerName" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"

            $instanceName = $server.InstanceName
            Write-Message -Level Verbose -Message "server.InstanceName is $instanceName" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            $netName = $server.NetName
            Write-Message -Level Verbose -Message "server.NetName is $netName" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"

            if ($instanceName.Length -eq 0) {
                $newServerName = $netName
                $instanceName = "MSSQLSERVER"
            } else {
                $newServerName = "$netName\$instanceName"
            }
            Write-Message -Level Verbose -Message "newServerName is $newServerName" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"

            # output some other properties that migth help to get the new servername
            Write-Message -Level Debug -Message "server.ComputerName is $($server.ComputerName)" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            Write-Message -Level Debug -Message "server.ComputerNamePhysicalNetBIOS is $($server.ComputerNamePhysicalNetBIOS)" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            Write-Message -Level Debug -Message "server.DomainInstanceName is $($server.DomainInstanceName)" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            Write-Message -Level Debug -Message "server.Name is $($server.Name)" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            Write-Message -Level Debug -Message "server.NetName is $($server.NetName)" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            Write-Message -Level Debug -Message "server.ServiceName is $($server.ServiceName)" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"

            $serverInfo = [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                ServerName     = $configuredServerName
                NewServerName  = $newServerName
                RenameRequired = $newServerName -ne $configuredServerName
                Updatable      = "N/A"
                Warnings       = $null
                Blockers       = $null
            }

            $reasons = @()
            $ssrsService = "SQL Server Reporting Services ($instanceName)"

            Write-Message -Level Verbose -Message "Checking for $serverName on $netBiosName" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            $rs = $null
            if ($SkipSsrs -eq $false -or $NoWarning -eq $false) {
                try {
                    $rs = Get-DbaService -ComputerName $instance.ComputerName -InstanceName $server.ServiceName -Type SSRS -EnableException -WarningAction Stop
                } catch {
                    Write-Message -Level Warning -Message "Unable to pull information on $ssrsService." -ErrorRecord $_ -Target $instance -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
                }
            }

            if ($null -ne $rs -or $rs.Count -gt 0) {
                if ($rs.State -eq 'Running') {
                    $rstext = "$ssrsService must be stopped and updated."
                } else {
                    $rstext = "$ssrsService exists. When it is started again, it must be updated."
                }
                $serverInfo.Warnings = $rstext
            } else {
                $serverInfo.Warnings = "N/A"
            }

            # check for mirroring
            $mirroredDb = $server.Databases | Where-Object { $_.IsMirroringEnabled -eq $true }

            Write-Message -Level Debug -Message "Found the following mirrored dbs: $($mirroredDb.Name)" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"

            if ($mirroredDb.Length -gt 0) {
                $dbs = $mirroredDb.Name -join ", "
                $reasons += "Databases are being mirrored: $dbs"
            }

            # check for replication
            $sql = "SELECT name FROM sys.databases WHERE is_published = 1 OR is_subscribed = 1 OR is_distributor = 1"
            Write-Message -Level Debug -Message "SQL Statement: $sql" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            $replicatedDb = $server.Query($sql)

            if ($replicatedDb.Count -gt 0) {
                $dbs = $replicatedDb.Name -join ", "
                $reasons += "Database(s) are involved in replication: $dbs"
            }

            # check for even more replication
            $sql = "SELECT srl.remote_name AS RemoteLoginName FROM sys.remote_logins srl JOIN sys.sysservers sss ON srl.server_id = sss.srvid"
            Write-Message -Level Debug -Message "SQL Statement: $sql" -FunctionName Test-DbaInstanceName -ModuleName "dbatools"
            $results = $server.Query($sql)

            if ($results.RemoteLoginName.Count -gt 0) {
                $remoteLogins = $results.RemoteLoginName -join ", "
                $reasons += "Remote logins still exist: $remoteLogins"
            }

            if ($reasons.Length -gt 0) {
                $serverInfo.Updatable = $false
                $serverInfo.Blockers = $reasons
            } else {
                $serverInfo.Updatable = $true
                $serverInfo.Blockers = "N/A"
            }

            $serverInfo
        }
    }
} $SqlInstance $SqlCredential $ExcludeSsrs $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
