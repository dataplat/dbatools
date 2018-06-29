#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Move-DbaRegisteredServer {
    <#
        .SYNOPSIS
            Moves registered servers around SQL Server Central Management Server (CMS)

        .DESCRIPTION
            Moves registered servers around SQL Server Central Management Server (CMS)

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Name
            Specifies one or more reg servers to move. Name is the visible name in SSMS CMS interface (labeled Registered Server Name)

        .PARAMETER ServerName
            Specifies one or more reg servers to move. Server Name is the actual instance name (labeled Server Name)
    
        .PARAMETER NewGroup
            The new group. If no new group is specified, the default root will used

        .PARAMETER InputObject
            Allows results from Get-DbaRegisteredServer to be piped in

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
            https://dbatools.io/Move-DbaRegisteredServer

        .EXAMPLE
            Move-DbaRegisteredServer -SqlInstance sql2012 -Group HR, Accounting

            Removes all servers from the HR and Accounting groups on sql2012

        .EXAMPLE
            Move-DbaRegisteredServer -SqlInstance sql2012 -Group HR\Development

            Removes all servers from the HR and sub-group Development from the CMS on sql2012.
    
        .EXAMPLE
            Move-DbaRegisteredServer -SqlInstance sql2012 -Confirm:$false

            Removes all registered servers on sql2012 and turns off all prompting
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
        [string]$NewGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer[]]$InputObject,
        [switch]$EnableException
    )
    
    begin {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Name) -and (Test-Bound -Not -ParameterName ServerName)) {
            Stop-Function -Message "Name or ServerName must be specified when using -SqlInstance"
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRegisteredServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $Name -ServerName $ServerName
            
        }
        
        foreach ($regserver in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $regserver
            
            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }
            
            $server = $parentserver.ServerConnection.SqlConnectionObject
            
            if ((Test-Bound -ParameterName NewGroup)) {
                $group = Get-DbaRegisteredServerGroup -SqlInstance $server -Group $NewGroup
                
                if (-not $group) {
                    Stop-Function -Message "$NewGroup not found on $server" -Continue
                }
            }
            else {
                $group = Get-DbaRegisteredServerGroup -SqlInstance $server -Id 1
            }
            
            if ($Pscmdlet.ShouldProcess($regserver.SqlInstance, "Moving $($regserver.Name) to $group")) {
                try {
                    $null = $parentserver.ServerConnection.ExecuteNonQuery($regserver.ScriptMove($group).GetScript())
                    Get-DbaRegisteredServer -SqlInstance $server -Name $regserver.Name -ServerName $regserver.ServerName
                }
                catch {
                    Stop-Function -Message "Failed to move $($regserver.Name) to $NewGroup on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}