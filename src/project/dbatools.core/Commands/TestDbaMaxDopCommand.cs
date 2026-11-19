#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests SQL Server MAXDOP configuration against recommended values based on CPU cores
/// and NUMA topology. Port of public/Test-DbaMaxDop.ps1; surface pinned by
/// migration/baselines/Test-DbaMaxDop.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaMaxDop")]
[OutputType(typeof(ArrayList))]
public sealed class TestDbaMaxDopCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
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
            new DbaInstanceParameter[] { instance }, SqlCredential, EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the source process foreach VERBATIM, one element per hop invocation (the
    // source loop line doubles as the guard loop, so every Stop-Function -Continue
    // lands on it exactly like the function world). The begin block's five note
    // constants are pure strings, re-declared at hop top. Substitution only:
    // -FunctionName appended to the six hop-frame Stop-Function/Write-Message sites
    // (the hop scriptblock has no function frame to stamp).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        $notesDopLT = "Before changing MaxDop, consider that the lower value may have been intentionally set."
        $notesDopGT = "Before changing MaxDop, consider that the higher value may have been intentionally set."
        $notesDopZero = "This is the default setting. Consider using the recommended value instead."
        $notesDopOne = "Some applications like SharePoint, Dynamics NAV, SAP, BizTalk has the need to use MAXDOP = 1. Please confirm that your instance is not supporting one of these applications prior to changing the MaxDop."
        $notesAsRecommended = "Configuration is as recommended."

        #Variable marked as unused by PSScriptAnalyzer
        #$hasScopedConfig = $false

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaMaxDop
            }

            #Get current configured value
            $maxDop = $server.Configuration.MaxDegreeOfParallelism.ConfigValue

            try {
                #represents the Number of NUMA nodes
                $sql = "SELECT COUNT(DISTINCT memory_node_id) AS NUMA_Nodes FROM sys.dm_os_memory_clerks WHERE memory_node_id != 64"
                $NumaNodes = $server.ConnectionContext.ExecuteScalar($sql)
            } catch {
                Stop-Function -Message "Failed to get Numa node count." -ErrorRecord $_ -Target $server -Continue -FunctionName Test-DbaMaxDop
            }

            try {
                #represents the Number of Processor Cores
                $sql = "SELECT COUNT(scheduler_id) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE'"
                $numberOfCores = $server.ConnectionContext.ExecuteScalar($sql)
            } catch {
                Stop-Function -Message "Failed to get number of cores." -ErrorRecord $_ -Target $server -Continue -FunctionName Test-DbaMaxDop
            }

            #Calculate Recommended Max Dop to instance
            #Server with single NUMA node
            if ($NumaNodes -eq 1) {
                if ($numberOfCores -lt 8) {
                    #Less than 8 logical processors - Keep MAXDOP at or below # of logical processors
                    $recommendedMaxDop = $numberOfCores
                } else {
                    #Equal or greater than 8 logical processors - Keep MAXDOP at 8
                    $recommendedMaxDop = 8
                }
            } else {
                #Server with multiple NUMA nodes
                if ($server.VersionMajor -ge 13) {
                    if (($numberOfCores / $NumaNodes) -lt 16) {
                        # On SQL2016+ - Less than 16 logical processors per NUMA node - Keep MAXDOP at or below # of logical processors per NUMA node
                        $recommendedMaxDop = [int]($numberOfCores / $NumaNodes)
                    } else {
                        # Greater than 16 logical processors per NUMA node - Keep MAXDOP at 16
                        $recommendedMaxDop = 16
                    }
                } else {
                    # Greater than 8 logical processors per NUMA node - Keep MAXDOP at 8
                    $recommendedMaxDop = 8
                    if (($numberOfCores / $NumaNodes) -lt 8) {
                        # On previous SQL Server versions - Less than 8 logical processors per NUMA node - Keep MAXDOP at or below # of logical processors per NUMA node
                        $recommendedMaxDop = [int]($numberOfCores / $NumaNodes)
                    } else {
                        # Greater than 8 logical processors per NUMA node - Keep MAXDOP at 8
                        $recommendedMaxDop = 8
                    }
                }
            }

            #Setting notes for instance max dop value
            $notes = $null
            if ($maxDop -eq 1) {
                $notes = $notesDopOne
            } else {
                if ($maxDop -ne 0 -and $maxDop -lt $recommendedMaxDop) {
                    $notes = $notesDopLT
                } else {
                    if ($maxDop -ne 0 -and $maxDop -gt $recommendedMaxDop) {
                        $notes = $notesDopGT
                    } else {
                        if ($maxDop -eq 0) {
                            $notes = $notesDopZero
                        } else {
                            $notes = $notesAsRecommended
                        }
                    }
                }
            }

            [PSCustomObject]@{
                ComputerName          = $server.ComputerName
                InstanceName          = $server.ServiceName
                SqlInstance           = $server.DomainInstanceName
                InstanceVersion       = $server.Version
                Database              = "N/A"
                DatabaseMaxDop        = "N/A"
                CurrentInstanceMaxDop = $maxDop
                RecommendedMaxDop     = $recommendedMaxDop
                NumaNodes             = $NumaNodes
                NumberOfCores         = $numberOfCores
                Notes                 = $notes
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, DatabaseMaxDop, CurrentInstanceMaxDop, RecommendedMaxDop, Notes

            # On SQL Server 2016 and higher, MaxDop can be set on a per-database level
            if ($server.VersionMajor -ge 13) {
                #Variable marked as unused by PSScriptAnalyzer
                #$hasScopedConfig = $true
                Write-Message -Level Verbose -Message "SQL Server 2016 or higher detected, checking each database's MaxDop." -FunctionName Test-DbaMaxDop -ModuleName "dbatools"

                $databases = $server.Databases | Where-Object { $_.IsSystemObject -eq $false }

                foreach ($database in $databases) {
                    if ($database.IsAccessible -eq $false) {
                        Write-Message -Level Verbose -Message "Database $database is not accessible." -FunctionName Test-DbaMaxDop -ModuleName "dbatools"
                        continue
                    }
                    Write-Message -Level Verbose -Message "Checking database '$($database.Name)'." -FunctionName Test-DbaMaxDop -ModuleName "dbatools"

                    $dbmaxdop = $database.MaxDop

                    [PSCustomObject]@{
                        ComputerName          = $server.ComputerName
                        InstanceName          = $server.ServiceName
                        SqlInstance           = $server.DomainInstanceName
                        InstanceVersion       = $server.Version
                        Database              = $database.Name
                        DatabaseMaxDop        = $dbmaxdop
                        CurrentInstanceMaxDop = $maxDop
                        RecommendedMaxDop     = $recommendedMaxDop
                        NumaNodes             = $NumaNodes
                        NumberOfCores         = $numberOfCores
                        Notes                 = if ($dbmaxdop -eq 0) { "Will use CurrentInstanceMaxDop value" } else { "$notes" }
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, DatabaseMaxDop, CurrentInstanceMaxDop, RecommendedMaxDop, Notes
                }
            }
        }
} $SqlInstance $SqlCredential $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
