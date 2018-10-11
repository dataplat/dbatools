#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaAgDatabase {
<#
    .SYNOPSIS
        Removes a database to an availability group on a SQL Server instance.
        
    .DESCRIPTION
        Removes a database to an availability group on a SQL Server instance.
    
   .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER AvailabilityGroup
        Only remove specific availability groups.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.
        
    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Internal parameter to support piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        
    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        
    .LINK
        https://dbatools.io/Remove-DbaAgDatabase
        
    .EXAMPLE
        PS C:\> Remove-DbaAgDatabase -SqlInstance sqlserver2012 -AllAvailabilityGroup
        
        Removes all availability groups on the sqlserver2014 instance. Prompts for confirmation.
        
    .EXAMPLE
        PS C:\> Remove-DbaAgDatabase -SqlInstance sqlserver2012 -AvailabilityGroup ag1, ag2 -Confirm:$false
        
        Removes the ag1 and ag2 availability groups on sqlserver2012.  Does not prompt for confirmation.
        
    .EXAMPLE
        PS C:\> Get-AvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroup availability group1 | Remove-DbaAgDatabase
        
        Removes the availability groups returned from the Get-AvailabilityGroup function. Prompts for confirmation.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        # needs to accept db or agdb so generic object
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database) -or (Test-Bound -Not -ParameterName AvailabilityGroup)) {
                Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter."
                return
            }
        }
        
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAgDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }
        
        foreach ($db in $InputObject) {
            $ags = Get-DbaAvailabilityGroup -SqlInstance $db.Parent -AvailabilityGroup $AvailabilityGroup
            
            foreach ($ag in $ags) {
                if ($Pscmdlet.ShouldProcess("$instance", "Removeing availability group $db to $($db.Parent)")) {
                    try {
                        $agdb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($ag, $db.Name)
                        $ag.AvailabilityDatabases.Drop($agdb)
                        $db.Refresh()
                        $db
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}