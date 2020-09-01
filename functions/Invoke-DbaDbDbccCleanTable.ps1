function Invoke-DbaDbDbccCleanTable {
    <#
    .SYNOPSIS
        Execution of Database Console Command DBCC CLEANTABLE

    .DESCRIPTION
        Executes the command DBCC CLEANTABLE against defined objects and returns results

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
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER Object
        The table(s) or indexed view(s) to be cleaned.

    .PARAMETER BatchSize
        Is the number of rows processed per transaction.
        If not specified, or if 0 is specified, the statement processes the whole table in one transaction.

    .PARAMETER NoInformationalMessages
        Suppresses all informational messages.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDbccCleanTable

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCleanTable -SqlInstance SqlServer2017 -Database CurrentDB -Object 'dbo.SomeTable'

        Connects to CurrentDB on instance SqlServer2017 using Windows Authentication and runs the command DBCC CLEANTABLE('CurrentDB', 'dbo.SomeTable') to reclaim space after variable-length columns have been dropped.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCleanTable -SqlInstance SqlServer2017 -Database CurrentDB -Object 34636372 -BatchSize 5000

        Connects to CurrentDB on instance SqlServer2017 using Windows Authentication and runs the command DBCC CLEANTABLE('CurrentDB', 34636372, 5000) to reclaim space from table with Table_Id = 34636372 after variable-length columns have been dropped.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Invoke-DbaDbDbccCleanTable -SqlInstance SqlServer2017 -SqlCredential $cred -Database CurrentDB -Object 'dbo.SomeTable'  -NoInformationalMessages

        Connects to CurrentDB on instance SqlServer2017 using sqladmin credential and runs the command DBCC CLEANTABLE('CurrentDB', 'dbo.SomeTable') WITH NO_INFOMSGS to reclaim space after variable-length columns have been dropped.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Invoke-DbaDbDbccCleanTable -Object 'dbo.SomeTable' -BatchSize 5000

        Runs the command DBCC CLEANTABLE('DatabaseName', 'dbo.SomeTable', 5000) against all databses on Sql1 and Sql2/sqlexpress

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Object,
        [int]$BatchSize,
        [switch]$NoInformationalMessages,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC CLEANTABLE(#options#)")
        if (Test-Bound -ParameterName NoInformationalMessages) {
            $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
        }
    }
    process {
        if (Test-Bound -Not -ParameterName Object) {
            Stop-Function -Message "You must specify a table or indexed view to execute against using -Object"
            return
        }
        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping." -Continue
                }

                foreach ($obj in $Object) {
                    try {
                        $query = $StringBuilder.ToString()
                        $options = New-Object System.Text.StringBuilder
                        if ($obj -match '^\d+$') {
                            $null = $options.Append("'$($db.Name)', $($obj)")
                        } else {
                            $null = $options.Append("'$($db.Name)', '$($obj)'")
                        }
                        if (Test-Bound -ParameterName BatchSize) {
                            $null = $options.Append(", $($BatchSize)")
                        }

                        $query = $query.Replace('#options#', "$($options.ToString())")
                        Write-Message -Message "Query to run: $query" -Level Verbose

                        if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                            Write-Message -Message "Query to run: $query" -Level Verbose
                            $results = $server | Invoke-DbaQuery  -Query $query -Database $db.Name -MessagesToOutput
                        }
                    } catch {
                        Stop-Function -Message "Error running  $query against $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                    }
                    if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                        if (($null -eq $results) -or ($results.GetType().Name -eq 'String') ) {
                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db.Name
                                Object       = $obj
                                Cmd          = $query.ToString()
                                Output       = $results
                            }
                        }
                    }
                }
            }
        }
    }
}