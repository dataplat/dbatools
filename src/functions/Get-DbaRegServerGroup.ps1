function Get-DbaRegServerGroup {
    <#
    .SYNOPSIS
        Gets list of Server Groups objects stored in SQL Server Central Management Server (CMS).

    .DESCRIPTION
        Returns an array of Server Groups found in the CMS.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Group
        Specifies one or more groups to include from SQL Server Central Management Server.

    .PARAMETER ExcludeGroup
        Specifies one or more Central Management Server groups to exclude.

    .PARAMETER Id
        Get group by Id(s). This parameter only works if the group has a registered server in it.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Tony Wilhelm (@tonywsql)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRegServerGroup

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sqlserver2014a

        Gets the top level groups from the CMS on sqlserver2014a, using Windows Credentials.

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sqlserver2014a -SqlCredential $credential

        Gets the top level groups from the CMS on sqlserver2014a, using alternative credentials to authenticate to the server.

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sqlserver2014a -Group HR, Accounting

        Gets the HR and Accounting groups from the CMS on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sqlserver2014a -Group HR\Development

        Returns the sub-group Development of the HR group from the CMS on sqlserver2014a.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Group,
        [object[]]$ExcludeGroup,
        [int[]]$Id,
        [switch]$EnableException
    )
    begin {
        $serverstores = $groups = @()
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $serverstores += Get-DbaRegServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Cannot access Central Management Server '$instance'" -ErrorRecord $_ -Continue
            }
        }

        if (-not $SqlInstance) {
            $serverstores += Get-DbaRegServerStore
        }

        foreach ($serverstore in $serverstores) {
            if ($Group) {
                foreach ($currentgroup in $Group) {
                    Write-Message -Level Verbose -Message "Processing $currentgroup"
                    if ($currentgroup -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        $currentgroup = Get-RegServerGroupReverseParse -object $currentgroup
                    }

                    if ($currentgroup -match 'DatabaseEngineServerGroup\\') {
                        $currentgroup = $currentgroup.Replace('DatabaseEngineServerGroup\', '')
                    }

                    if ($currentgroup -match '\\') {
                        $split = $currentgroup.Split('\\')
                        $i = 0
                        $groupobject = $serverstore.DatabaseEngineServerGroup
                        do {
                            if ($groupobject) {
                                $groupobject = $groupobject.ServerGroups[$split[$i]]
                                Write-Message -Level Verbose -Message "Parsed $($groupobject.Name)"
                            }
                        }
                        until ($i++ -eq $split.GetUpperBound(0))
                        if ($groupobject) {
                            $groups += $groupobject
                        }
                    } else {
                        try {
                            $thisgroup = $serverstore.DatabaseEngineServerGroup.ServerGroups[$currentgroup]
                            if ($thisgroup) {
                                Write-Message -Level Verbose -Message "Added $($thisgroup.Name)"
                                $groups += $thisgroup
                            }
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Added all root server groups"
                $groups = $serverstore.DatabaseEngineServerGroup.ServerGroups
            }

            if ($Group -eq 'DatabaseEngineServerGroup') {
                Write-Message -Level Verbose -Message "Added root group"
                $groups = $serverstore.DatabaseEngineServerGroup
            }

            if ($ExcludeGroup) {
                $excluded = Get-DbaRegServerGroup -SqlInstance $serverstore.ParentServer -SqlCredential $SqlCredential -Group $ExcludeGroup
                Write-Message -Level Verbose -Message "Excluding $ExcludeGroup"
                $groups = $groups | Where-Object { $_.Urn.Value -notin $excluded.Urn.Value }
            }

            if ($Id) {
                Write-Message -Level Verbose -Message "Filtering for id $Id. Id 1 = default."
                if ($Id -eq 1) {
                    $groups = $serverstore.DatabaseEngineServerGroup
                } else {
                    $groups = $serverstore.DatabaseEngineServerGroup.GetDescendantRegisteredServers().Parent | Where-Object Id -In $Id
                }
            }
            if ($serverstore.ServerConnection) {
                $serverstore.ServerConnection.Disconnect()
            }

            foreach ($groupobject in $groups) {
                Add-Member -Force -InputObject $groupobject -MemberType NoteProperty -Name ComputerName -Value $serverstore.ComputerName
                Add-Member -Force -InputObject $groupobject -MemberType NoteProperty -Name InstanceName -Value $serverstore.InstanceName
                Add-Member -Force -InputObject $groupobject -MemberType NoteProperty -Name SqlInstance -Value $serverstore.SqlInstance
                Add-Member -Force -InputObject $groupobject -MemberType NoteProperty -Name ParentServer -Value $serverstore.ParentServer

                if ($groupobject.ComputerName) {
                    Select-DefaultView -InputObject $groupobject -Property ComputerName, InstanceName, SqlInstance, Name, DisplayName, Description, ServerGroups, RegisteredServers
                } else {
                    Select-DefaultView -InputObject $groupobject -Property Name, DisplayName, Description, ServerGroups, RegisteredServers
                }
            }
        }
    }
}