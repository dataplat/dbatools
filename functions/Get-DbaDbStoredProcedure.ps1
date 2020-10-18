function Get-DbaDbStoredProcedure {
    <#
    .SYNOPSIS
        Gets database Stored Procedures

    .DESCRIPTION
        Gets database Stored Procedures

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

    .PARAMETER ExcludeSystemSp
        This switch removes all system objects from the Stored Procedure collection

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, StoredProcedure, Proc
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbStoredProcedure

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance sql2016

        Gets all database Stored Procedures

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -Database db1

        Gets the Stored Procedures for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -ExcludeDatabase db1

        Gets the Stored Procedures for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -ExcludeSystemSp

        Gets the Stored Procedures for all databases that are not system objects

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbStoredProcedure

        Gets the Stored Procedures for the databases on Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance Server1 -ExcludeSystem | Get-DbaDbStoredProcedure

        Pipe the databases from Get-DbaDatabase into Get-DbaDbStoredProcedure

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemSp,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
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
            if ($db.StoredProcedures.Count -eq 0) {
                Write-Message -Message "No Stored Procedures exist in the $db database on $instance" -Target $db -Level Output
                continue
            }

            foreach ($proc in $db.StoredProcedures) {
                if ( (Test-Bound -ParameterName ExcludeSystemSp) -and $proc.IsSystemObject ) {
                    continue
                }

                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name ComputerName -value $proc.Parent.ComputerName
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name InstanceName -value $proc.Parent.InstanceName
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name SqlInstance -value $proc.Parent.SqlInstance
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name Database -value $db.Name

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'ID as ObjectId', 'CreateDate',
                'DateLastModified', 'Name', 'ImplementationType', 'Startup'
                Select-DefaultView -InputObject $proc -Property $defaults
            }
        }
    }
}
