#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaAgDatabase {
<#
    .SYNOPSIS
        Adds a database to an availability group on a SQL Server instance.
        
    .DESCRIPTION
        Adds a database to an availability group on a SQL Server instance.
    
    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.
        
    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
        
    .PARAMETER AvailabilityGroup
        Only add specific availability groups.
        
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
        https://dbatools.io/Add-DbaAgDatabase
        
    .EXAMPLE
        Add-DbaAgDatabase -SqlInstance sqlserver2012 -AllAvailabilityGroup
        
        Adds all availability groups on the sqlserver2014 instance. Prompts for confirmation.
        
    .EXAMPLE
        Add-DbaAgDatabase -SqlInstance sqlserver2012 -AvailabilityGroup ag1, ag2 -Confirm:$false
        
        Adds the ag1 and ag2 availability groups on sqlserver2012.  Does not prompt for confirmation.
        
    .EXAMPLE
        Get-AvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroup availability group1 | Add-DbaAgDatabase
        
        Adds the availability groups returned from the Get-AvailabilityGroup function. Prompts for confirmation.
        
        
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
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
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }
        
        foreach ($db in $InputObject) {
            $ags = Get-DbaAvailabilityGroup -SqlInstance $db.Parent -AvailabilityGroup $AvailabilityGroup
            
            foreach ($ag in $ags) {
                if ($Pscmdlet.ShouldProcess("$instance", "Adding availability group $db to $($db.Parent)")) {
                    try {
                        $agdb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($ag, $db.Name)
                        $ag.AvailabilityDatabases.Add($agdb)
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