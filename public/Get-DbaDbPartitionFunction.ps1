function Get-DbaDbPartitionFunction {
    <#
    .SYNOPSIS
        Retrieves partition function definitions and metadata from SQL Server databases.

    .DESCRIPTION
        Retrieves partition function definitions and their metadata from one or more SQL Server databases. Partition functions define how table or index data is distributed across multiple partitions based on the values of a partitioning column. This function returns details like creation date, function name, and number of partitions, making it useful for documenting partitioning schemes, analyzing partition distribution strategies, and auditing partitioned table configurations before maintenance operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for partition functions. Accepts multiple database names as an array.
        Use this when you need to examine partition functions in specific databases rather than scanning all accessible databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies which databases to skip when searching for partition functions. Accepts multiple database names as an array.
        Use this to avoid scanning system databases or databases where you know partition functions don't exist, improving performance on instances with many databases.

    .PARAMETER PartitionFunction
        Specifies which partition functions to retrieve by name. Accepts multiple function names as an array and supports wildcards.
        Use this when you need details about specific partition functions rather than retrieving all partition functions from the target databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Partition
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbPartitionFunction

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionFunction -SqlInstance sql2016

        Gets all database partition functions.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionFunction -SqlInstance Server1 -Database db1

        Gets the partition functions for the db1 database.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionFunction -SqlInstance Server1 -ExcludeDatabase db1

        Gets the partition functions for all databases except db1.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbPartitionFunction

        Gets the partition functions for the databases on Sql1 and Sql2/sqlexpress.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionFunction -SqlInstance localhost -Database TestDB -PartitionFunction partFun01

        Gets the partition function partFun01 for the TestDB on localhost.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias("Name")]
        [string[]]$PartitionFunction,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                if (!$db.IsAccessible) {
                    Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                    continue
                }

                $partitionFunctions = $db.partitionfunctions

                if ($PartitionFunction) {
                    $partitionFunctions = $partitionFunctions | Where-Object { $_.Name -in $PartitionFunction }
                }

                if (!$partitionfunctions) {
                    Write-Message -Message "No Partition Functions exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }

                $partitionFunctions | ForEach-Object {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, Name, NumberOfPartitions
                }
            }
        }
    }
}