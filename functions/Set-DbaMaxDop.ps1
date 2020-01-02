function Set-DbaMaxDop {
    <#
    .SYNOPSIS
        Sets SQL Server maximum degree of parallelism (Max DOP), then displays information relating to SQL Server Max DOP configuration settings. Works on SQL Server 2005 and higher.

    .DESCRIPTION
        Uses the Test-DbaMaxDop command to get the recommended value if -MaxDop parameter is not specified.

        These are just general recommendations for SQL Server and are a good starting point for setting the "max degree of parallelism" option.

        You can set MaxDop database scoped configurations if the server is version 2016 or higher

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more databases to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more databases to exclude from processing. Options for this list are auto-populated from the server

    .PARAMETER MaxDop
        Specifies the Max DOP value to set.

    .PARAMETER AllDatabases
        If this switch is enabled, Max DOP will be set on all databases. This switch is only useful on SQL Server 2016 and higher.

    .PARAMETER InputObject
        If Test-SqlMaxDop has been executed prior to this function, the results may be passed in via this parameter.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .NOTES
        Tags: MaxDop, SpConfigure
        Author: Claudio Silva (@claudioessilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaMaxDop

    .EXAMPLE
        PS C:\> Set-DbaMaxDop -SqlInstance sql2008, sql2012

        Sets Max DOP to the recommended value for servers sql2008 and sql2012.

    .EXAMPLE
        PS C:\> Set-DbaMaxDop -SqlInstance sql2014 -MaxDop 4

        Sets Max DOP to 4 for server sql2014.

    .EXAMPLE
        PS C:\> Test-DbaMaxDop -SqlInstance sql2008 | Set-DbaMaxDop

        Gets the recommended Max DOP from Test-DbaMaxDop and applies it to to sql2008.

    .EXAMPLE
        PS C:\> Set-DbaMaxDop -SqlInstance sql2016 -Database db1

        Set recommended Max DOP for database db1 on server sql2016.

    .EXAMPLE
        PS C:\> Set-DbaMaxDop -SqlInstance sql2016 -AllDatabases

        Set recommended Max DOP for all databases on server sql2016.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [int]$MaxDop = -1,
        [Parameter(ValueFromPipeline)]
        [pscustomobject]$InputObject,
        [Alias("All")]
        [switch]$AllDatabases,
        [switch]$EnableException
    )
    begin {
        if ($MaxDop -eq -1) {
            $UseRecommended = $true
        }
    }

    process {
        if (Test-Bound -ParameterName Database, AllDatabases, ExcludeDatabase) {
            Stop-Function -Category InvalidArgument -Message "-Database, -AllDatabases and -ExcludeDatabase are mutually exclusive. Please choose only one."
            return
        }

        if ((Test-Bound -ParameterName SqlInstance, InputObject -not)) {
            Stop-Function -Category InvalidArgument -Message "Please provide either the SqlInstance or InputObject."
            return
        }

        $dbscopedconfiguration = $false

        if ((Test-Bound -Not -ParameterName InputObject)) {
            $InputObject = Test-DbaMaxDop -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Verbose:$false
        } elseif ($null -eq $InputObject.SqlInstance) {
            $InputObject = Test-DbaMaxDop -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Verbose:$false
        }

        $InputObject | Add-Member -Force -NotePropertyName PreviousInstanceMaxDopValue -NotePropertyValue 0
        $InputObject | Add-Member -Force -NotePropertyName PreviousDatabaseMaxDopValue -NotePropertyValue 0

        #If we have servers 2016 or higher we will have a row per database plus the instance level, getting unique we only run one time per instance
        $servers = $InputObject | Select-Object SqlInstance -Unique

        foreach ($server in $servers) {
            $servername = $server.SqlInstance

            try {
                $server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $servername -Continue
            }

            if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $server. Skipping." -Category PermissionDenied -ErrorRecord $_ -Target $currentServer -Continue
            }

            if ($server.versionMajor -ge 13) {
                Write-Message -Level Verbose -Message "Server '$servername' supports Max DOP configuration per database."

                if ((Test-Bound -ParameterName Database, ExcludeDatabase -not)) {
                    #Set at instance level
                    $InputObject = $InputObject | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
                } else {
                    $dbscopedconfiguration = $true

                    if ((Test-Bound -Not -ParameterName AllDatabases) -and (Test-Bound -ParameterName Database)) {
                        $InputObject = $InputObject | Where-Object { $_.Database -in $Database }
                    } elseif ((Test-Bound -Not -ParameterName AllDatabases) -and (Test-Bound -ParameterName ExcludeDatabase)) {
                        $InputObject = $InputObject | Where-Object { $_.Database -notin $ExcludeDatabase }
                    } else {
                        if (Test-Bound -ParameterName AllDatabases) {
                            $InputObject = $InputObject | Where-Object { $_.DatabaseMaxDop -ne "N/A" }
                        } else {
                            $InputObject = $InputObject | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
                            $dbscopedconfiguration = $false
                        }
                    }
                }
            } else {
                if ((Test-Bound -ParameterName database) -or (Test-Bound -ParameterName AllDatabases)) {
                    Write-Message -Level Warning -Message "Server '$servername' (v$($server.versionMajor)) does not support Max DOP configuration at the database level. Remember that this option is only available from SQL Server 2016 (v13). Run the command again without using database related parameters. Skipping."
                    Continue
                }
            }

            foreach ($row in $InputObject | Where-Object { $_.SqlInstance -eq $servername }) {
                if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.CurrentInstanceMaxDop) -and !($dbscopedconfiguration)) {
                    Write-Message -Level Verbose -Message "$servername is configured properly. No change required."
                    Continue
                }

                if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.DatabaseMaxDop) -and $dbscopedconfiguration) {
                    Write-Message -Level Verbose -Message "Database $($row.Database) on $servername is configured properly. No change required."
                    Continue
                }

                $row.PreviousInstanceMaxDopValue = $row.CurrentInstanceMaxDop

                try {
                    if ($UseRecommended) {
                        if ($dbscopedconfiguration) {
                            $row.PreviousDatabaseMaxDopValue = $row.DatabaseMaxDop

                            if ($resetDatabases) {
                                Write-Message -Level Verbose -Message "Changing $($row.Database) database max DOP to $($row.DatabaseMaxDop)."
                                $server.Databases["$($row.Database)"].MaxDop = $row.DatabaseMaxDop
                            } else {
                                Write-Message -Level Verbose -Message "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $($row.RecommendedMaxDop)."
                                $server.Databases["$($row.Database)"].MaxDop = $row.RecommendedMaxDop
                                $row.DatabaseMaxDop = $row.RecommendedMaxDop
                            }

                        } else {
                            Write-Message -Level Verbose -Message "Changing $server SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $($row.RecommendedMaxDop)."
                            $server.Configuration.MaxDegreeOfParallelism.ConfigValue = $row.RecommendedMaxDop
                            $row.CurrentInstanceMaxDop = $row.RecommendedMaxDop
                        }
                    } else {
                        if ($dbscopedconfiguration) {
                            $row.PreviousDatabaseMaxDopValue = $row.DatabaseMaxDop

                            Write-Message -Level Verbose -Message "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $MaxDop."
                            $server.Databases["$($row.Database)"].MaxDop = $MaxDop
                            $row.DatabaseMaxDop = $MaxDop
                        } else {
                            Write-Message -Level Verbose -Message "Changing $servername SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $MaxDop."
                            $server.Configuration.MaxDegreeOfParallelism.ConfigValue = $MaxDop
                            $row.CurrentInstanceMaxDop = $MaxDop
                        }
                    }

                    if ($dbscopedconfiguration) {
                        if ($Pscmdlet.ShouldProcess($row.Database, "Setting max dop on database")) {
                            $server.Databases["$($row.Database)"].Alter()
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($servername, "Setting max dop on instance")) {
                            $server.Configuration.Alter()
                        }
                    }

                    $results = [pscustomobject]@{
                        ComputerName                = $server.ComputerName
                        InstanceName                = $server.ServiceName
                        SqlInstance                 = $server.DomainInstanceName
                        InstanceVersion             = $row.InstanceVersion
                        Database                    = $row.Database
                        DatabaseMaxDop              = $row.DatabaseMaxDop
                        CurrentInstanceMaxDop       = $row.CurrentInstanceMaxDop
                        RecommendedMaxDop           = $row.RecommendedMaxDop
                        PreviousDatabaseMaxDopValue = $row.PreviousDatabaseMaxDopValue
                        PreviousInstanceMaxDopValue = $row.PreviousInstanceMaxDopValue
                    }

                    if ($dbscopedconfiguration) {
                        Select-DefaultView -InputObject $results -Property InstanceName, Database, PreviousDatabaseMaxDopValue, @{
                            name = "CurrentDatabaseMaxDopValue"; expression = {
                                $_.DatabaseMaxDop
                            }
                        }
                    } else {
                        Select-DefaultView -InputObject $results -Property ComputerName, InstanceName, SqlInstance, PreviousInstanceMaxDopValue, CurrentInstanceMaxDop
                    }
                } catch {
                    Stop-Function -Message "Could not modify Max Degree of Parallelism for $server." -ErrorRecord $_ -Target $server -Continue
                }
            }
        }
    }
}