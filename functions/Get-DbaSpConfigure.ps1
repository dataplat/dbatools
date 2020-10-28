function Get-DbaSpConfigure {
    <#
    .SYNOPSIS
        Returns all server level system configuration (sys.configuration/sp_configure) information

    .DESCRIPTION
        This function returns server level system configuration (sys.configuration/sp_configure) information. The information is gathered through SMO Configuration.Properties.
        The data includes the default value for each configuration, for quick identification of values that may have been changed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Return only specific configurations. Name can be either values from (sys.configuration/sp_configure) or from SMO object

    .PARAMETER ExcludeName
        Exclude specific configurations. Name can be either values from (sys.configuration/sp_configure) or from SMO object

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SpConfig, Configure, Configuration
        Author: Nic Cain, https://sirsql.net/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSpConfigure

    .INPUTS
        A DbaInstanceParameter representing an array of SQL Server instances.

    .OUTPUTS
        Returns PSCustomObject with properties ServerName, ComputerName, InstanceName, SqlInstance, Name, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, RunningValue, DefaultValue, IsRunningDefaultValue

    .EXAMPLE
        PS C:\> Get-DbaSpConfigure -SqlInstance localhost

        Returns all system configuration information on the localhost.

    .EXAMPLE
        PS C:\> 'localhost','localhost\namedinstance' | Get-DbaSpConfigure

        Returns system configuration information on multiple instances piped into the function

    .EXAMPLE
        PS C:\> Get-DbaSpConfigure -SqlInstance sql2012 -Name 'max server memory (MB)'

        Returns only the system configuration for MaxServerMemory on sql2012.

    .EXAMPLE
        PS C:\> Get-DbaSpConfigure -SqlInstance sql2012 -ExcludeName 'max server memory (MB)', RemoteAccess | Out-GridView

        Returns system configuration information on sql2012 but excludes for max server memory (MB) and remote access. Values returned in grid view

    .EXAMPLE
        PS C:\> $cred = Get-Credential SqlCredential
        PS C:\> 'sql2012' | Get-DbaSpConfigure -SqlCredential $cred -Name RemoteAccess, 'max server memory (MB)' -ExcludeName 'remote access' | Out-GridView

        Returns system configuration information on sql2012 using SQL Server Authentication. Only MaxServerMemory is returned as RemoteAccess was also excluded.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Config", "ConfigName")]
        [string[]]$Name,
        [string[]]$ExcludeName,
        [switch]$EnableException
    )
    begin {
        $smoName = [pscustomobject]@{
            "access check cache bucket count"    = "AccessCheckCacheBucketCount"
            "access check cache quota"           = "AccessCheckCacheQuota"
            "Ad Hoc Distributed Queries"         = "AdHocDistributedQueriesEnabled"
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
            "backup compression default"         = "DefaultBackupCompression"
            "blocked process threshold (s)"      = "BlockedProcessThreshold"
            "blocked process threshold"          = "BlockedProcessThreshold"
            "c2 audit mode"                      = "C2AuditMode"
            "clr enabled"                        = "IsSqlClrEnabled"
            "clr strict security"                = "ClrStrictSecurity"
            "column encryption enclave type"     = "ColumnEncryptionEnclaveType"
            "common criteria compliance enabled" = "CommonCriteriaComplianceEnabled"
            "contained database authentication"  = "ContainmentEnabled"
            "cost threshold for parallelism"     = "CostThresholdForParallelism"
            "cross db ownership chaining"        = "CrossDBOwnershipChaining"
            "cursor threshold"                   = "CursorThreshold"
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
            "tempdb metadata memory-optimized"   = "TempdbMetadataMemoryOptimized"
            "transform noise words"              = "TransformNoiseWords"
            "two digit year cutoff"              = "TwoDigitYearCutoff"
            "user connections"                   = "UserConnections"
            "User Instance Timeout"              = "UserInstanceTimeout"
            "user instances enabled"             = "UserInstancesEnabled"
            "user options"                       = "UserOptions"
            "Web Assistant Procedures"           = "WebXPsEnabled"
            "xp_cmdshell"                        = "XPCmdShellEnabled"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            #Get a list of the configuration Properties. This collection matches entries in sys.configurations
            try {
                $proplist = $server.Configuration.Properties
            } catch {
                Stop-Function -Message "Unable to gather configuration properties $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            if ($Name) {
                $proplist = $proplist | Where-Object { ($_.DisplayName -in $Name -or ($smoName).$($_.DisplayName) -in $Name) }
            }

            if (Test-Bound "ExcludeName") {
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
                    [pscustomobject]@{
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
    }
}
