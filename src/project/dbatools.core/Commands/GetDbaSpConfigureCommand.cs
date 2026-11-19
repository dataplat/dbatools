#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server sp_configure settings with default-value comparisons. Port of
/// public/Get-DbaSpConfigure.ps1 (W3-051). SqlInstance is ValueFromPipeline, so each pipeline
/// record rides ONE VERBATIM module hop in ProcessRecord (GetDbaExtendedProtection precedent):
/// the per-$instance connect, the $proplist Name/ExcludeName filtering, the Get-SqlDefaultSpConfigure
/// comparison, and the per-property PSCustomObject emit all ride verbatim.
///
/// begin/process: the source begin block only builds $smoName, a STATIC display-name -&gt; SMO-name
/// lookup table with no runtime dependency and no side effect. It is built at the top of the
/// per-record hop (observably identical to begin-once - static data, read-only use; NOT the
/// stateful once-across-records / sentinel class, so sentinel-carry=0).
///
/// CARRIER (W2-071 class - BOUNDNESS): the source's ExcludeName filter guards on
/// Test-Bound "ExcludeName" (presence of the bound parameter), carried as ContainsKey
/// $__boundExcludeName - matching the source test line-by-line. The Name filter uses
/// if ($Name) (TRUTHINESS of the value), which rides natively in the hop and is left unchanged -
/// reproducing each guard's own test, in its own direction.
///
/// DEF-001: the per-instance Stop-Function -Continue (connect / property-gather failure) throws
/// under -EnableException, and the property loop emits objects, so a buffered foreach would lose
/// them - delivered via InvokeScopedStreaming. DEF-006: the two hop-level Stop-Function calls
/// carry -FunctionName Get-DbaSpConfigure (no Write-Message in this command). Surface pinned by
/// migration/baselines/Get-DbaSpConfigure.json (SqlInstance mandatory pos0 VFP; SqlCredential
/// pos1; Name pos2 alias Config/ConfigName; ExcludeName pos3; no SSP; no OutputType).
/// </summary>
[Cmdlet("Get", "DbaSpConfigure")]
public sealed class GetDbaSpConfigureCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Return only specific configuration settings (display or SMO property names).</summary>
    [Parameter(Position = 2)]
    [Alias("Config", "ConfigName")]
    public string[]? Name { get; set; }

    /// <summary>Exclude specific configuration settings (display or SMO property names).</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeName { get; set; }

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
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Name, ExcludeName, EnableException.ToBool(),
            BoundPresence("ExcludeName"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>Carries a Test-Bound guard (W2-071 class): BOUNDNESS of the parameter
    /// (ContainsKey), NOT the truthiness of its value.</summary>
    private object BoundPresence(string name) => MyInvocation.BoundParameters.ContainsKey(name);

    // PS: begin's static $smoName table + process body VERBATIM (single hop per record; the
    // static table rebuilds per record with no observable difference). Substitutions only: the
    // Test-Bound "ExcludeName" guard becomes the carried $__boundExcludeName ContainsKey flag
    // (if ($Name) stays a native truthiness read); hop-level Stop-Function gains -FunctionName
    // Get-DbaSpConfigure.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $ExcludeName, $EnableException, $__boundExcludeName, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Name, [string[]]$ExcludeName, $EnableException, $__boundExcludeName, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $smoName = [PSCustomObject]@{
        "access check cache bucket count"    = "AccessCheckCacheBucketCount"
        "access check cache quota"           = "AccessCheckCacheQuota"
        "Ad Hoc Distributed Queries"         = "AdHocDistributedQueriesEnabled"
        "ADR Cleaner Thread Count"           = "AdrCleanerThreadCount"
        "ADR cleaner retry timeout (min)"    = "AdrCleanerRetryTimeout"
        "ADR Preallocation Factor"           = "AdrPreallcationFactor"
        "affinity I/O mask"                  = "AffinityIOMask"
        "affinity mask"                      = "AffinityMask"
        "affinity64 I/O mask"                = "Affinity64IOMask"
        "affinity64 mask"                    = "Affinity64Mask"
        "Agent XPs"                          = "AgentXPsEnabled"
        "allow filesystem enumeration"       = "AllowFilesystemEnumeration"
        "allow polybase export"              = "AllowPolybaseExport"
        "allow updates"                      = "AllowUpdates"
        "automatic soft-NUMA disabled"       = "AutomaticSoftnumaDisabled"
        "awe enabled"                        = "AweEnabled"
        "backup checksum default"            = "BackupChecksumDefault"
        "backup compression algorithm"       = "BackupCompressionAlgorithm"
        "backup compression default"         = "DefaultBackupCompression"
        "blocked process threshold"          = "BlockedProcessThreshold"
        "blocked process threshold (s)"      = "BlockedProcessThreshold"
        "c2 audit mode"                      = "C2AuditMode"
        "clr enabled"                        = "IsSqlClrEnabled"
        "clr strict security"                = "ClrStrictSecurity"
        "column encryption enclave type"     = "ColumnEncryptionEnclaveType"
        "common criteria compliance enabled" = "CommonCriteriaComplianceEnabled"
        "contained database authentication"  = "ContainmentEnabled"
        "cost threshold for parallelism"     = "CostThresholdForParallelism"
        "cross db ownership chaining"        = "CrossDBOwnershipChaining"
        "cursor threshold"                   = "CursorThreshold"
        "Data processed daily limit in TB"   = "DataProcessedDailyLimitInTB"
        "Data processed monthly limit in TB" = "DataProcessedMonthlyLimitInTB"
        "Data processed weekly limit in TB"  = "DataProcessedWeeklyLimitInTB"
        "Database Mail XPs"                  = "DatabaseMailEnabled"
        "default full-text language"         = "DefaultFullTextLanguage"
        "default language"                   = "DefaultLanguage"
        "default trace enabled"              = "DefaultTraceEnabled"
        "disallow results from triggers"     = "DisallowResultsFromTriggers"
        "EKM provider enabled"               = "ExtensibleKeyManagementEnabled"
        "external scripts enabled"           = "ExternalScriptsEnabled"
        "filestream access level"            = "FilestreamAccessLevel"
        "fill factor (%)"                    = "FillFactor"
        "ft crawl bandwidth (max)"           = "FullTextCrawlBandwidthMax"
        "ft crawl bandwidth (min)"           = "FullTextCrawlBandwidthMin"
        "ft notify bandwidth (max)"          = "FullTextNotifyBandwidthMax"
        "ft notify bandwidth (min)"          = "FullTextNotifyBandwidthMin"
        "hadoop connectivity"                = "HadoopConnectivity"
        "hardware offload config"            = "HardwareOffloadConfig"
        "hardware offload enabled"           = "HardwareOffloadEnabled"
        "hardware offload mode"              = "HardwareOffloadMode"
        "index create memory (KB)"           = "IndexCreateMemory"
        "in-doubt xact resolution"           = "InDoubtTransactionResolution"
        "lightweight pooling"                = "LightweightPooling"
        "locks"                              = "Locks"
        "max degree of parallelism"          = "MaxDegreeOfParallelism"
        "max full-text crawl range"          = "FullTextCrawlRangeMax"
        "max server memory (MB)"             = "MaxServerMemory"
        "max text repl size (B)"             = "ReplicationMaxTextSize"
        "max worker threads"                 = "MaxWorkerThreads"
        "media retention"                    = "MediaRetention"
        "min memory per query (KB)"          = "MinMemoryPerQuery"
        "min server memory (MB)"             = "MinServerMemory"
        "nested triggers"                    = "NestedTriggers"
        "network packet size (B)"            = "NetworkPacketSize"
        "Ole Automation Procedures"          = "OleAutomationProceduresEnabled"
        "open objects"                       = "OpenObjects"
        "openrowset auto_create_statistics"  = "OpenRowsetAutoCreateStatistics"
        "optimize for ad hoc workloads"      = "OptimizeAdhocWorkloads"
        "PH timeout (s)"                     = "ProtocolHandlerTimeout"
        "polybase enabled"                   = "PolybaseEnabled"
        "polybase network encryption"        = "PolybaseNetworkEncryption"
        "precompute rank"                    = "PrecomputeRank"
        "priority boost"                     = "PriorityBoost"
        "query governor cost limit"          = "QueryGovernorCostLimit"
        "query wait (s)"                     = "QueryWait"
        "recovery interval (min)"            = "RecoveryInterval"
        "remote access"                      = "RemoteAccess"
        "remote admin connections"           = "RemoteDacConnectionsEnabled"
        "remote data archive"                = "RemoteDataArchiveEnabled"
        "remote login timeout (s)"           = "RemoteLoginTimeout"
        "remote proc trans"                  = "RemoteProcTrans"
        "remote query timeout (s)"           = "RemoteQueryTimeout"
        "Replication XPs"                    = "ReplicationXPsEnabled"
        "scan for startup procs"             = "ScanForStartupProcedures"
        "server trigger recursion"           = "ServerTriggerRecursionEnabled"
        "set working set size"               = "SetWorkingSetSize"
        "show advanced options"              = "ShowAdvancedOptions"
        "SMO and DMO XPs"                    = "SmoAndDmoXPsEnabled"
        "SQL Mail XPs"                       = "SqlMailXPsEnabled"
        "suppress recovery model errors"     = "SuppressRecoveryModelErrors"
        "tempdb metadata memory-optimized"   = "TempdbMetadataMemoryOptimized"
        "transform noise words"              = "TransformNoiseWords"
        "two digit year cutoff"              = "TwoDigitYearCutoff"
        "User Instance Timeout"              = "UserInstanceTimeout"
        "user connections"                   = "UserConnections"
        "user instances enabled"             = "UserInstancesEnabled"
        "user options"                       = "UserOptions"
        "Web Assistant Procedures"           = "WebXPsEnabled"
        "xp_cmdshell"                        = "XPCmdShellEnabled"
        "version high part of SQL Server"    = "VersionHighPartOfSqlServer"
        "version low part of SQL Server"     = "VersionLowPartOfSqlServer"
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaSpConfigure
        }

        #Get a list of the configuration Properties. This collection matches entries in sys.configurations
        try {
            $proplist = $server.Configuration.Properties
        } catch {
            Stop-Function -Message "Unable to gather configuration properties $instance" -Target $instance -ErrorRecord $_ -Continue -FunctionName Get-DbaSpConfigure
        }

        if ($Name) {
            $proplist = $proplist | Where-Object { ($_.DisplayName -in $Name -or ($smoName).$($_.DisplayName) -in $Name) }
        }

        if ($__boundExcludeName) {
            $proplist = $proplist | Where-Object { ($_.DisplayName -NotIn $ExcludeName -and ($smoName).$($_.DisplayName) -NotIn $ExcludeName) }
        }

        #Grab the default sp_configure property values from the external function
        $defaultConfigs = (Get-SqlDefaultSpConfigure -SqlVersion $server.VersionMajor).psobject.properties;

        #Iterate through the properties to get the configuration settings
        foreach ($prop in $proplist) {
            $defaultConfig = $defaultConfigs | Where-Object { $_.Name -eq $prop.DisplayName };

            if ($defaultConfig.Value -eq $prop.RunValue) { $isDefault = $true }
            else { $isDefault = $false }

            #Ignores properties that are not valid on this version of SQL
            if (!([string]::IsNullOrEmpty($prop.RunValue))) {

                $DisplayName = $prop.DisplayName
                [PSCustomObject]@{
                    ServerName            = $server.Name
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    Name                  = ($smoName).$DisplayName
                    DisplayName           = $DisplayName
                    Description           = $prop.Description
                    IsAdvanced            = $prop.IsAdvanced
                    IsDynamic             = $prop.IsDynamic
                    MinValue              = $prop.Minimum
                    MaxValue              = $prop.Maximum
                    ConfiguredValue       = $prop.ConfigValue
                    RunningValue          = $prop.RunValue
                    DefaultValue          = $defaultConfig.Value
                    IsRunningDefaultValue = $isDefault
                    Parent                = $server
                    ConfigName            = ($smoName).$DisplayName
                    Property              = $prop
                } | Select-DefaultView -ExcludeProperty ServerName, Parent, ConfigName, Property
            }
        }
    }
} $SqlInstance $SqlCredential $Name $ExcludeName $EnableException $__boundExcludeName $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
