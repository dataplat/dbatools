function Test-DbaDbQueryStore {
    <#
    .SYNOPSIS
        Compares Query Store settings against best practices.

    .DESCRIPTION
        Evaluates Query Store against a set of rules to match best practices. The rules are:

        * ActualState = ReadWrite (This means Query Store is enabled and collecting data.)
        * DataFlushIntervalInSeconds = 900 (Recommended to leave this at the default of 900 seconds (15 mins).)
        * MaxPlansPerQuery = 200 (Number of distinct plans per query. 200 is a good starting point for most environments.)
        * MaxStorageSizeInMB = 2048 (How much disk space Query Store will use. 2GB is a good starting point.)
        * QueryCaptureMode = Auto (With auto, queries that are insignificant from a resource utilization perspective, or executed infrequently, are not captured.)
        * SizeBasedCleanupMode = Auto (With auto, as Query Store gets close to out of space it will automatically purge older data.)
        * StaleQueryThresholdInDays = 30 (Determines how much historic data to keep. 30 days is a good value here.)
        * StatisticsCollectionIntervalInMinutes = 30 (Time window that runtime stats will be aggregated. Use 30 unless you have space concerns, then leave at the default (60).)
        * WaitStatsCaptureMode = ON (Adds valuable data when troubleshooting.)
        * Trace Flag 7745 enabled
        * Trace Flag 7752 enabled

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all user databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDatabase.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: QueryStore
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Based on Erin Stellato's (@erinstellato) Query Store Best Practices - https://www.sqlskills.com/blogs/erin/query-store-best-practices/

    .LINK
        https://dbatools.io/Test-DbaDbQueryStore

    .EXAMPLE
        PS C:\> Test-DbaDbQueryStore -SqlInstance localhost

        Checks that Query Store is enabled and meets best practices for all user databases on the localhost machine.

    .EXAMPLE
        PS C:\> Test-DbaDbQueryStore -SqlInstance localhost -Database AdventureWorks2017

        Checks that Query Store is enabled and meets best practices for the AdventureWorks2017 database on the localhost machine.

    .EXAMPLE
        PS C:\> Test-DbaDbQueryStore -SqlInstance localhost -ExcludeDatabase AdventureWorks2017

        Checks that Query Store is enabled and meets best practices for all user databases except AdventureWorks2017 on the localhost machine.


    .EXAMPLE
        PS C:\> $databases = Get-DbaDatabase -SqlInstance localhost
        PS C:\> $databases | Test-DbaDbQueryStore

        Checks that Query Store is enabled and meets best practices for all databases that are piped on the localhost machine.

    #>

    [CmdletBinding()]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or a server, or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName

            switch ($inputType) {
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem -OnlyAccessible
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem -OnlyAccessible
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbDatabases = $input | Where-Object { -not $_.IsSystemObject }
                }
                default {
                    Stop-Function -Message "InputObject is not a server or database."
                    return
                }
            }

            try {
                $smo = Connect-SqlInstance -SqlInstance $dbDatabases[0].Parent -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $dbDatabases = $dbDatabases | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbDatabases = $dbDatabases | Where-Object Name -NotIn $ExcludeDatabase
            }

            $desiredState = [PSCustomObject]@{
                Property      = 'ActualState'
                Value         = 'ReadWrite'
                Justification = 'This means Query Store is enabled and collecting data.'
            },
            [PSCustomObject]@{
                Property      = 'DataFlushIntervalInSeconds'
                Value         = '900'
                Justification = 'Recommended to leave this at the default of 900 seconds (15 mins).'
            },
            [PSCustomObject]@{
                Property      = 'MaxPlansPerQuery'
                Value         = '200'
                Justification = 'Number of distinct plans per query. 200 is a good starting point for most environments.'
            },
            [PSCustomObject]@{
                Property      = 'MaxStorageSizeInMB'
                Value         = '2048'
                Justification = 'How much disk space Query Store will use. 2GB is a good starting point.'
            },
            [PSCustomObject]@{
                Property      = 'QueryCaptureMode'
                Value         = 'Auto'
                Justification = 'With auto, queries that are insignificant from a resource utilization perspective, or executed infrequently, are not captured.'
            },
            [PSCustomObject]@{
                Property      = 'SizeBasedCleanupMode'
                Value         = 'Auto'
                Justification = 'With auto, as Query Store gets close to out of space it will automatically purge older data.'
            },
            [PSCustomObject]@{
                Property      = 'StaleQueryThresholdInDays'
                Value         = '30'
                Justification = 'Determines how much historic data to keep. 30 days is a good value here.'
            },
            [PSCustomObject]@{
                Property      = 'StatisticsCollectionIntervalInMinutes'
                Value         = '30'
                Justification = 'Time window that runtime stats will be aggregated. Use 30 unless you have space concerns, then leave at the default (60).'
            },
            [PSCustomObject]@{
                Property      = 'WaitStatsCaptureMode'
                Value         = 'ON'
                Justification = 'Adds valuable data when troubleshooting.'
            }

            try {
                Write-Message -Level Verbose -Message "Evaluating Query Store options"
                $currentOptions = Get-DbaDbQueryStoreOption -SqlInstance $smo -Database $dbDatabases.name

                foreach ($db in $currentOptions) {
                    $props = $db.GetPropertySet() | Where-Object Name -NotIn ('CurrentStorageSizeInMB', 'ReadOnlyReason', 'DesiredState')
                    foreach ($property in $props) {
                        [PSCustomObject]@{
                            ComputerName     = $db.ComputerName
                            InstanceName     = $db.InstanceName
                            SqlInstance      = $db.SqlInstance
                            Database         = $db.Database
                            Name             = $property.Name
                            Value            = $property.Value
                            RecommendedValue = ($desiredState | Where-Object Property -EQ $property.Name).Value
                            IsBestPractice   = ($property.Value -eq ($desiredState | Where-Object Property -EQ $property.Name).Value)
                            Justification    = ($desiredState | Where-Object Property -EQ $property.Name).Justification
                        }
                    }
                }
            } catch {
                Stop-Function -Message "Unable to get Query Store data $smo" -Target $smo -ErrorRecord $_
            }

            # Trace flags
            $queryStoreTF = [PSCustomObject]@{
                TraceFlag     = '7745'
                Justification = 'SQL Server will not wait to write Query Store data to disk on shutdown\failover (can cause lose of Query Store data).'
            },
            [PSCustomObject]@{
                TraceFlag     = '7752'
                Justification = 'Load Query Store data asynchronously on SQL Server startup.'
            }
            try {
                foreach ($tf in $queryStoreTF) {
                    $tfEnabled = Get-DbaTraceFlag -SqlInstance $smo -TraceFlag $tf.TraceFlag
                    [PSCustomObject]@{
                        ComputerName     = $smo.ComputerName
                        InstanceName     = $smo.DbaInstanceName
                        SqlInstance      = $smo.Name
                        Name             = ('Trace Flag {0} Enabled' -f $tf.TraceFlag)
                        Value            = if ($tfEnabled) { 'Enabled' } else { 'Disabled' }
                        RecommendedValue = $tf.TraceFlag
                        IsBestPractice   = ($tfEnabled.TraceFlag -eq $tf.TraceFlag)
                        Justification    = $tf.Justification
                    }
                    $tfEnabled = $null
                }
            } catch {
                Stop-Function -Message "Unable to get Trace Flag data $smo" -Target $smo -ErrorRecord $_
            }
        }
    }
}