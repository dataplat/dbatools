function Get-DbaDbccStatistic {
    <#
    .SYNOPSIS
        Execution of Database Console Command DBCC SHOW_STATISTICS

    .DESCRIPTION
        Executes the command DBCC SHOW_STATISTICS against defined objects and returns results

        Reclaims space from dropped variable-length columns in tables or indexed views

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-cleantable-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER Object
        The table or indexed view for which to display statistics information.
        Any two part object name should be formatted as 'Schema.ObjectName'

    .PARAMETER Target
        Name of the index, statistics, or column for which to display statistics information.
        Target can be enclosed in brackets, single quotes, double quotes, or no quotes

    .PARAMETER Option
        Used to limit the result sets returned by the statement to the specified option.
        Options are 'StatHeader', 'DensityVector', 'Histogram', 'StatsStream'
        Default of StatHeader

    .PARAMETER NoInformationalMessages
        Suppresses all informational messages.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC, Statistics
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbccStatistic

    .EXAMPLE
        PS C:\> Get-DbaDbccStatistic -SqlInstance SQLServer2017

        Will run the statement SHOW_STATISTICS WITH STAT_HEADER against all Statistics on all User Tables or views for every accessible database on instance SQLServer2017. Connects using Windows Authentication.

    .EXAMPLE
        PS C:\> Get-DbaDbccStatistic -SqlInstance SQLServer2017 -Database MyDb -Option DensityVector

        Will run the statement SHOW_STATISTICS WITH DENSITY_VECTOR against all Statistics on all User Tables or views for database MyDb on instance SQLServer2017. Connects using Windows Authentication.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbccStatistic -SqlInstance SQLServer2017 -SqlCredential $cred -Database MyDb -Object UserTable -Option Histogram

        Will run the statement SHOW_STATISTICS WITH HISTOGRAM against all Statistics on table UserTable for database MyDb on instance SQLServer2017. Connects using sqladmin credential.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbccStatistic -SqlInstance SQLServer2017 -Database MyDb -Object 'dbo.UserTable' -Target MyStatistic -Option StatsStream

        Runs the statement SHOW_STATISTICS('dbo.UserTable', 'MyStatistic') WITH STATS_STREAM against database MyDb on instances Sql1 and Sql2/sqlexpress. Connects using Windows Authentication.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$Object,
        [string]$Target,
        [ValidateSet('StatHeader', 'DensityVector', 'Histogram', 'StatsStream')]
        [string]$Option = "StatHeader",
        [switch]$NoInformationalMessages,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC SHOW_STATISTICS(#options#) WITH NO_INFOMSGS" )
        if ($Option -eq 'StatHeader') {
            $null = $stringBuilder.Append(", STAT_HEADER")
        } elseif ($Option -eq 'DensityVector') {
            $null = $stringBuilder.Append(", DENSITY_VECTOR")
        } elseif ($Option -eq 'Histogram') {
            $null = $stringBuilder.Append(", HISTOGRAM")
        } elseif ($Option -eq 'StatsStream') {
            $null = $stringBuilder.Append(", STATS_STREAM")
        }

        $statList =
        "Select Object, Target, name FROM
        (
            Select Schema_Name(o.SCHEMA_ID) + '.' + o.name as Object, st.name as Target, o.name
            FROM sys.stats st
            INNER JOIN sys.objects o
                on o.object_id = st.object_id
            WHERE o.type in ('U', 'V')
        ) a
        "
    }
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -eq 8) {
                if ((Test-Bound -Not -ParameterName Object) -or (Test-Bound -Not -ParameterName Target)) {
                    Write-Message -Level Warning -Message "You must specify an Object and a Target for SQL Server 2000"
                    continue
                }
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"
                $queryList = @()
                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping." -Continue
                }

                if ((Test-Bound -ParameterName Object) -and (Test-Bound -ParameterName Target)) {
                    $query = $StringBuilder.ToString()
                    $query = $query.Replace('#options#', "'$Object', '$Target'")

                    $queryList += New-Object -TypeName PSObject -Property @{Object = $Object;
                        Target                                                     = $Target;
                        Query                                                      = $query
                    }
                } elseif (Test-Bound -ParameterName Object) {
                    $whereFilter = " WHERE (Object = '$object' or name = '$object')"
                    $statListFiltered = $statList + $whereFilter
                    Write-Message -Level Verbose -Message "Query to execute: $statListFiltered"
                    $statListData = $db.Query($statListFiltered)
                    foreach ($statisticObj in  $statListData) {
                        $query = $StringBuilder.ToString()
                        $query = $query.Replace('#options#', "'$($statisticObj.Object)', '$($statisticObj.Target)'")
                        $queryList += New-Object -TypeName PSObject -Property @{Object = $statisticObj.Object;
                            Target                                                     = $statisticObj.Target;
                            Query                                                      = $query
                        }
                    }
                } else {
                    $statListData = $db.Query($statList)
                    foreach ($statisticObj in  $statListData) {
                        $query = $StringBuilder.ToString()
                        $query = $query.Replace('#options#', "'$($statisticObj.Object)', '$($statisticObj.Target)'")
                        $queryList += New-Object -TypeName PSObject -Property @{Object = $statisticObj.Object;
                            Target                                                     = $statisticObj.Target;
                            Query                                                      = $query
                        }
                    }
                }

                try {
                    foreach ($queryObj in $queryList ) {
                        Write-Message -Message "Running statement $($queryObj.Query)" -Level Verbose
                        $results = $server | Invoke-DbaQuery  -Query $queryObj.Query -Database $db.Name -MessagesToOutput

                        if ($Option -eq 'StatHeader') {
                            foreach ($row in $results) {
                                [PSCustomObject]@{
                                    ComputerName           = $server.ComputerName
                                    InstanceName           = $server.ServiceName
                                    SqlInstance            = $server.DomainInstanceName
                                    Database               = $db.Name
                                    Object                 = $queryObj.Object
                                    Target                 = $queryObj.Target
                                    Cmd                    = $queryObj.Query
                                    Name                   = $row[0]
                                    Updated                = $row[1]
                                    Rows                   = $row[2]
                                    RowsSampled            = $row[3]
                                    Steps                  = $row[4]
                                    Density                = $row[5]
                                    AverageKeyLength       = $row[6]
                                    StringIndex            = $row[7]
                                    FilterExpression       = $row[8]
                                    UnfilteredRows         = $row[9]
                                    PersistedSamplePercent = $row[10]
                                }
                            }
                        }
                        if ($Option -eq 'DensityVector') {
                            foreach ($row in $results) {
                                [PSCustomObject]@{
                                    ComputerName  = $server.ComputerName
                                    InstanceName  = $server.ServiceName
                                    SqlInstance   = $server.DomainInstanceName
                                    Database      = $db.Name
                                    Object        = $queryObj.Object
                                    Target        = $queryObj.Target
                                    Cmd           = $queryObj.Query
                                    AllDensity    = $row[0].ToString()
                                    AverageLength = $row[1]
                                    Columns       = $row[2]
                                }
                            }
                        }
                        if ($Option -eq 'Histogram') {
                            foreach ($row in $results) {
                                [PSCustomObject]@{
                                    ComputerName      = $server.ComputerName
                                    InstanceName      = $server.ServiceName
                                    SqlInstance       = $server.DomainInstanceName
                                    Database          = $db.Name
                                    Object            = $queryObj.Object
                                    Target            = $queryObj.Target
                                    Cmd               = $queryObj.Query
                                    RangeHiKey        = $row[0]
                                    RangeRows         = $row[1]
                                    EqualRows         = $row[2]
                                    DistinctRangeRows = $row[3]
                                    AverageRangeRows  = $row[4]
                                }
                            }
                        }
                        if ($Option -eq 'StatsStream') {
                            foreach ($row in $results) {
                                [PSCustomObject]@{
                                    ComputerName = $server.ComputerName
                                    InstanceName = $server.ServiceName
                                    SqlInstance  = $server.DomainInstanceName
                                    Database     = $db.Name
                                    Object       = $queryObj.Object
                                    Target       = $queryObj.Target
                                    Cmd          = $queryObj.Query
                                    StatsStream  = $row[0]
                                    Rows         = $row[1]
                                    DataPages    = $row[2]
                                }
                            }
                        }
                    }
                } catch {
                    Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                }
            }
        }
    }
}