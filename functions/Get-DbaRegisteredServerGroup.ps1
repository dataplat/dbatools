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

        .PARAMETER Id
            Get group by Id(s)

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
            Get-DbaRegisteredServerGroup -SqlInstance sqlserver2014a -SqlCredential $credential

            Gets the top level groups from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

        .EXAMPLE
            Get-DbaRegisteredServerGroup -SqlInstance sqlserver2014a -Group HR, Accounting

            Gets the HR and Accounting groups from the CMS on sqlserver2014a.

        .EXAMPLE
            Get-DbaRegisteredServerGroup -SqlInstance sqlserver2014a -Group HR\Development

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
        [int[]]$Id,
        [switch]$EnableException
    )
    begin {
        function Get-ReverseParse ($object) {
            $name = @()
            do {
                $name += $object.Name
                $object = $object.Parent
            }
            until ($object.Name -eq 'DatabaseEngineServerGroup')
            
            [array]::Reverse($name)
            $name -join '\'
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Get-DbaRegisteredServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            }
            catch {
                Stop-Function -Message "Cannot access Central Management Server '$instance'" -ErrorRecord $_ -Continue
            }
            $groups = @()
            if ($group) {
                foreach ($currentgroup in $Group) {
                    if ($currentgroup -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        $currentgroup = Get-ReverseParse -object $currentgroup
                    }
                    
                    if ($currentgroup -match '\\') {
                        $split = $currentgroup.Split('\\')
                        $i = 0
                        $groupobject = $server.DatabaseEngineServerGroup
                        do {
                            if ($groupobject) {
                                $groupobject = $groupobject.ServerGroups[$split[$i]]
                            }
                        }
                        until ($i++ -eq $split.GetUpperBound(0))
                        if ($groupobject) {
                            $groups += $groupobject
                        }
                    }
                    else {
                        $thisgroup = $server.DatabaseEngineServerGroup.ServerGroups[$currentgroup]
                        if ($thisgroup) {
                            $groups += $server.DatabaseEngineServerGroup.ServerGroups[$currentgroup]
                        }
                    }
                }
            }
            else {
                $groups = $server.DatabaseEngineServerGroup.ServerGroups
            }
            
            if ($Group -eq 'DatabaseEngineServerGroup') {
                $groups = $server.DatabaseEngineServerGroup
            }
            
            if (Test-Bound -ParameterName ExcludeGroup) {
                $groups = $groups | Where-Object Name -notin $ExcludeGroup
            }
            
            if (Test-Bound -ParameterName Id) {
                $groups = $server.DatabaseEngineServerGroup | Where-Object Id -in $Id
            }
            
            # Close the connection, otherwise using it with the ServersStore will keep it open
            # $server.ServerConnection.Disconnect()
            
            foreach ($groupobject in $groups) {
                Add-Member -Force -InputObject $groupobject -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $groupobject -MemberType NoteProperty -Name InstanceName -value $server.InstanceName
                Add-Member -Force -InputObject $groupobject -MemberType NoteProperty -Name SqlInstance -value $server.SqlInstance
                Select-DefaultView -InputObject $groupobject -ExcludeProperty Parent, IdentityKey, ServerType, IsLocal, IsSystemServerGroup, IsDropped, Urn, Properties, Metadata, DuplicateFound, PropertyMetadataChanged, PropertyChanged
            }
        }
    }
}