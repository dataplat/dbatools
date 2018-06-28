#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Move-DbaRegisteredServerGroup {
    <#
        .SYNOPSIS
            Gets list of Server Groups objects stored in SQL Server Central Management Server (CMS).

        .DESCRIPTION
            Returns an array of Server Groups found in the CMS.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Group
            Specifies one or more groups to include from SQL Server Central Management Server.

        .PARAMETER ExcludeGroup
            Specifies one or more Central Management Server groups to exclude.
    
        .PARAMETER Id
            Get group by Id(s)

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
            https://dbatools.io/Move-DbaRegisteredServerGroup

        .EXAMPLE
            Move-DbaRegisteredServerGroup -SqlInstance sqlserver2014a

            Gets the top level groups from the CMS on sqlserver2014a, using Windows Credentials.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential

            Gets the top level groups from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

            Gets the HR and Accounting groups from the CMS on sqlserver2014a.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

            Returns the sub-group Development of the HR group from the CMS on sqlserver2014a.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Group,
        [parameter(Mandatory)]
        [string]$NewGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Group)) {
            Stop-Function -Message "Group must be specified when using -SqlInstance"
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -EnableException -Group $Group
        }
        
        foreach ($regservergroup in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $regservergroup
            
            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }
            
            $server = $parentserver.ServerConnection.SqlConnectionObject
            
            if ($NewGroup -eq 'Default') {
                $groupobject = Get-DbaRegisteredServerGroup -SqlInstance $server -Id 1
            }
            else {
                $groupobject = Get-DbaRegisteredServerGroup -SqlInstance $server -Group $NewGroup
            }
            
            if (-not $groupobject) {
                Stop-Function -Message "Group '$NewGroup' not found on $server" -Continue
            }
            
            if ($Pscmdlet.ShouldProcess($regserver.SqlInstance, "Moving $($regservergroup.Name) to $groupobject")) {
                try {
                    $null = $parentserver.ServerConnection.ExecuteNonQuery($regservergroup.ScriptMove($groupobject).GetScript())
                    Get-DbaRegisteredServerGroup -SqlInstance $server -Group $group
                }
                catch {
                    Stop-Function -Message "Failed to move $($regserver.Name) to $NewGroup on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}