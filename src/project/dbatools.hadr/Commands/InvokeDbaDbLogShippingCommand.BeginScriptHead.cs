#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaDbLogShippingCommand
{
    // PS: the begin block VERBATIM, first half (composed as BeginScript = head +
    // newline + tail; re-parsed at build verification), CRLF-preserved. The hop runs
    // ONCE (side-effectful begin: source+destination connects, 28 validation sites).
    // Frame: the caller-bound parameter-table splat (ONLY MyInvocation.BoundParameters
    // minus engine commons - the typed inner params supply function-world defaults for
    // everything unbound). Two sites are bound-ness-sensitive and depend on that
    // contract: the source line-627 $PSBoundParameters.ContainsKey("AzureBaseUrl")
    // read, which needs the splatted set RE-SEEDED into the dot-sourced body because
    // that body opens a fresh empty automatic, and the Test-Bound count-window, which
    // rides the carried $__boundSharedAzureExactlyOne flag. Plus the W3-102 continue-relay
    // guard for the loop-less line-692 -Continue. Substitutions across both halves:
    // 75 -FunctionName appends + the one Test-Bound count-window rewrite (SOURCE
    // comment); stripping reproduces the source bytes cmp-exact.
    private const string BeginScriptHead = """
param($__parameters, $__boundSharedAzureExactlyOne, $__continueMarker, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SourceSqlInstance, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$DestinationSqlInstance, [System.Management.Automation.PSCredential]$SourceSqlCredential, [System.Management.Automation.PSCredential]$SourceCredential, [System.Management.Automation.PSCredential]$DestinationSqlCredential, [System.Management.Automation.PSCredential]$DestinationCredential, [object[]]$Database, [string]$SharedPath, [string]$LocalPath, [string]$AzureBaseUrl, [string]$AzureCredential, [string]$BackupJob, [int]$BackupRetention, [string]$BackupSchedule, $BackupScheduleFrequencyType, [object[]]$BackupScheduleFrequencyInterval, $BackupScheduleFrequencySubdayType, [int]$BackupScheduleFrequencySubdayInterval, $BackupScheduleFrequencyRelativeInterval, [int]$BackupScheduleFrequencyRecurrenceFactor, [string]$BackupScheduleStartDate, [string]$BackupScheduleEndDate, [string]$BackupScheduleStartTime, [string]$BackupScheduleEndTime, [int]$BackupThreshold, [string]$CopyDestinationFolder, [string]$CopyJob, [int]$CopyRetention, [string]$CopySchedule, $CopyScheduleFrequencyType, [object[]]$CopyScheduleFrequencyInterval, $CopyScheduleFrequencySubdayType, [int]$CopyScheduleFrequencySubdayInterval, $CopyScheduleFrequencyRelativeInterval, [int]$CopyScheduleFrequencyRecurrenceFactor, [string]$CopyScheduleStartDate, [string]$CopyScheduleEndDate, [string]$CopyScheduleStartTime, [string]$CopyScheduleEndTime, [string]$FullBackupPath, [int]$HistoryRetention, [string]$PrimaryMonitorServer, [System.Management.Automation.PSCredential]$PrimaryMonitorCredential, $PrimaryMonitorServerSecurityMode, [string]$RestoreDataFolder, [string]$RestoreLogFolder, [int]$RestoreDelay, [int]$RestoreAlertThreshold, [string]$RestoreJob, [int]$RestoreRetention, [string]$RestoreSchedule, $RestoreScheduleFrequencyType, [object[]]$RestoreScheduleFrequencyInterval, $RestoreScheduleFrequencySubdayType, [int]$RestoreScheduleFrequencySubdayInterval, $RestoreScheduleFrequencyRelativeInterval, [int]$RestoreScheduleFrequencyRecurrenceFactor, [string]$RestoreScheduleStartDate, [string]$RestoreScheduleEndDate, [string]$RestoreScheduleStartTime, [string]$RestoreScheduleEndTime, [int]$RestoreThreshold, [string]$SecondaryDatabasePrefix, [string]$SecondaryDatabaseSuffix, [string]$SecondaryMonitorServer, [System.Management.Automation.PSCredential]$SecondaryMonitorCredential, $SecondaryMonitorServerSecurityMode, [string]$StandbyDirectory, [string]$UseBackupFolder, [switch]$BackupScheduleDisabled, [switch]$CompressBackup, [switch]$CopyScheduleDisabled, [switch]$DisconnectUsers, [switch]$Force, [switch]$GenerateFullBackup, [switch]$IgnoreFileChecks, [switch]$NoInitialization, [switch]$NoRecovery, [switch]$PrimaryThresholdAlertEnabled, [switch]$RestoreScheduleDisabled, [switch]$SecondaryThresholdAlertEnabled, [switch]$Standby, [switch]$UseExistingFullBackup, [switch]$EnableException, $__boundSharedAzureExactlyOne, $__continueMarker, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # This scope's $PSBoundParameters IS faithful - the caller's real bound set is splatted in, so only
    # the parameters the caller passed are marked bound. The dot-sourced body below gets a FRESH EMPTY
    # automatic instead (measured on 7.6.3 and 5.1.26100), which silently inverted the
    # ContainsKey("AzureBaseUrl") read that decides the Azure-vs-file-share path. Capture it here and
    # re-seed it there, minus the four plumbing arguments that are passed by name and were never part
    # of the caller's set.
    $__realBoundParameters = @{}
    foreach ($__realBoundKey in $PSBoundParameters.Keys) {
        if ($__realBoundKey -notin @("__boundSharedAzureExactlyOne", "__continueMarker", "__boundVerbose", "__boundDebug")) {
            $__realBoundParameters[$__realBoundKey] = $PSBoundParameters[$__realBoundKey]
        }
    }

    $__continueEscaped = $true
    foreach ($__continueRelayGuard in @(1)) {
        . {
        $PSBoundParameters = $__realBoundParameters
        if ($Force) { $ConfirmPreference = 'none' }

        Write-Message -Message "Started log shipping for $SourceSqlInstance to $DestinationSqlInstance" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

        # Try connecting to the instance
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }


        # Check the instance if it is a named instance
        $SourceServerName, $SourceInstanceName = $SourceSqlInstance.FullName.Split("\")

        if ($null -eq $SourceInstanceName) {
            $SourceInstanceName = "MSSQLSERVER"
        }

        # Set up regex strings for several checks
        $RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'
        $RegexUnc = '^\\(?:\\[^<>:`"/\\|?*]+)+$'
        $RegexAzureUrl = '^https?://[a-z0-9]{3,24}\.blob\.core\.windows\.net/[a-z0-9]([a-z0-9\-]*[a-z0-9])?/?'

        # Validate mutually exclusive parameters for backup destination
        if (-not $__boundSharedAzureExactlyOne) { # SOURCE: if (-not (Test-Bound -ParameterName "SharedPath", "AzureBaseUrl" -Min 1 -Max 1)) {
            Stop-Function -Message "You must specify either -SharedPath (for traditional file share log shipping) or -AzureBaseUrl (for Azure blob storage log shipping), but not both." -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the connection timeout
        if ($SourceServer.ConnectionContext.StatementTimeout -ne 0) {
            $SourceServer.ConnectionContext.StatementTimeout = 0
            Write-Message -Message "Connection timeout of $SourceServer is set to 0" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }

        # Check if using Azure blob storage or traditional file share
        $UseAzure = $PSBoundParameters.ContainsKey("AzureBaseUrl")

        if ($UseAzure) {
            # Validate Azure URL format
            Write-Message -Message "Using Azure blob storage: $AzureBaseUrl" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

            # Trim trailing slashes
            $AzureBaseUrl = $AzureBaseUrl.TrimEnd("/")

            if ($AzureBaseUrl -notmatch $RegexAzureUrl) {
                Stop-Function -Message "Azure blob storage URL $AzureBaseUrl must be in the format https://storageaccount.blob.core.windows.net/container (example: https://mystorageaccount.blob.core.windows.net/logshipping)" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                return
            }

            # Check SQL Server version (Azure backup requires SQL Server 2012+)
            if ($SourceServer.Version.Major -lt 11) {
                Stop-Function -Message "Azure blob storage backup requires SQL Server 2012 or later. Source instance is version $($SourceServer.Version.Major)" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                return
            }

            # For Azure, we'll use the URL as both the backup directory and share
            $SharedPath = $AzureBaseUrl
            $LocalPath = $AzureBaseUrl
        } else {
            if (-not $IgnoreFileChecks) {
                # Check the backup network path
                Write-Message -Message "Testing backup network path $SharedPath" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                if ((Test-DbaPath -Path $SharedPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential) -ne $true) {
                    Stop-Function -Message "Backup network path $SharedPath is not valid or can't be reached." -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                    return
                }
            } else {
                Write-Message -Message "Skipping backup network path validation for $SharedPath because -IgnoreFileChecks was specified." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
            }

            if ($SharedPath -notmatch $RegexUnc) {
                Stop-Function -Message "Backup network path $SharedPath has to be in the form of \\server\share." -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                return
            }
        }

        # Check the backup compression
        if ($SourceServer.Version.Major -gt 9) {
            if ($CompressBackup) {
                Write-Message -Message "Setting backup compression to 1." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                [bool]$BackupCompression = 1
            } else {
                $backupServerSetting = (Get-DbaSpConfigure -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -ConfigName DefaultBackupCompression).ConfiguredValue
                Write-Message -Message "Setting backup compression to default server setting $backupServerSetting." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                [bool]$BackupCompression = $backupServerSetting
            }
        } else {
            Write-Message -Message "Source server $SourceServer does not support backup compression" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }

        # Check the database parameter
        if ($Database) {
            foreach ($db in $Database) {
                if ($db -notin $SourceServer.Databases.Name) {
                    Stop-Function -Message "Database $db cannot be found on instance $SourceSqlInstance" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                }

                $DatabaseCollection = $SourceServer.Databases | Where-Object { $_.Name -in $Database }
            }
        } else {
            Stop-Function -Message "Please supply a database to set up log shipping for" -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
        }

        # Set the database mode
        if ($Standby) {
            $DatabaseStatus = 1
            Write-Message -Message "Destination database status set to STANDBY" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } else {
            $DatabaseStatus = 0
            Write-Message -Message "Destination database status set to NO RECOVERY" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }

        # Setting defaults
        if (-not $BackupRetention) {
            $BackupRetention = 4320
            Write-Message -Message "Backup retention set to $BackupRetention" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $BackupThreshold) {
            $BackupThreshold = 60
            Write-Message -Message "Backup Threshold set to $BackupThreshold" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $CopyRetention) {
            $CopyRetention = 4320
            Write-Message -Message "Copy retention set to $CopyRetention" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $HistoryRetention) {
            $HistoryRetention = 14420
            Write-Message -Message "History retention set to $HistoryRetention" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreAlertThreshold) {
            $RestoreAlertThreshold = 45
            Write-Message -Message "Restore alert Threshold set to $RestoreAlertThreshold" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreDelay) {
            $RestoreDelay = 0
            Write-Message -Message "Restore delay set to $RestoreDelay" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreRetention) {
            $RestoreRetention = 4320
            Write-Message -Message "Restore retention set to $RestoreRetention" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreThreshold) {
            $RestoreThreshold = 45
            Write-Message -Message "Restore Threshold set to $RestoreThreshold" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $PrimaryMonitorServerSecurityMode) {
            $PrimaryMonitorServerSecurityMode = 1
            Write-Message -Message "Primary monitor server security mode set to $PrimaryMonitorServerSecurityMode" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $SecondaryMonitorServerSecurityMode) {
            $SecondaryMonitorServerSecurityMode = 1
            Write-Message -Message "Secondary monitor server security mode set to $SecondaryMonitorServerSecurityMode" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $BackupScheduleFrequencyType) {
            $BackupScheduleFrequencyType = "Daily"
            Write-Message -Message "Backup frequency type set to $BackupScheduleFrequencyType" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $BackupScheduleFrequencyInterval) {
            $BackupScheduleFrequencyInterval = "EveryDay"
            Write-Message -Message "Backup frequency interval set to $BackupScheduleFrequencyInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $BackupScheduleFrequencySubdayType) {
            $BackupScheduleFrequencySubdayType = "Minutes"
            Write-Message -Message "Backup frequency subday type set to $BackupScheduleFrequencySubdayType" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $BackupScheduleFrequencySubdayInterval) {
            $BackupScheduleFrequencySubdayInterval = 15
            Write-Message -Message "Backup frequency subday interval set to $BackupScheduleFrequencySubdayInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $BackupScheduleFrequencyRelativeInterval) {
            $BackupScheduleFrequencyRelativeInterval = "Unused"
            Write-Message -Message "Backup frequency relative interval set to $BackupScheduleFrequencyRelativeInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $BackupScheduleFrequencyRecurrenceFactor) {
            $BackupScheduleFrequencyRecurrenceFactor = 0
            Write-Message -Message "Backup frequency recurrence factor set to $BackupScheduleFrequencyRecurrenceFactor" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $CopyScheduleFrequencyType) {
            $CopyScheduleFrequencyType = "Daily"
            Write-Message -Message "Copy frequency type set to $CopyScheduleFrequencyType" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $CopyScheduleFrequencyInterval) {
            $CopyScheduleFrequencyInterval = "EveryDay"
            Write-Message -Message "Copy frequency interval set to $CopyScheduleFrequencyInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
""";
}
