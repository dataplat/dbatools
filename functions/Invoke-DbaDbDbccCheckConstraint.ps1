function Invoke-DbaDbDbccCheckConstraint {
    <#
    .SYNOPSIS
        Execution of Database Console Command DBCC CHECKCONSTRAINTS

    .DESCRIPTION
        Executes the command DBCC CHECKCONSTRAINTS and returns results

        Reports and corrects pages and row count inaccuracies in the catalog views.
        These inaccuracies may cause incorrect space usage reports returned by the sp_spaceused system stored procedure.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkconstraints-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER Object
        The table or constraint to be checked.
        When table_name or table_id is specified, all enabled constraints on that table are checked.
        When constraint_name or constraint_id is specified, only that constraint is checked.
        If neither a table identifier nor a constraint identifier is specified, all enabled constraints on all tables in the current database are checked.

    .PARAMETER AllConstraints
        Checks all enabled and disabled constraints on the table if the table name is specified or if all tables are checked;
        Otherwise, checks only the enabled constraint.
        Has no effect when a constraint is specified

    .PARAMETER AllErrorMessages
        Returns all rows that violate constraints in the table that is checked.
        The default is the first 200 rows.

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
        https://dbatools.io/Invoke-DbaDbDbccCheckConstraint

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckConstraint -SqlInstance SqlServer2017

        Runs the command DBCC CHECKCONSTRAINTS to check all enabled constraints on all tables for all databases for the instance SqlServer2017. Connect using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckConstraint -SqlInstance SqlServer2017 -Database CurrentDB

        Connect to instance SqlServer2017 using Windows Authentication and run the command DBCC CHECKCONSTRAINTS to check all enabled constraints on all tables in the CurrentDB database.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckConstraint -SqlInstance SqlServer2017 -Database CurrentDB -Object Sometable

        Connects to CurrentDB on instance SqlServer2017 using Windows Authentication and runs the command DBCC CHECKCONSTRAINTS(SometableId) to check all enabled constraints in the table.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckConstraint -SqlInstance SqlServer2017 -Database CurrentDB -Object ConstraintId

        Connects to CurrentDB on instance SqlServer2017 using Windows Authentication and runs the command DBCC CHECKCONSTRAINTS(ConstraintId) to check the constraint with constraint_id = ConstraintId.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Invoke-DbaDbDbccCheckConstraint -SqlInstance SqlServer2017 -SqlCredential $cred -Database CurrentDB -Object TableId -AllConstraints -AllErrorMessages -NoInformationalMessages

        Connects to CurrentDB on instance SqlServer2017 using sqladmin credential and runs the command DBCC CHECKCONSTRAINTS(TableId) WITH ALL_CONSTRAINTS, ALL_ERRORMSGS, NO_INFOMSGS to check all enabled and disabled constraints on the table with able_id = TableId. Returns all rows that violate constraints.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Invoke-DbaDbDbccCheckConstraint -WhatIf

        Displays what will happen if command DBCC CHECKCONSTRAINTS is called against all databses on Sql1 and Sql2/sqlexpress

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$Object,
        [switch]$AllConstraints,
        [switch]$AllErrorMessages,
        [switch]$NoInformationalMessages,
        [switch]$EnableException
    )
    begin {
        $withCount = 0
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC CHECKCONSTRAINTS(#options#)")
        if (Test-Bound -ParameterName AllConstraints) {
            $null = $stringBuilder.Append(" WITH ALL_CONSTRAINTS")
            $withCount++
        }
        if (Test-Bound -ParameterName AllErrorMessages) {
            if ($withCount -eq 0) {
                $null = $stringBuilder.Append(" WITH ALL_ERRORMSGS")
            } else {
                $null = $stringBuilder.Append(", ALL_ERRORMSGS")
            }
            $withCount++
        }
        if (Test-Bound -ParameterName NoInformationalMessages) {
            if ($withCount -eq 0) {
                $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
            } else {
                $null = $stringBuilder.Append(", NO_INFOMSGS")
            }
        }

    }
    process {
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

                try {
                    $query = $StringBuilder.ToString()
                    if (Test-Bound -ParameterName Object) {
                        if ($object -match '^\d+$') {
                            $query = $query.Replace('#options#', "$Object")
                        } else {
                            $query = $query.Replace('#options#', "'$Object'")
                        }
                    } else {
                        $query = $query.Replace('(#options#)', "")
                    }

                    if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                        Write-Message -Message "Query to run: $query" -Level Verbose
                        $results = $server | Invoke-DbaQuery  -Query $query -Database $db.Name -MessagesToOutput
                    }
                } catch {
                    Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                }

                if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                    $output = $null
                    if (($null -eq $results) -or ($results.GetType().Name -eq 'String') ) {
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.Name
                            Cmd          = $query.ToString()
                            Output       = $results
                            Table        = $null
                            Constraint   = $null
                            Where        = $null
                        }
                    } elseif (($results.GetType().Name -eq 'Object[]') -or ($results.GetType().Name -eq 'DataRow')) {
                        foreach ($row in $results) {
                            if ($row.GetType().Name -eq 'String') {
                                $output = $row.ToString()
                            } else {
                                [PSCustomObject]@{
                                    ComputerName = $server.ComputerName
                                    InstanceName = $server.ServiceName
                                    SqlInstance  = $server.DomainInstanceName
                                    Database     = $db.Name
                                    Cmd          = $query.ToString()
                                    Output       = $output
                                    Table        = $row[0]
                                    Constraint   = $row[1]
                                    Where        = $row[2]

                                }
                            }
                        }
                    }
                }
            }
        }
    }
}