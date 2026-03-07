function Invoke-DbaDbDbccCheckDb {
    <#
    .SYNOPSIS
        Checks the logical and physical integrity of all objects in a SQL Server database using DBCC CHECKDB

    .DESCRIPTION
        Executes DBCC CHECKDB to verify the integrity of all objects in the specified databases. This is the primary database consistency check command that includes DBCC CHECKALLOC, DBCC CHECKTABLE, and DBCC CHECKCATALOG operations. The command returns information about any integrity issues found, helping DBAs identify corruption or consistency problems.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to run CHECKDB against. Accepts multiple database names.
        If not specified, all accessible databases on the instance will be processed.

    .PARAMETER InputObject
        Accepts piped database objects from Get-DbaDatabase. When provided, SqlInstance and Database parameters are not required.

    .PARAMETER NoIndex
        Specifies that intensive checks of nonclustered indexes for user tables should not be performed.
        This decreases the overall execution time. Use this when you need a faster integrity check that still validates all clustered indexes, data pages, and the logical structure of nonclustered indexes.

    .PARAMETER AllErrorMessages
        Returns all reported errors per object instead of limiting output to the first 200 errors per object.
        Use this when you need a complete inventory of integrity issues, especially when diagnosing widespread corruption.

    .PARAMETER ExtendedLogicalChecks
        Enables extended logical checks on an indexed view, XML indexes, and spatial indexes where present.
        Use this when you want a thorough check of indexed views and XML/spatial indexes. Requires SQL Server 2008 or later.

    .PARAMETER NoInformationalMessages
        Suppresses informational messages like "DBCC execution completed" and processing status updates.
        Use this when automating checks in scripts where you only want to capture actual errors, not DBCC status messages.

    .PARAMETER TabLock
        Causes DBCC CHECKDB to obtain locks instead of using an internal database snapshot.
        This includes a short-term exclusive (X) lock on the database. Use this for faster execution on heavily loaded databases where an internal snapshot may be expensive.

    .PARAMETER EstimateOnly
        Displays the estimated amount of tempdb space needed to run DBCC CHECKDB with all specified options.
        The actual database check is not performed.

    .PARAMETER PhysicalOnly
        Limits the checking to the integrity of the physical structure of the page and record headers, and the consistency between pages' allocation and the structures recorded in the object metadata.
        This provides a fast, low-overhead integrity check for large databases.

    .PARAMETER DataPurity
        Causes DBCC CHECKDB to check the database for column values that are not valid or out-of-range.
        This check is enabled by default on databases upgraded from SQL Server 2004 or earlier.

    .PARAMETER MaxDop
        Overrides the max degree of parallelism for the DBCC CHECKDB statement. MaxDop can limit the number of processors used during execution.

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
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDbccCheckDb

    .OUTPUTS
        PSCustomObject

        Returns one object per database processed with the following properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: Name of the database that was checked
        - Cmd: The DBCC CHECKDB command that was executed
        - Output: DBCC output messages including any errors or informational messages

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckDb -SqlInstance SqlServer2017

        Runs DBCC CHECKDB against all accessible databases on SqlServer2017 using Windows Authentication.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckDb -SqlInstance SqlServer2017 -Database AdventureWorks

        Runs DBCC CHECKDB against the AdventureWorks database on SqlServer2017.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckDb -SqlInstance SqlServer2017 -Database AdventureWorks -PhysicalOnly

        Runs a fast, physical-only integrity check against AdventureWorks on SqlServer2017.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckDb -SqlInstance SqlServer2017 -Database AdventureWorks -NoIndex -NoInformationalMessages

        Runs DBCC CHECKDB against AdventureWorks skipping nonclustered index checks and suppressing informational messages.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckDb -SqlInstance SqlServer2017 -Database AdventureWorks -MaxDop 2

        Runs DBCC CHECKDB against AdventureWorks limiting parallelism to 2 processors.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCheckDb -SqlInstance SqlServer2017 -Database AdventureWorks -EstimateOnly

        Returns the estimated tempdb space required to run DBCC CHECKDB against AdventureWorks without performing the actual check.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SqlServer2017 -Database AdventureWorks | Invoke-DbaDbDbccCheckDb -PhysicalOnly

        Pipes the AdventureWorks database object from Get-DbaDatabase and runs a physical-only DBCC CHECKDB against it.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Invoke-DbaDbDbccCheckDb -WhatIf

        Displays what will happen if DBCC CHECKDB is run against all databases on Sql1 and Sql2/sqlexpress.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$NoIndex,
        [switch]$AllErrorMessages,
        [switch]$ExtendedLogicalChecks,
        [switch]$NoInformationalMessages,
        [switch]$TabLock,
        [switch]$EstimateOnly,
        [switch]$PhysicalOnly,
        [switch]$DataPurity,
        [int]$MaxDop,
        [switch]$EnableException
    )
    begin {
        $withOptions = New-Object System.Collections.ArrayList
        if (Test-Bound -ParameterName NoIndex) {
            $null = $withOptions.Add("NOINDEX")
        }
        if (Test-Bound -ParameterName AllErrorMessages) {
            $null = $withOptions.Add("ALL_ERRORMSGS")
        }
        if (Test-Bound -ParameterName ExtendedLogicalChecks) {
            $null = $withOptions.Add("EXTENDED_LOGICAL_CHECKS")
        }
        if (Test-Bound -ParameterName NoInformationalMessages) {
            $null = $withOptions.Add("NO_INFOMSGS")
        }
        if (Test-Bound -ParameterName TabLock) {
            $null = $withOptions.Add("TABLOCK")
        }
        if (Test-Bound -ParameterName EstimateOnly) {
            $null = $withOptions.Add("ESTIMATEONLY")
        }
        if (Test-Bound -ParameterName PhysicalOnly) {
            $null = $withOptions.Add("PHYSICAL_ONLY")
        }
        if (Test-Bound -ParameterName DataPurity) {
            $null = $withOptions.Add("DATA_PURITY")
        }
        if (Test-Bound -ParameterName MaxDop) {
            $null = $withOptions.Add("MAXDOP = $MaxDop")
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

            $InputObject += $dbs | Where-Object IsAccessible
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            Write-Message -Level Verbose -Message "Processing $($db.Name) on $($server.DomainInstanceName)"

            if ($db.IsAccessible -eq $false) {
                Stop-Function -Message "The database $($db.Name) is not accessible. Skipping." -Continue
            }

            try {
                $query = "DBCC CHECKDB([$($db.Name)])"
                if ($withOptions.Count -gt 0) {
                    $query += " WITH $($withOptions -join ', ')"
                }

                if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $($server.DomainInstanceName)")) {
                    Write-Message -Message "Query to run: $query" -Level Verbose
                    $results = $server | Invoke-DbaQuery -Query $query -Database $db.Name -MessagesToOutput
                }
            } catch {
                Stop-Function -Message "Error capturing data on $($db.Name)" -Target $server.DomainInstanceName -ErrorRecord $_ -Exception $_.Exception -Continue
            }

            if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $db.Name
                    Cmd          = $query.ToString()
                    Output       = $results
                }
            }
        }
    }
}
