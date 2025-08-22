function Copy-DbaRegServer {
    <#
    .SYNOPSIS
        Copies Central Management Server groups and registered server instances between SQL Server instances.

    .DESCRIPTION
        Migrates registered servers and server groups from a source Central Management Server to a destination CMS, preserving the hierarchical structure of groups and subgroups. This eliminates the need to manually recreate complex server organization structures when setting up new environments or consolidating server management. The function handles conflicts by either skipping existing items or dropping and recreating them when Force is specified.

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

                $copyDestinationGroupStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $groupName
                    Type              = "CMS Destination Group"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
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
                            $copyDestinationGroupStatus.Notes = $_.Exception.Message
                            $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping group $groupName on $destinstance | $PSItem"
                            continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating group $groupName")) {
                    try {
                        Write-Message -Level Verbose -Message "Creating group $($sourceGroup.Name)"
                        $destinationGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($currentServerGroup, $sourceGroup.Name)
                        $destinationGroup.Create()
                        $copyDestinationGroupStatus.Status = "Successful"
                        $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyDestinationGroupStatus.Status = "Failed"
                        $copyDestinationGroupStatus.Notes = $_.Exception.Message
                        $copyDestinationGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating group $groupName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            # Add Servers
            foreach ($instance in $sourceGroup.RegisteredServers) {
                $instanceName = $instance.Name
                $serverName = $instance.ServerName
                $destinstance = $destServer.Name
                $copyInstanceStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $instanceName
                    Type              = "CMS Instance"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($serverName.ToLowerInvariant() -eq $toCmStore.DomainInstanceName.ToLowerInvariant()) {
                    if ($SwitchServerName) {
                        $serverName = $fromCmStore.DomainInstanceName
                        $instanceName = $fromCmStore.DomainInstanceName
                        Write-Message -Level Verbose -Message "SwitchServerName was used and new CMS equals current server name. $($toCmStore.DomainInstanceName.ToLowerInvariant()) changed to $serverName."
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$serverName is Central Management Server. Add prohibited. Skipping.")) {
                            $copyInstanceStatus.Status = "Skipped"
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "$serverName is Central Management Server. Add prohibited. Skipping."
                        }
                        continue
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
                            $copyInstanceStatus.Notes = $_.Exception.Message
                            $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping instance $instanceName from $groupName and recreating on $destinstance | $PSItem"
                            continue
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
                        Write-Message -Level Verbose -Message "Added Server $serverName as $instanceName to $($destinationGroup.Name)"
                    } catch {
                        $copyInstanceStatus.Status = "Failed"
                        $copyInstanceStatus.Notes = $_.Exception.Message
                        $copyInstanceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        if ($_.Exception -match "same name") {
                            Write-Message -Level Verbose -Message "Could not add Switched Server instance name on $instanceName"
                        } else {
                            Write-Message -Level Verbose -Message "Failed to add $serverName on $instanceName"
                            continue
                        }
                    }
                }
            }

            # Add Groups
            foreach ($fromSubGroup in $sourceGroup.ServerGroups) {
                $fromSubGroupName = $fromSubGroup.Name
                if ($Pscmdlet.ShouldProcess($destinstance, "Copying group $fromSubGroupName")) {
                    $toSubGroup = $destinationGroup.ServerGroups[$fromSubGroupName]

                    $copyGroupStatus = [PSCustomObject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = $fromSubGroupName
                        Type              = "CMS Group"
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                }

                if ($null -ne $toSubGroup) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Subgroup $fromSubGroupName exists at destination. Use -Force to drop and migrate.")) {
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
                            $copyGroupStatus.Notes = $_.Exception.Message
                            $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping group $fromSubGroupName on $destinstance | $PSItem"
                            continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating group $($fromSubGroup.Name)")) {
                    try {
                        Write-Message -Level Verbose -Message "Creating group $($fromSubGroup.Name)"
                        $toSubGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationGroup, $fromSubGroup.Name)
                        $toSubGroup.create()
                        $copyGroupStatus.Status = "Successful"
                        $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyGroupStatus.Status = "Failed"
                        $copyGroupStatus.Notes = $_.Exception.Message
                        $copyGroupStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating group $($fromSubGroup.Name) to $destinstance | $PSItem"
                        continue
                    }
                }

                Invoke-ParseServerGroup -sourceGroup $fromSubGroup -destinationgroup $toSubGroup -SwitchServerName $SwitchServerName
            }
        }

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
            $fromCmStore = Get-DbaRegServerStore -SqlInstance $sourceServer
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
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