function Get-DbaDbCheckConstraint {
    <#
        .SYNOPSIS
            Gets database Check constraints

        .DESCRIPTION
            Gets database Checks constraints

        .PARAMETER SqlInstance
            The target SQL Server instance(s)

        .PARAMETER SqlCredential
            Allows you to login to SQL Server using alternative credentials

        .PARAMETER Database
            To get Checks from specific database(s)

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto populated from the server

        .PARAMETER ExcludeSystemTable
            This switch removes all system objects from the table collection

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
            Get-DbaDbCheckConstraint -SqlInstance sql2016

            Gets all database check constraints

        .EXAMPLE
            Get-DbaDbCheckConstraint -SqlInstance Server1 -Database db1

            Gets the check constraints for the db1 database

        .EXAMPLE
            Get-DbaDbCheckConstraint -SqlInstance Server1 -ExcludeDatabase db1

            Gets the check constraints for all databases except db1

        .EXAMPLE
            Get-DbaDbCheckConstraint -SqlInstance Server1 -ExcludeSystemTable

            Gets the check constraints for all databases that are not system objects

        .EXAMPLE
            'Sql1','Sql2/sqlexpress' | Get-DbaDbCheckConstraint

            Gets the check constraints for the databases on Sql1 and Sql2/sqlexpress
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

                    if ($tbl.Checks.Count -eq 0) {
                        Write-Message -Message "No Checks exist in $tbl table on the $db database on $instance" -Target $tbl -Level Verbose
                        continue
                    }

                    foreach ($ck in $tbl.Checks) {
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name ComputerName -value $server.NetName
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name Database -value $db.Name

                        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Parent', 'ID', 'CreateDate',
                        'DateLastModified', 'Name', 'IsEnabled', 'IsChecked', 'NotForReplication', 'Text', 'State'
                        Select-DefaultView -InputObject $ck -Property $defaults
                    }
                }
            }
        }
    }
}