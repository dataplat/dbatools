function Get-DbaDbCheckConstraint {
    <#
    .SYNOPSIS
        Gets database Check constraints.

    .DESCRIPTION
        Gets database Checks constraints.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for check constraints. Accepts wildcards and multiple database names.
        Use this when you need to examine constraints on specific databases rather than all accessible databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the check constraint search. Accepts multiple database names.
        Useful when you want to scan most databases but skip certain ones like development or temporary databases.

    .PARAMETER ExcludeSystemTable
        Excludes check constraints from system tables when searching through databases.
        Use this to focus only on user-created tables and avoid system table constraints that are typically not relevant for DBA reviews.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Claudio Silva (@ClaudioESSilva), claudioessilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbCheckConstraint

    .EXAMPLE
        PS C:\> Get-DbaDbCheckConstraint -SqlInstance sql2016

        Gets all database check constraints.

    .EXAMPLE
        PS C:\> Get-DbaDbCheckConstraint -SqlInstance Server1 -Database db1

        Gets the check constraints for the db1 database.

    .EXAMPLE
        PS C:\> Get-DbaDbCheckConstraint -SqlInstance Server1 -ExcludeDatabase db1

        Gets the check constraints for all databases except db1.

    .EXAMPLE
        PS C:\> Get-DbaDbCheckConstraint -SqlInstance Server1 -ExcludeSystemTable

        Gets the check constraints for all databases that are not system objects.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbCheckConstraint

        Gets the check constraints for the databases on Sql1 and Sql2/sqlexpress.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemTable,
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

                foreach ($tbl in $db.Tables) {
                    if ( (Test-Bound -ParameterName ExcludeSystemTable) -and $tbl.IsSystemObject ) {
                        continue
                    }

                    if ($tbl.Checks.Count -eq 0) {
                        Write-Message -Message "No Checks exist in $tbl table on the $db database on $instance" -Target $tbl -Level Verbose
                        continue
                    }

                    foreach ($ck in $tbl.Checks) {
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $ck -MemberType NoteProperty -Name DatabaseId -value $db.Id

                        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Parent', 'ID', 'CreateDate',
                        'DateLastModified', 'Name', 'IsEnabled', 'IsChecked', 'NotForReplication', 'Text', 'State'
                        Select-DefaultView -InputObject $ck -Property $defaults
                    }
                }
            }
        }
    }
}