#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Audits tempdb configuration against six best-practice rules. Port of
/// public/Test-DbaTempDbConfig.ps1 (W1-134). The complete per-record body rides an
/// advanced module-scoped PowerShell hop so private/public helpers, SMO and ETS access,
/// filtering/grouping/count coercion, dynamic continues, streams, and mocks retain the
/// function's engine behavior. Surface pinned by migration/baselines/Test-DbaTempDbConfig.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaTempDbConfig")]
public sealed class TestDbaTempDbConfigCommand : DbaBaseCmdlet
{
    /// <summary>SQL Server instances to inspect.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative SQL credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
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
            SqlInstance, SqlCredential, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($SqlInstance, $SqlCredential, $EnableException)

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaTempDbConfig
            }

            # removed previous assumption that 2016+ will have it enabled
            $tfCheck = $server.Databases['tempdb'].Query("DBCC TRACEON (3604); DBCC TRACESTATUS(-1)")
            $current = ($tfCheck.TraceFlag -join ',').Contains('1118')

            If ($server.VersionMajor -gt 12) {
                [PSCustomObject]@{
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Rule           = 'TF 1118 Enabled'
                    Recommended    = $false
                    CurrentSetting = $current
                    IsBestPractice = $true
                    Notes          = 'SQL Server 2016 and above has this functionality enabled by default.'
                }
            } else {
                [PSCustomObject]@{
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Rule           = 'TF 1118 Enabled'
                    Recommended    = $true
                    CurrentSetting = $current
                    IsBestPractice = $current -eq $true
                    Notes          = 'KB328551 describes how TF 1118 can benefit performance. SQL Server 2016 has this functionality enabled by default.'
                }
            }

            Write-Message -Level Verbose -Message "TF 1118 evaluated" -FunctionName Test-DbaTempDbConfig -ModuleName "dbatools"

            #get files and log files
            $tempdbFiles = Get-DbaDbFile -SqlInstance $server -Database tempdb
            [array]$dataFiles = $tempdbFiles | Where-Object Type -ne 1
            $logFiles = $tempdbFiles | Where-Object Type -eq 1
            Write-Message -Level Verbose -Message "TempDB file objects gathered" -FunctionName Test-DbaTempDbConfig -ModuleName "dbatools"

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Count'
                Recommended    = [Math]::Min(8, $server.Processors)
                CurrentSetting = $dataFiles.Count
                IsBestPractice = $dataFiles.Count -eq [Math]::Min(8, $server.Processors)
                Notes          = 'Microsoft recommends that the number of tempdb data files is equal to the number of logical cores up to 8.'
            }

            Write-Message -Level Verbose -Message "File counts evaluated." -FunctionName Test-DbaTempDbConfig -ModuleName "dbatools"

            #test file growth
            $percData = $dataFiles | Where-Object GrowthType -ne 'KB' | Measure-Object
            $percLog = $logFiles | Where-Object GrowthType -ne 'KB' | Measure-Object

            $totalCount = $percData.Count + $percLog.Count
            if ($totalCount -gt 0) {
                $totalCount = $true
            } else {
                $totalCount = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Growth in Percent'
                Recommended    = $false
                CurrentSetting = $totalCount
                IsBestPractice = $totalCount -eq $false
                Notes          = 'Set file growth to explicit values, not by percent.'
            }

            Write-Message -Level Verbose -Message "File growth settings evaluated." -FunctionName Test-DbaTempDbConfig -ModuleName "dbatools"
            #test file Location

            $cdata = ($dataFiles | Where-Object PhysicalName -like 'C:*' | Measure-Object).Count + ($logFiles | Where-Object PhysicalName -like 'C:*' | Measure-Object).Count
            if ($cdata -gt 0) {
                $cdata = $true
            } else {
                $cdata = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Location'
                Recommended    = $false
                CurrentSetting = $cdata
                IsBestPractice = $cdata -eq $false
                Notes          = "Do not place your tempdb files on C:\."
            }

            Write-Message -Level Verbose -Message "File locations evaluated." -FunctionName Test-DbaTempDbConfig -ModuleName "dbatools"

            #Test growth limits
            $growthLimits = ($dataFiles | Where-Object MaxSize -gt 0 | Measure-Object).Count + ($logFiles | Where-Object MaxSize -gt 0 | Measure-Object).Count
            if ($growthLimits -gt 0) {
                $growthLimits = $true
            } else {
                $growthLimits = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File MaxSize Set'
                Recommended    = $false
                CurrentSetting = $growthLimits
                IsBestPractice = $growthLimits -eq $false
                Notes          = "Consider setting your tempdb files to unlimited growth."
            }

            Write-Message -Level Verbose -Message "MaxSize values evaluated." -FunctionName Test-DbaTempDbConfig -ModuleName "dbatools"

            #Test Data File Size Equal
            $distinctCountSizeDataFiles = ($dataFiles | Group-Object -Property Size | Measure-Object).Count

            if ($distinctCountSizeDataFiles -eq 1) {
                $equalSizeDataFiles = $true
            } else {
                $equalSizeDataFiles = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'Data File Size Equal'
                Recommended    = $true
                CurrentSetting = $equalSizeDataFiles
                IsBestPractice = $equalSizeDataFiles -eq $true
                Notes          = "Consider creating equally sized data files."
            }
            Write-Message -Level Verbose -Message "Data File Size Equal evaluated." -FunctionName Test-DbaTempDbConfig -ModuleName "dbatools"
        }
} $SqlInstance $SqlCredential $EnableException @__commonParameters 3>&1 2>&1
""";
}
