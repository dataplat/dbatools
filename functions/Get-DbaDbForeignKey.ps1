function Get-DbaDbForeignKey {
    <#
        .SYNOPSIS
            Gets database Foreign Keys

        .DESCRIPTION
            Gets database Foreign Keys

        .PARAMETER SqlInstance
            The target SQL Server instance(s)

        .PARAMETER SqlCredential
            Allows you to login to SQL Server using alternative credentials

        .PARAMETER Database
            To get Foreign Keys from specific database(s)

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto populated from the server

        .PARAMETER ExcludeSystemTable
            This switch removes all system objects from the tables collection

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Databases
            Author: Cláudio Silva ( @ClaudioESSilva | https://claudioessilva.eu)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Get-DbaDbForeignKey -SqlInstance sql2016

            Gets all database Foreign Keys

        .EXAMPLE
            Get-DbaDbForeignKey -SqlInstance Server1 -Database db1

            Gets the Foreign Keys for the db1 database

        .EXAMPLE
            Get-DbaDbForeignKey -SqlInstance Server1 -ExcludeDatabase db1

            Gets the Foreign Keys for all databases except db1

        .EXAMPLE
            Get-DbaDbForeignKey -SqlInstance Server1 -ExcludeSystemTable

            Gets the Foreign Keys from all tables that are not system objects from all databases

        .EXAMPLE
            'Sql1','Sql2/sqlexpress' | Get-DbaDbForeignKey

            Gets the Foreign Keys for the databases on Sql1 and Sql2/sqlexpress
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemTable,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
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

                foreach($tbl in $db.Tables) {
                    if ( (Test-Bound -ParameterName ExcludeSystemTable) -and $tbl.IsSystemObject ) {
                        continue
                    }

                    if ($tbl.ForeignKeys.Count -eq 0) {
                        Write-Message -Message "No Foreign Keys exist in $tbl table on the $db database on $instance" -Target $tbl -Level Verbose
                        continue
                    }

                    foreach ($fk in $tbl.ForeignKeys) {
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name ComputerName -value $server.NetName
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name Database -value $db.Name

                        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Table', 'ID', 'CreateDate',
                        'DateLastModified', 'Name', 'IsEnabled', 'IsChecked', 'NotForReplication', 'ReferencedKey', 'ReferencedTable', 'ReferencedTableSchema'
                        Select-DefaultView -InputObject $fk -Property $defaults
                    }
                }
            }
        }
    }
}