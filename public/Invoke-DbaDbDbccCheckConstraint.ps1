function Invoke-DbaDbDbccCheckConstraint {
    <#
    .SYNOPSIS
        Validates constraint integrity by checking for constraint violations in SQL Server databases

    .DESCRIPTION
        Executes DBCC CHECKCONSTRAINTS to identify rows that violate CHECK, FOREIGN KEY, and other constraints in your databases. This command helps DBAs verify data integrity after bulk imports, constraint modifications, or when troubleshooting data quality issues. You can target specific tables, individual constraints, or scan entire databases for violations. The command returns detailed information about any rows that don't meet constraint requirements, including the table, constraint name, and violating data criteria.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkconstraints-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to check for constraint violations. Accepts multiple database names and supports wildcards for pattern matching.
        If not specified, all accessible databases on the instance will be processed. Use this when you need to target specific databases instead of checking the entire instance.

    .PARAMETER Object
        Specifies the table or constraint to check for violations. Accepts either table names, constraint names, or their numeric IDs.
        When targeting a table, all enabled constraints on that table are validated. When targeting a specific constraint, only that constraint is checked.
        Use this when you need to focus on a specific table after bulk data operations or when investigating a known problematic constraint.

    .PARAMETER AllConstraints
        Forces checking of both enabled and disabled constraints on the specified table or all tables in the database.
        By default, only enabled constraints are validated. Use this when you need to verify data integrity against all constraint definitions, including those temporarily disabled during maintenance operations.
        Has no effect when checking a specific constraint by name or ID.

    .PARAMETER AllErrorMessages
        Returns all constraint violation rows instead of limiting output to the first 200 violations per constraint.
        Use this when you need a complete inventory of data quality issues, especially after bulk imports or when preparing comprehensive data cleanup reports.
        Be cautious with large tables as this can generate extensive output.

    .PARAMETER NoInformationalMessages
        Suppresses informational messages like "DBCC execution completed" and processing status updates.
        Use this when automating constraint checks in scripts where you only want to capture actual constraint violations, not DBCC status messages.
        Helpful for cleaner output when processing multiple databases or integrating results into monitoring systems.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per database when no constraint violations are found, or one object per violating row when violations are detected.

        When no violations exist (Path 1):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: Name of the database that was checked
        - Cmd: The DBCC CHECKCONSTRAINTS command that was executed
        - Output: DBCC informational or status messages, or null if no messages
        - Table: Always null when no violations found
        - Constraint: Always null when no violations found
        - Where: Always null when no violations found

        When constraint violations are found (Path 2):
        Returns one object per violating row with the following properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: Name of the database containing the violation
        - Cmd: The DBCC CHECKCONSTRAINTS command that was executed
        - Output: String containing previous output information
        - Table: Name of the table containing the violating row
        - Constraint: Name of the constraint that was violated
        - Where: The WHERE clause or criteria identifying the violating row

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

        Displays what will happen if command DBCC CHECKCONSTRAINTS is called against all databases on Sql1 and Sql2/sqlexpress.

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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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