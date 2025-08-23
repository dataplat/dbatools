function Get-DbaDbObjectTrigger {
    <#
    .SYNOPSIS
        Retrieves triggers attached to tables and views across SQL Server databases.

    .DESCRIPTION
        Retrieves all DML triggers that are attached to tables and views within specified databases. This function helps DBAs inventory trigger-based business logic, identify potential performance bottlenecks, and document database dependencies. You can filter results by database, object type (tables vs views), or pipe in specific objects from Get-DbaDbTable and Get-DbaDbView. Returns trigger details including enabled status and last modified date for impact analysis and change management.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        Specifies which databases to search for table and view triggers. Accepts wildcards for pattern matching.
        Use this when you need to audit triggers in specific databases rather than scanning the entire instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from trigger enumeration. Accepts wildcards for pattern matching.
        Useful when you want to skip system databases or databases known to have no custom triggers.

    .PARAMETER Type
        Filters triggers by the type of object they are attached to: Table, View, or All (default).
        Use 'Table' or 'View' when you need to focus on triggers for specific object types during auditing or troubleshooting.

    .PARAMETER InputObject
        Accepts specific table or view objects from Get-DbaDbTable and Get-DbaDbView via pipeline input.
        Use this when you want to check triggers on particular tables or views rather than scanning entire databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Trigger
        Author: Claudio Silva (@claudioessilva), claudioessilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbObjectTrigger

    .EXAMPLE
        PS C:\> Get-DbaDbObjectTrigger -SqlInstance sql2017

        Returns all database triggers

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database supa | Get-DbaDbObjectTrigger

        Returns all triggers for database supa on sql2017

    .EXAMPLE
        PS C:\> Get-DbaDbObjectTrigger -SqlInstance sql2017 -Database supa

        Returns all triggers for database supa on sql2017

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet('All', 'Table', 'View')]
        [string]$Type = 'All',
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($InputObject.Count -gt 0) {
            $InputObject | ForEach-Object {
                if (-not ($_ -is [Microsoft.SqlServer.Management.Smo.TableViewBase])) {
                    Stop-Function -Message "InputObject $_ is not of type Table or View." -Continue
                    return
                }
            }
        }

        foreach ($Instance in $SqlInstance) {
            if ($Type -in @('All', 'Table')) {
                $InputObject += Get-DbaDbTable -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
            if ($Type -in @('All', 'View')) {
                $InputObject += Get-DbaDbView -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
        }

        foreach ($obj in $InputObject) {
            try {
                foreach ($trigger in ($obj.Triggers)) {
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name ComputerName -value $trigger.Parent.ComputerName
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name InstanceName -value $trigger.Parent.InstanceName
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name SqlInstance -value $trigger.Parent.SqlInstance
                    Select-DefaultView -InputObject $trigger -Property ComputerName, InstanceName, SqlInstance, Name, Parent, IsEnabled, DateLastModified
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}