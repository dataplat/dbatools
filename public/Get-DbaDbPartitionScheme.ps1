function Get-DbaDbPartitionScheme {
    <#
    .SYNOPSIS
        Retrieves partition schemes from SQL Server databases for table partitioning management.

    .DESCRIPTION
        Retrieves partition scheme objects from one or more SQL Server databases, providing details about how partitioned tables and indexes are distributed across filegroups. Partition schemes define the physical storage mapping for partitioned tables by specifying which filegroups contain each partition's data. This function helps DBAs inventory existing partition schemes when planning table partitioning strategies, troubleshooting performance issues with partitioned tables, or preparing for partition maintenance operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        To get users from specific database(s).

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server.

    .PARAMETER PartitionScheme
        The name(s) of the partition scheme(s).

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
        https://dbatools.io/Get-DbaDbPartitionScheme

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionScheme -SqlInstance sql2016

        Gets all database partition schemes.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionScheme -SqlInstance Server1 -Database db1

        Gets the partition schemes for the db1 database.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionScheme -SqlInstance Server1 -ExcludeDatabase db1

        Gets the partition schemes for all databases except db1.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbPartitionScheme

        Gets the partition schemes for the databases on Sql1 and Sql2/sqlexpress.

    .EXAMPLE
        PS C:\> Get-DbaDbPartitionScheme -SqlInstance localhost -Database TestDB -PartitionScheme partSch01

        Gets the partition scheme partSch01 for the TestDB on localhost.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias("Name")]
        [string[]]$PartitionScheme,
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

                $partitionSchemes = $db.PartitionSchemes

                if ($PartitionScheme) {
                    $partitionSchemes = $partitionSchemes | Where-Object { $_.Name -in $PartitionScheme }
                }

                if (!$partitionSchemes) {
                    Write-Message -Message "No Partition Schemes exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }

                $partitionSchemes | ForEach-Object {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, Name, PartitionFunction
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-DbaDatabasePartitionScheme
    }
}