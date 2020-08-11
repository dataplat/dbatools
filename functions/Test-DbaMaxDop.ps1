function Test-DbaMaxDop {
    <#
    .SYNOPSIS
        Displays information relating to SQL Server Max Degree of Parallelism setting. Works on SQL Server 2005-2016.

    .DESCRIPTION
        Inspired by Sakthivel Chidambaram's post about SQL Server MAXDOP Calculator (https://blogs.msdn.microsoft.com/sqlsakthi/p/maxdop-calculator/),
        this script displays a SQL Server's: max dop configured, and the calculated recommendation.

        For SQL Server 2016 shows:
        - Instance max dop configured and the calculated recommendation
        - max dop configured per database (new feature)

        More info:
        https://support.microsoft.com/en-us/kb/2806535
        https://blogs.msdn.microsoft.com/sqlsakthi/2012/05/23/wow-we-have-maxdop-calculator-for-sql-server-it-makes-my-job-easier/

        These are just general recommendations for SQL Server and are a good starting point for setting the "max degree of parallelism" option.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: MaxDop, SpConfigure
        Author: Claudio Silva (@claudioessilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Test-DbaMaxDop

    .EXAMPLE
        PS C:\> Test-DbaMaxDop -SqlInstance sql2008, sqlserver2012

        Get Max DOP setting for servers sql2008 and sqlserver2012 and also the recommended one.

    .EXAMPLE
        PS C:\> Test-DbaMaxDop -SqlInstance sql2014 | Select-Object *

        Shows Max DOP setting for server sql2014 with the recommended value. Piping the output to Select-Object * will also show the 'NumaNodes' and 'NumberOfCores' of each instance

    .EXAMPLE
        PS C:\> Test-DbaMaxDop -SqlInstance sqlserver2016 | Select-Object *

        Get Max DOP setting for servers sql2016 with the recommended value. Piping the output to Select-Object * will also show the 'NumaNodes' and 'NumberOfCores' of each instance. Because it is an 2016 instance will be shown 'InstanceVersion', 'Database' and 'DatabaseMaxDop' columns.

    #>
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        $notesDopLT = "Before changing MaxDop, consider that the lower value may have been intentionally set."
        $notesDopGT = "Before changing MaxDop, consider that the higher value may have been intentionally set."
        $notesDopZero = "This is the default setting. Consider using the recommended value instead."
        $notesDopOne = "Some applications like SharePoint, Dynamics NAV, SAP, BizTalk has the need to use MAXDOP = 1. Please confirm that your instance is not supporting one of these applications prior to changing the MaxDop."
        $notesAsRecommended = "Configuration is as recommended."
    }

    process {
        #Variable marked as unused by PSScriptAnalyzer
        #$hasScopedConfig = $false

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Get current configured value
            $maxDop = $server.Configuration.MaxDegreeOfParallelism.ConfigValue

            try {
                #represents the Number of NUMA nodes
                $sql = "SELECT COUNT(DISTINCT memory_node_id) AS NUMA_Nodes FROM sys.dm_os_memory_clerks WHERE memory_node_id!=64"
                $NumaNodes = $server.ConnectionContext.ExecuteScalar($sql)
            } catch {
                Stop-Function -Message "Failed to get Numa node count." -ErrorRecord $_ -Target $server -Continue
            }

            try {
                #represents the Number of Processor Cores
                $sql = "SELECT COUNT(scheduler_id) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE'"
                $numberOfCores = $server.ConnectionContext.ExecuteScalar($sql)
            } catch {
                Stop-Function -Message "Failed to get number of cores." -ErrorRecord $_ -Target $server -Continue
            }

            #Calculate Recommended Max Dop to instance
            #Server with single NUMA node
            if ($NumaNodes -eq 1) {
                if ($numberOfCores -lt 8) {
                    #Less than 8 logical processors - Keep MAXDOP at or below # of logical processors
                    $recommendedMaxDop = $numberOfCores
                } else {
                    #Equal or greater than 8 logical processors - Keep MAXDOP at 8
                    $recommendedMaxDop = 8
                }
            } else {
                #Server with multiple NUMA nodes
                if ($server.VersionMajor -ge 13) {
                    if (($numberOfCores / $NumaNodes) -lt 16) {
                        # On SQL2016+ - Less than 16 logical processors per NUMA node - Keep MAXDOP at or below # of logical processors per NUMA node
                        $recommendedMaxDop = [int]($numberOfCores / $NumaNodes)
                    } else {
                        # Greater than 16 logical processors per NUMA node - Keep MAXDOP at 16
                        $recommendedMaxDop = 16
                    }
                } else {
                    # Greater than 8 logical processors per NUMA node - Keep MAXDOP at 8
                    $recommendedMaxDop = 8
                    if (($numberOfCores / $NumaNodes) -lt 8) {
                        # On previous SQL Server versions - Less than 8 logical processors per NUMA node - Keep MAXDOP at or below # of logical processors per NUMA node
                        $recommendedMaxDop = [int]($numberOfCores / $NumaNodes)
                    } else {
                        # Greater than 8 logical processors per NUMA node - Keep MAXDOP at 8
                        $recommendedMaxDop = 8
                    }
                }
            }

            #Setting notes for instance max dop value
            $notes = $null
            if ($maxDop -eq 1) {
                $notes = $notesDopOne
            } else {
                if ($maxDop -ne 0 -and $maxDop -lt $recommendedMaxDop) {
                    $notes = $notesDopLT
                } else {
                    if ($maxDop -ne 0 -and $maxDop -gt $recommendedMaxDop) {
                        $notes = $notesDopGT
                    } else {
                        if ($maxDop -eq 0) {
                            $notes = $notesDopZero
                        } else {
                            $notes = $notesAsRecommended
                        }
                    }
                }
            }

            [pscustomobject]@{
                ComputerName          = $server.ComputerName
                InstanceName          = $server.ServiceName
                SqlInstance           = $server.DomainInstanceName
                InstanceVersion       = $server.Version
                Database              = "N/A"
                DatabaseMaxDop        = "N/A"
                CurrentInstanceMaxDop = $maxDop
                RecommendedMaxDop     = $recommendedMaxDop
                NumaNodes             = $NumaNodes
                NumberOfCores         = $numberOfCores
                Notes                 = $notes
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, DatabaseMaxDop, CurrentInstanceMaxDop, RecommendedMaxDop, Notes

            # On SQL Server 2016 and higher, MaxDop can be set on a per-database level
            if ($server.VersionMajor -ge 13) {
                #Variable marked as unused by PSScriptAnalyzer
                #$hasScopedConfig = $true
                Write-Message -Level Verbose -Message "SQL Server 2016 or higher detected, checking each database's MaxDop."

                $databases = $server.Databases | Where-Object { $_.IsSystemObject -eq $false }

                foreach ($database in $databases) {
                    if ($database.IsAccessible -eq $false) {
                        Write-Message -Level Verbose -Message "Database $database is not accessible."
                        continue
                    }
                    Write-Message -Level Verbose -Message "Checking database '$($database.Name)'."

                    $dbmaxdop = $database.MaxDop

                    [pscustomobject]@{
                        ComputerName          = $server.ComputerName
                        InstanceName          = $server.ServiceName
                        SqlInstance           = $server.DomainInstanceName
                        InstanceVersion       = $server.Version
                        Database              = $database.Name
                        DatabaseMaxDop        = $dbmaxdop
                        CurrentInstanceMaxDop = $maxDop
                        RecommendedMaxDop     = $recommendedMaxDop
                        NumaNodes             = $NumaNodes
                        NumberOfCores         = $numberOfCores
                        Notes                 = if ($dbmaxdop -eq 0) { "Will use CurrentInstanceMaxDop value" } else { "$notes" }
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, DatabaseMaxDop, CurrentInstanceMaxDop, RecommendedMaxDop, Notes
                }
            }
        }
    }
}