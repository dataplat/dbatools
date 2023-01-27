function Get-DbaDbUserDefinedTableType {
    <#
    .SYNOPSIS
        Gets database user defined table types

    .DESCRIPTION
        Gets database user defined table types

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        To get Stored Procedures from specific database(s)

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, UserDefinedTableType, Type
        Author: Ant Green (@ant_green)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbUserDefinedTableType

    .EXAMPLE
        PS C:\> Get-DbaDbUserDefinedTableType -SqlInstance sql2016

        Gets all database Stored Procedures

    .EXAMPLE
        PS C:\> Get-DbaDbUserDefinedTableType -SqlInstance Server1 -Database db1

        Gets the Stored Procedures for the db1 database

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    process {
        if (Test-Bound SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }
            if ($db.UserDefinedTableTypes.Count -eq 0) {
                Write-Message -Message "No User Defined Table Types exist in the $db database on $instance" -Target $db -Level Output
                continue
            }

            foreach ($tabletype in $db.UserDefinedTableTypes) {
                if ( $tabletype.IsSystemObject ) {
                    continue
                }

                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name ComputerName -value $tabletype.Parent.ComputerName
                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name InstanceName -value $tabletype.Parent.InstanceName
                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name SqlInstance -value $tabletype.Parent.SqlInstance
                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name Database -value $db.Name

                $defaults = 'ComputerName, InstanceName, SqlInstance, Database, ID, Name, Columns, Owner, CreateDate, IsSystemObject, Version'

                Select-DefaultView -InputObject $tabletype -Property $defaults
            }
        }
    }
}
