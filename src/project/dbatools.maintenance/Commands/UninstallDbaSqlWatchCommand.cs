#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Completely removes the SqlWatch monitoring solution from a target instance - dropping every
/// SqlWatch table/view/stored-procedure/function/assembly/table-type/Service-Broker object and
/// Agent job and Extended Events session, then unregistering the DACPAC. The object discovery,
/// SMO drops, DACPAC unregister, and ShouldProcess flow remain a module-scoped PowerShell
/// compatibility hop; this cmdlet supplies the real ShouldProcess runtime. SqlInstance is the
/// only pipeline input and each record's per-instance body carries no cross-record state, so the
/// body is a single per-record process hop with no carrier. DACPAC unregister and the whole flow
/// require Windows PowerShell - on Core the command refuses. Surface pinned by
/// migration/baselines/Uninstall-DbaSqlWatch.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Uninstall, "DbaSqlWatch", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class UninstallDbaSqlWatchCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database containing the SqlWatch installation to remove.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string Database { get; set; } = "master";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Single per-record process hop: SqlInstance is the only pipeline input and every per-instance
        // variable ($server/$tables/$views/...) is reassigned inside the foreach, so there is no
        // function-scoped accumulator to carry across records. Each Stop-Function branch `return`s or,
        // where the source uses -Continue, continues the hop's own foreach - matching the source.
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
            SqlInstance, SqlCredential, Database, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Database, $EnableException, $__realCmdlet)

    if (Test-FunctionInterrupt) {
        return
    }

    if ($PSEdition -eq 'Core') {
        Stop-Function -Message "PowerShell Core is not supported, please use Windows PowerShell." -FunctionName Uninstall-DbaSqlWatch
        return
    }
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Uninstall-DbaSqlWatch
        }

        # get SqlWatch objects
        $tables = Get-DbaDbTable -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" -or $PSItem.Name -like "dbachecks*" -or $PSItem.Name -eq "__RefactorLog" } | Sort-Object $PSItem.createdate -Descending
        $views = Get-DbaDbView -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "vw_sqlwatch_*" } | Sort-Object $PSItem.createdate -Descending
        $sprocs = Get-DbaDbStoredProcedure -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "usp_sqlwatch_*" -or $PSItem.Name -like "Stream*" } | Sort-Object $PSItem.createdate -Descending
        $funcs = Get-DbaDbUdf -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "ufn_sqlwatch_*" -or $PSItem.Name -like "Get*" -or $PSItem.Name -like "Read*" -and $PSItem.Name -notin "ufn_sqlwatch_get_threshold_comparator", "ufn_sqlwatch_clean_sql_text" } | Sort-Object $PSItem.createdate
        $funcs += Get-DbaDbUdf -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -in "ufn_sqlwatch_get_threshold_comparator", "ufn_sqlwatch_clean_sql_text" }
        $agentJobs = Get-DbaAgentJob -SqlInstance $server | Where-Object { $PSItem.Name -like "SqlWatch-*" }
        $XESessions = Get-DbaXESession -SqlInstance $server | Where-Object { $PSItem.Name -like "SQLWATCH_*" }
        $Assemblies = Get-DbaDbAssembly -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "SqlWatch*" }
        $TableTypes = Get-DbaDbUserDefinedTableType -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "utype_*" }
        $BrokerQueues = Get-DbaDbServiceBrokerQueue -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" }
        $BrokerServices = Get-DbaDbServiceBrokerService -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch SQL Agent jobs")) {
            try {
                Write-Message -Level Verbose -Message "Removing SQL Agent jobs from $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                $agentJobs | Remove-DbaAgentJob -Confirm:$false | Out-Null
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch Agent Jobs on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch stored procedures")) {
            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch stored procedures from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($sprocs) {
                    $sprocs | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch stored procedures from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch views")) {
            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch views from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($views) {
                    $views | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch views from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch functions")) {
            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch functions from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($funcs) {
                    $funcs | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch functions from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch tables")) {
            try {
                Write-Message -Level Verbose -Message "Removing foreign keys from SqlWatch tables in $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($tables.ForeignKeys) {
                    $tables.ForeignKeys | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all foreign keys from SqlWatch tables in $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }

            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch tables from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($tables) {
                    $tables | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch tables from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch Assemblies")) {
            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch assemblies from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($Assemblies) {
                    $Assemblies | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch assemblies from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch Table Types")) {
            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch Table Types from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($TableTypes) {
                    $TableTypes | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch Table Types from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch Service Broker Services")) {
            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch service broker services from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($BrokerServices) {
                    $BrokerServices | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch broker services from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch Service Broker Queues")) {
            try {
                Write-Message -Level Verbose -Message "Removing SqlWatch service broker queues from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                if ($BrokerQueues) {
                    $BrokerQueues | ForEach-Object { $PSItem.Drop() }
                }
            } catch {
                Stop-Function -Message "Could not remove all SqlWatch broker queues from $database on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Removing SqlWatch XE Sessions")) {
            try {
                if ($XESessions) {
                    Remove-DbaXESession -SqlInstance $Server -Session $XESessions.Name -Confirm:$false
                }
            } catch {
                Stop-Function -Message "Could not remove all XE Session for SqlWatch on $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Uninstall-DbaSqlWatch
            }
        }

        if ($__realCmdlet.ShouldProcess($server, "Unpublishing DACPAC")) {
            try {
                Write-Message -Level Verbose -Message "Unpublishing SqlWatch DACPAC from $database on $server." -FunctionName Uninstall-DbaSqlWatch -ModuleName "dbatools"
                $connectionString = $server.ConnectionContext.ConnectionString | Convert-ConnectionString
                $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connectionString
                $dacServices.Unregister($Database)
            } catch {
                Stop-Function -Message "Failed to unpublish SqlWatch DACPAC from $database on $server." -ErrorRecord $_ -FunctionName Uninstall-DbaSqlWatch
            }
        }
    }
} $SqlInstance $SqlCredential $Database $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
