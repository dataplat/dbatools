#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaRegisteredServerGroup {
    <#
        .SYNOPSIS
            Adds registered server groups to SQL Server Central Management Server (CMS).

        .DESCRIPTION
            Adds registered server groups to SQL Server Central Management Server (CMS).

        .PARAMETER SqlInstance
            The target SQL Server instance

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Name
            The Group Name

        .PARAMETER Description
            Optional description
    
        .PARAMETER Group
            The SQL Server Central Management Server group. If no groups are specified, the new group will be created at the root.

        .PARAMETER InputObjects
            Allows results from Get-DbaRegisteredServerGroup to be piped in

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Chrissy LeMaire (@cl)
            Tags: RegisteredServer, CMS

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Add-DbaRegisteredServerGroup

        .EXAMPLE
           Add-DbaRegisteredServerGroup -SqlInstance sql2008 -ServerName sql01 -Name "The 2008 Clustered Instance" -Description "HR's Dedicated SharePoint instance"

           Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, "The 2008 Clustered Instance" will be visible.
           Clearly this is hard to explain ;) 

        .EXAMPLE
            Add-DbaRegisteredServerGroup -SqlInstance sql2012, sql2014 -Group HR -ServerName sql01

            Creates a registered server on sql2012 and sql2014's CMS for sql01, nicknamed sql01, with no description
    
        .EXAMPLE
            Get-DbaRegisteredServerGroup -SqlInstance sql2012 -Group HR | Add-DbaRegisteredServerGroup -ServerName sql01

            Creates a registered server on sql2012's CMS for sql01, nicknamed sql01
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Name,
        [string]$Description,
        [string]$Group,
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )
    
    process {
        foreach ($instance in $SqlInstance) {
            if ((Test-Bound -ParameterName Group)) {
                $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
            }
            else {
                $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
            }
        }
        
        foreach ($reggroup in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $reggroup
            
            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }
            
            if ($Pscmdlet.ShouldProcess($parentserver.SqlInstance, "Adding $Name")) {
                try {
                    $newgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($reggroup, $Name)
                    $newgroup.Description = $Description
                    $newgroup.Create()
                    
                    Get-DbaRegisteredServerGroup -SqlInstance $parentserver.ServerConnection.SqlConnectionObject | Where-Object Id -eq $newgroup.id
                }
                catch {
                    Stop-Function -Message "Failed to add $reggroup on $($parentserver.ServerConnection.ServerInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}