#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Invoke-DbaAgFailover {
<#
    .SYNOPSIS
        Failover an availability group.
        
    .DESCRIPTION
       Failover an availability group.
        
    .PARAMETER SqlInstance
        The SQL Server instance. Server version must be SQL Server version 2012 or higher.
        
    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential).
        
    .PARAMETER AvailabilityGroup
        Specify the Availability Group name that you want to get information on.
    
    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup

    .PARAMETER Force
        Force Failover and allow data loss
    
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        
    .NOTES
        Tags: AG, AvailabilityGroup, HA
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        
    .LINK
        https://dbatools.io/Invoke-DbaAgFailover
        
    .EXAMPLE
        PS C:\> Invoke-DbaAgFailover -SqlInstance sql2017 -AvailabilityGroup SharePoint
        
        Safely (no potential data loss) fails over the SharePoint AG on sql2017
        
    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017 | Out-GridView -Passthru | Invoke-DbaAgFailover
        
        Safely (no potential data loss) fails over the selected availability groups on sql2017
    
    .EXAMPLE
        PS C:\> Invoke-DbaAgFailover -SqlInstance sql2017 -AvailabilityGroup SharePoint -Force
        
        Forcefully (with potential data loss) fails over the SharePoint AG on sql2017
#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            if ($server.IsHadrEnabled -eq $false) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance" -Target $instance -Continue
            }
            
            $ags = $server.AvailabilityGroups
            if ($AvailabilityGroup) {
                $ags = $ags | Where-Object Name -in $AvailabilityGroup
                
            }
            $InputObject += $ags
        }
        
        foreach ($ag in $InputObject) {
            if ($Force) {
                $ag.FailoverWithPotentialDataLoss()
            }
            else {
                $ag.Failover()
            }
            $ag.Refresh()
            $ag
        }
    }
}