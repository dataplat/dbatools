function Get-DbaDbObjectTrigger {
    <#
    .SYNOPSIS
        Get all existing database triggers on one or more SQL instances.

    .DESCRIPTION
        Get all existing database triggers on one or more SQL instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlCredential object used to connect to the SQL Server as a different user.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER InputObject
        Allow pipedline input from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/ca

    .NOTES
        Tags: Database, Trigger
        Author: Cláudio Silva (@claudioessilva), https://claudioessilva.eu

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
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($null -ne $InputObject) {
            $InputObject | foreach-object {
                if (-not ($_ -as [Microsoft.SqlServer.Management.Smo.Table]) -or (-not ($_ -as [Microsoft.SqlServer.Management.Smo.View]))) {
                    Stop-Function -Message "InputObject $_ not of type Table or View." -Continue
                    return
                }
            }
        }
    }
    process {
        foreach ($Instance in $SqlInstance) {
            $InputObject += Get-DbaDbTable -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            $InputObject += Get-DbaDbView -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
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