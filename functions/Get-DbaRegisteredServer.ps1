#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaRegisteredServer {
    <#
        .SYNOPSIS
            Gets list of SQL Server objects stored in SQL Server Central Management Server (CMS).

        .DESCRIPTION
            Returns an array of servers found in the CMS.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Group
            Specifies one or more groups to include from SQL Server Central Management Server.

        .PARAMETER ExcludeGroup
            Specifies one or more Central Management Server groups to exclude.

        .PARAMETER ExcludeCmsServer
            Deprecated, now follows the Microsoft convention of not including it by default. If you'd like to include the CMS Server, use -IncludeSelf

        .PARAMETER IncludeSelf
            If this switch is enabled, the CMS server itself will be included in the results, along with all other Registered Servers.

        .PARAMETER ResolveNetworkName
            If this switch is enabled, the NetBIOS name and IP address(es) of each server will be returned.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Bryan Hamby (@galador)
            Tags: RegisteredServer, CMS

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaRegisteredServer

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a

            Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a -IncludeSelf

            Gets a list of servers from the CMS on sqlserver2014a and includes sqlserver2014a in the output results.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName

            Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

            Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

            Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Groups")]
        [object[]]$Group,
        [object[]]$ExcludeGroup,
        [switch]$IncludeSelf,
        [switch]$ExcludeCmsServer,
        [switch]$ResolveNetworkName,
        [Alias('Silent')]
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

        $defaults = @()
        if ($ResolveNetworkName) {
            $defaults += 'ComputerName', 'FQDN', 'IPAddress'
        }
        $defaults += 'Name', 'ServerName', 'Description', 'ServerType', 'SecureConnectionString'

    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        $servers = @()
        foreach ($instance in $SqlInstance) {
            try {
                $cmsStore = Get-DbaRegisteredServersStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            }
            catch {
                Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue
            }

            if (Test-Bound -ParameterName ExcludeGroup) {
                $Group = ($cmsStore.DatabaseEngineServerGroup.ServerGroups | Where-Object Name -notin $ExcludeGroup).Name
            }

            if ($Group) {
                foreach ($currentGroup in $Group) {
                    $cms = Find-CmsGroup -CmsGrp $cmsStore.DatabaseEngineServerGroup.ServerGroups -Stopat $currentGroup
                    if ($null -eq $cms) {
                        Write-Message -Level Output -Message "No groups found matching that name on instance '$instance'."
                        continue
                    }
                    $servers += ($cms.GetDescendantRegisteredServers())
                }
            }
            else {
                $cms = $cmsStore.DatabaseEngineServerGroup
                $servers += ($cms.GetDescendantRegisteredServers())
            }
            if ($Group -and (Test-Bound -ParameterName Group -Not)) {
                #add root ones
                $servers += ($cmsstore.DatabaseEngineServerGroup.RegisteredServers)
            }

            # Close the connection, otherwise using it with the ServersStore will keep it open
            $cmsStore.ServerConnection.Disconnect()
        }

        foreach ($server in $servers) {
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $null
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $null
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null

            if ($ResolveNetworkName) {
                try {
                    $lookup = Resolve-DbaNetworkName $server.ServerName -Turbo
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $lookup.ComputerName
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $lookup.FQDN
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $lookup.IPAddress
                }
                catch {
                    try {
                        $lookup = Resolve-DbaNetworkName $server.ServerName
                        Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $lookup.ComputerName
                        Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $lookup.FQDN
                        Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $lookup.IPAddress
                    }
                    catch {}
                }
            }

            Add-Member -Force -InputObject $server -MemberType ScriptMethod -Name ToString -Value { $this.ServerName }
            Select-DefaultView -InputObject $server -Property $defaults
        }

        if ($IncludeSelf -and $servers) {
            $self = $servers[0].PsObject.Copy()
            $self | Add-Member -MemberType NoteProperty -Name Name -Value "CMS Instance" -Force
            $self.ServerName = $instance
            $self.Description = $null
            $self.SecureConnectionString = $null
            Select-DefaultView -InputObject $self -Property $defaults
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Parameter ExcludeCmsServer
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-DbaRegisteredServerName
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-SqlRegisteredServerName
    }
}
