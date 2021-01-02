function Copy-DbaRegServer {
    <#
    .SYNOPSIS
        Migrates SQL Server Central Management groups and server instances from one SQL Server to another.

    .DESCRIPTION
        Copy-DbaRegServer copies all groups, subgroups, and server instances from one SQL Server to another.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Group
        This is an auto-populated array that contains your Central Management Server top-level groups on Source. You can specify one, many or none.

        If Group is not specified, all groups in your Central Management Server will be copied.

    .PARAMETER SwitchServerName
        If this switch is enabled, all instance names will be changed from Source to Destination.

        Central Management Server does not allow you to add a shared registered server with the same name as the Configuration Server.

    .PARAMETER Force
        If this switch is enabled, group(s) will be dropped and recreated if they already exists on destination.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaRegServer

    .EXAMPLE
        PS C:\> Copy-DbaRegServer -Source sqlserver2014a -Destination sqlcluster

        All groups, subgroups, and server instances are copied from sqlserver2014a CMS to sqlcluster CMS.

    .EXAMPLE
        PS C:\> Copy-DbaRegServer -Source sqlserver2014a -Destination sqlcluster -Group Group1,Group3

        Top-level groups Group1 and Group3 along with their subgroups and server instances are copied from sqlserver to sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaRegServer -Source sqlserver2014a -Destination sqlcluster -Group Group1,Group3 -SwitchServerName -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential

        Top-level groups Group1 and Group3 along with their subgroups and server instances are copied from sqlserver to sqlcluster. When adding sql instances to sqlcluster, if the server name of the migrating instance is "sqlcluster", it will be switched to "sqlserver".

        If SwitchServerName is not specified, "sqlcluster" will be skipped.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Alias('CMSGroup')]
        [string[]]$Group,
        [switch]$SwitchServerName,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        function Invoke-ParseServerGroup {
            [cmdletbinding()]
            param (
                $sourceGroup,
                $destinationGroup,
                $SwitchServerName
            )
            if ($destinationGroup.Name -eq "DatabaseEngineServerGroup" -and $sourceGroup.Name -ne "DatabaseEngineServerGroup") {
                $currentServerGroup = $destinationGroup
                $groupName = $sourceGroup.Name
                $destinationGroup = $destinationGroup.ServerGroups[$groupName]

                $copyDestinationGroupStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $groupName
                    Type              = "CMS Destination Group"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($null -ne $destinationGroup) {

                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if $groupName exists")) {
                            $copyDestinationGroupStatus.Status = "Skipped"
                            $copyDestinationGroupStatus.Notes = "Already exists on destination"
                            $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Destination group $groupName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    }
                    if ($Pscmdlet.ShouldProcess($destinstance, "Dropping group $groupName")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping group $groupName"
                            $destinationGroup.Drop()
                        } catch {
                            $copyDestinationGroupStatus.Status = "Failed"
                            $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping group" -Target $groupName -ErrorRecord $_ -Continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating group $groupName")) {
                    Write-Message -Level Verbose -Message "Creating group $($sourceGroup.Name)"
                    $destinationGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($currentServerGroup, $sourceGroup.Name)
                    $destinationGroup.Create()

                    $copyDestinationGroupStatus.Status = "Successful"
                    $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }

            # Add Servers
            foreach ($instance in $sourceGroup.RegisteredServers) {
                $instanceName = $instance.Name
                $serverName = $instance.ServerName

                $copyInstanceStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $instanceName
                    Type              = "CMS Instance"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($serverName.ToLowerInvariant() -eq $toCmStore.DomainInstanceName.ToLowerInvariant()) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if server is the CMS equals current server name")) {
                        if ($SwitchServerName) {
                            $serverName = $fromCmStore.DomainInstanceName
                            $instanceName = $fromCmStore.DomainInstanceName
                            Write-Message -Level Verbose -Message "SwitchServerName was used and new CMS equals current server name. $($toCmStore.DomainInstanceName.ToLowerInvariant()) changed to $serverName."
                        } else {
                            $copyInstanceStatus.Status = "Skipped"
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "$serverName is Central Management Server. Add prohibited. Skipping."
                            continue
                        }
                    }
                }

                if ($destinationGroup.RegisteredServers.Name -contains $instanceName) {

                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if $instanceName in $groupName exists")) {
                            $copyInstanceStatus.Status = "Skipped"
                            $copyInstanceStatus.Notes = "Already exists on destination"
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Instance $instanceName exists in group $groupName at destination. Use -Force to drop and migrate."
                        }
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Dropping instance $instanceName from $groupName and recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping instance $instance from $groupName"
                            $destinationGroup.RegisteredServers[$instanceName].Drop()
                        } catch {
                            $copyInstanceStatus.Status = "Failed"
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping instance from group" -Target $instanceName -ErrorRecord $_ -Continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Copying $instanceName")) {
                    $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($destinationGroup, $instanceName)
                    $newServer.ServerName = $serverName
                    $newServer.Description = $instance.Description

                    if ($serverName -ne $fromCmStore.DomainInstanceName) {
                        $newServer.SecureConnectionString = $instance.SecureConnectionString
                        $newServer.ConnectionString = $instance.ConnectionString.ToString()
                    }

                    try {
                        $newServer.Create()

                        $copyInstanceStatus.Status = "Successful"
                        $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyInstanceStatus.Status = "Failed"
                        $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        if ($_.Exception -match "same name") {
                            Stop-Function -Message "Could not add Switched Server instance name." -Target $instanceName -ErrorRecord $_ -Continue
                        } else {
                            Stop-Function -Message "Failed to add $serverName" -Target $instanceName -ErrorRecord $_ -Continue
                        }
                    }
                    Write-Message -Level Verbose -Message "Added Server $serverName as $instanceName to $($destinationGroup.Name)"
                }
            }

            # Add Groups
            foreach ($fromSubGroup in $sourceGroup.ServerGroups) {
                $fromSubGroupName = $fromSubGroup.Name
                $toSubGroup = $destinationGroup.ServerGroups[$fromSubGroupName]

                $copyGroupStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $fromSubGroupName
                    Type              = "CMS Group"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($null -ne $toSubGroup) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Checking to see if subgroup $fromSubGroupName exists")) {
                            $copyGroupStatus.Status = "Skipped"
                            $copyGroupStatus.Notes = "Already exists on destination"
                            $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Subgroup $fromSubGroupName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Dropping subgroup $fromSubGroupName recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping subgroup $fromSubGroupName"
                            $toSubGroup.Drop()
                        } catch {
                            $copyGroupStatus.Status = "Failed"
                            $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping subgroup" -Target $toSubGroup -ErrorRecord $_ -Continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating group $($fromSubGroup.Name)")) {
                    Write-Message -Level Verbose -Message "Creating group $($fromSubGroup.Name)"
                    $toSubGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationGroup, $fromSubGroup.Name)
                    $toSubGroup.create()

                    $copyGroupStatus.Status = "Successful"
                    $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }

                Invoke-ParseServerGroup -sourceGroup $fromSubGroup -destinationgroup $toSubGroup -SwitchServerName $SwitchServerName
            }
        }

        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
            $fromCmStore = Get-DbaRegServerStore -SqlInstance $sourceServer
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $toCmStore = Get-DbaRegServerStore -SqlInstance $destServer

            $stores = $fromCmStore.DatabaseEngineServerGroup
            if ($Group) {
                $stores = @();
                foreach ($groupName in $Group) {
                    $stores += $fromCmStore.DatabaseEngineServerGroup.ServerGroups[$groupName]
                }
            }

            foreach ($store in $stores) {
                Invoke-ParseServerGroup -sourceGroup $store -destinationgroup $toCmStore.DatabaseEngineServerGroup -SwitchServerName $SwitchServerName
            }
        }
    }
}