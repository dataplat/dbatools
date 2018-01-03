function Copy-DbaResourceGovernor {
    <#
        .SYNOPSIS
            Migrates Resource Pools

        .DESCRIPTION
            By default, all non-system resource pools are migrated. If the pool already exists on the destination, it will be skipped unless -Force is used.

            The -ResourcePool parameter is auto-populated for command-line completion and can be used to copy only specific objects.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2008 or higher.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER ResourcePool
            Specifies the resource pool(s) to process. Options for this list are auto-populated from the server. If unspecified, all resource pools will be processed.

        .PARAMETER ExcludeResourcePool
            Specifies the resource pool(s) to exclude. Options for this list are auto-populated from the server

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER Force
            If this switch is enabled, the policies will be dropped and recreated on Destination.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Migration, ResourceGovernor
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaResourceGovernor

        .EXAMPLE
            Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster

            Copies all extended event policies from sqlserver2014a to sqlcluster using Windows credentials to connect to the SQL Server instances..

        .EXAMPLE
            Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

            Copies all extended event policies from sqlserver2014a to sqlcluster using SQL credentials to connect to sqlserver2014a and Windows credentials to connect to sqlcluster.

        .EXAMPLE
            Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -WhatIf

            Shows what would happen if the command were executed.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$ResourcePool,
        [object[]]$ExcludeResourcePool,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
            Stop-Function -Message "Resource Governor is only supported in SQL Server 2008 and above. Quitting."
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        $copyResourceGovSetting = [pscustomobject]@{
            SourceServer      = $sourceServer.Name
            DestinationServer = $destServer.Name
            Type              = "Resource Governor Settings"
            Name              = "All Settings"
            Status            = $null
            Notes             = $null
            DateTime          = [DbaDateTime](Get-Date)
        }

        if ($Pscmdlet.ShouldProcess($destination, "Updating Resource Governor settings")) {
            if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
                Write-Message -Level Verbose -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
            }
            else {
                try {
                    $sql = $sourceServer.ResourceGovernor.Script() | Out-String
                    Write-Message -Level Debug -Message $sql
                    Write-Message -Level Verbose -Message "Updating Resource Governor settings."
                    $destServer.Query($sql)

                    $copyResourceGovSetting.Status = "Successful"
                    $copyResourceGovSetting | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                catch {
                    $copyResourceGovSetting.Status = "Failed"
                    $copyResourceGovSetting.Notes = $_.Exception
                    $copyResourceGovSetting | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Not able to update settings." -Target $destServer -ErrorRecord $_
                }
            }
        }

        # Pools
        if ($ResourcePool) {
            $pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -In $ResourcePool
        }
        elseif ($ExcludeResourcePool) {
            $pool = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -NotIn $ExcludeResourcePool
        }
        else {
            $pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object { $_.Name -notin "internal", "default" }
        }

        Write-Message -Level Verbose -Message "Migrating pools."
        foreach ($pool in $pools) {
            $poolName = $pool.Name

            $copyResourceGovPool = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Resource Governor Pool"
                Name              = $poolName
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($destServer.ResourceGovernor.ResourcePools[$poolName] -ne $null) {
                if ($force -eq $false) {
                    Write-Message -Level Verbose -Message "Pool '$poolName' was skipped because it already exists on $destination. Use -Force to drop and recreate."

                    $copyResourceGovPool.Status = "Skipped"
                    $copyResourceGovPool.Notes = "Already exists"
                    $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    continue
                }
                else {
                    if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $poolName")) {
                        Write-Message -Level Verbose -Message "Pool '$poolName' exists on $destination."
                        Write-Message -Level Verbose -Message "Force specified. Dropping $poolName."

                        try {
                            $destPool = $destServer.ResourceGovernor.ResourcePools[$poolName]
                            $workloadGroups = $destPool.WorkloadGroups
                            foreach ($workloadGroup in $workloadGroups) {
                                $workloadGroup.Drop()
                            }
                            $destPool.Drop()
                            $destServer.ResourceGovernor.Alter()
                        }
                        catch {
                            $copyResourceGovPool.Status = "Failed to drop from Destination"
                            $copyResourceGovPool.Notes = $_.Exception
                            $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Unable to drop: $_  Moving on." -Target $destPool -ErrorRecord $_ -Continue
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Migrating pool $poolName")) {
                try {
                    $sql = $pool.Script() | Out-String
                    Write-Message -Level Debug -Message $sql
                    Write-Message -Level Verbose -Message "Copying pool $poolName."
                    $destServer.Query($sql)

                    $copyResourceGovPool.Status = "Successful"
                    $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    $workloadGroups = $pool.WorkloadGroups
                    foreach ($workloadGroup in $workloadGroups) {
                        $workgroupName = $workloadGroup.Name

                        $copyResourceGovWorkGroup = [pscustomobject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Type              = "Resource Governor Pool Workgroup"
                            Name              = $workgroupName
                            Status            = $null
                            Notes             = $null
                            DateTime          = [DbaDateTime](Get-Date)
                        }

                        $sql = $workloadGroup.Script() | Out-String
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Copying $workgroupName."
                        $destServer.Query($sql)

                        $copyResourceGovWorkGroup.Status = "Successful"
                        $copyResourceGovWorkGroup | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                }
                catch {
                    $copyResourceGovWorkGroup.Status = "Failed"
                    $copyResourceGovWorkGroup.Notes = $_.Exception
                    $copyResourceGovWorkGroup | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Unable to migrate pool." -Target $pool -ErrorRecord $_
                }
            }
        }

        if ($Pscmdlet.ShouldProcess($destination, "Reconfiguring")) {
            if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
                Write-Message -Level Verbose -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
            }
            else {
                Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE"
                $destServer.Query($sql)

                $copyResourceGovReconfig = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Reconfigure Resource Governor"
                    Name              = "Reconfigure Resource Governor"
                    Status            = "Successful"
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }
                $copyResourceGovReconfig | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlResourceGovernor
    }
}