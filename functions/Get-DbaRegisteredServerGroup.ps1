function Get-DbaRegisteredServerGroup {
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

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Tony Wilhelm (@tonywsql)
            Tags: RegisteredServer, CMS

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaRegisteredServerGroup

        .EXAMPLE
            Get-DbaRegisteredServerGroup -SqlInstance sqlserver2014a

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
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Group,
        [object[]]$ExcludeGroup,
        [switch]$EnableException
    )
    begin {
        function Find-CmsGroup {
            [OutputType([object[]])]
            [cmdletbinding()]
            param(
                $CmsGrp,
                $Base = $null,
                $Stopat
            )
            $results = @()

                foreach ($el in $CmsGrp) {
                if ($null -eq $Base -or [string]::IsNullOrWhiteSpace($Base) ) {
                    $partial = $el.name
                }
                else {
                    $partial = "$Base\$($el.name)"
                }
                if ($partial -eq $Stopat) {
                    return $el
                }
                else {
                    foreach ($elg in $el.ServerGroups) {
                        $results += Find-CmsGroup -CmsGrp $elg -Base $partial -Stopat $Stopat
                    }
                }
            }
            return $results
        }
    }

    process {

        if (Test-FunctionInterrupt) {
            return
        }

        $groups = @()
        foreach ($instance in $SqlInstance) {

            try {
                $cmsStore = Get-DbaRegisteredServersStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            }
            catch {
                Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue
            }

            if ($group) {
                foreach ($currentGroup in $group) {
                    $cms = Find-CmsGroup -CmsGrp $cmsStore.DatabaseEngineServerGroup.ServerGroups -Stopat $currentGroup
                    if ($null -eq $cms) {
                        Write-Message -Level Output -Message "No groups found matching '$($currentGroup)' on instance '$instance'."
                        continue
                    }
                    $groups += $cms
                }
            }
            else {
                $groups = $cmsStore.DatabaseEngineServerGroup.ServerGroups
            }

            if (Test-Bound -ParameterName ExcludeGroup) {
                $groups = $groups | Where-Object Name -notin $ExcludeGroup
            }

            # Close the connection, otherwise using it with the ServersStore will keep it open
            $cmsStore.ServerConnection.Disconnect()
            
            $groups | Select-DefaultView -ExcludeProperty IsLocal, IsSystemServerGroup, IsDropped, Urn, Properties, Metadata, DuplicateFound, PropertyMetadataChanged, PropertyChanged
        }
    }
}
