function Copy-DbaResourceGovernor {
    <#
    .SYNOPSIS
        Copies SQL Server Resource Governor configuration including pools, workload groups, and classifier functions between instances

    .DESCRIPTION
        Migrates your entire SQL Server Resource Governor setup from one instance to another, including custom resource pools, workload groups, and classifier functions. This saves you from manually recreating complex Resource Governor configurations when setting up new servers or during migrations.

        The function copies all non-system resource pools (excludes the built-in "internal" and "default" pools) along with their associated workload groups and settings. It also migrates any custom classifier function you've configured to automatically assign incoming requests to appropriate resource pools.

        If a resource pool already exists on the destination server, it will be skipped unless you use -Force to overwrite it. Resource Governor will be properly reconfigured after the migration to ensure all changes take effect.

        Note that Resource Governor is only available in Enterprise, Datacenter, and Developer editions of SQL Server. The -ResourcePool parameter is auto-populated for command-line completion and can be used to copy only specific objects.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2008 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaResourceGovernor

    .EXAMPLE
        PS C:\> Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster

        Copies all all non-system resource pools from sqlserver2014a to sqlcluster using Windows credentials to connect to the SQL Server instances..

    .EXAMPLE
        PS C:\> Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all all non-system resource pools from sqlserver2014a to sqlcluster using SQL credentials to connect to sqlserver2014a and Windows credentials to connect to sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaResourceGovernor -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$ResourcePool,
        [object[]]$ExcludeResourcePool,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $sourceClassifierFunction = Get-DbaRgClassifierFunction -SqlInstance $sourceServer

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destClassifierFunction = Get-DbaRgClassifierFunction -SqlInstance $destServer

            $copyResourceGovSetting = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Resource Governor Settings"
                Name              = "All Settings"
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            $copyResourceGovClassifierFunc = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Resource Governor Settings"
                Name              = "Classifier Function"
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($Pscmdlet.ShouldProcess($destinstance, "Updating Resource Governor settings")) {
                if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
                    Write-Message -Level Verbose -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
                } else {
                    try {
                        Write-Message -Level Verbose -Message "Managing classifier function."
                        # ALL IN ONE, NO CONTINUES
                        if (!$sourceClassifierFunction) {
                            $copyResourceGovClassifierFunc.Status = "Skipped"
                            $copyResourceGovClassifierFunc.Notes = $null
                            $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } else {
                            $fullyQualifiedFunctionName = $sourceClassifierFunction.Schema + "." + $sourceClassifierFunction.Name

                            if (!$destClassifierFunction) {
                                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                                $destFunction = $destServer.Databases["master"].UserDefinedFunctions[$sourceClassifierFunction.Name]
                                if ($destFunction) {
                                    Write-Message -Level Verbose -Message "Dropping the function with the source classifier function name."
                                    $destFunction.Drop()
                                }

                                Write-Message -Level Verbose -Message "Creating function."
                                $script = $sourceClassifierFunction.Script() | Where-Object { $_ -notmatch '^SET QUOTED_IDENTIFIER' -and $_ -notmatch '^SET ANSI_NULLS' }
                                $destServer.Query($script)

                                $sql = "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = $fullyQualifiedFunctionName);"
                                Write-Message -Level Debug -Message $sql
                                Write-Message -Level Verbose -Message "Mapping Resource Governor classifier function."
                                $destServer.Query($sql)

                                $copyResourceGovClassifierFunc.Status = "Successful"
                                $copyResourceGovClassifierFunc.Notes = "The new classifier function has been created"
                                $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                Write-Message -Level Debug -Message $sql
                                Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                $destServer.Query($sql)
                            } else {
                                if ($Force -eq $false) {
                                    $copyResourceGovClassifierFunc.Status = "Skipped"
                                    $copyResourceGovClassifierFunc.Notes = "Already exists on destination"
                                    $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                } else {

                                    $sql = "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL);"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Disabling the Resource Governor."
                                    $destServer.Query($sql)

                                    $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                    $destServer.Query($sql)

                                    Write-Message -Level Verbose -Message "Dropping the destination classifier function."
                                    $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                                    $destFunction = $destServer.Databases["master"].UserDefinedFunctions[$sourceClassifierFunction.Name]
                                    $destClassifierFunction.Drop()

                                    Write-Message -Level Verbose -Message "Re-creating the Resource Governor classifier function."
                                    $script = $sourceClassifierFunction.Script() | Where-Object { $_ -notmatch '^SET QUOTED_IDENTIFIER' -and $_ -notmatch '^SET ANSI_NULLS' }
                                    $destServer.Query($script)

                                    $sql = "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = $fullyQualifiedFunctionName);"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Mapping Resource Governor classifier function."
                                    $destServer.Query($sql)

                                    $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                    Write-Message -Level Debug -Message $sql
                                    Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                    $destServer.Query($sql)

                                    $copyResourceGovClassifierFunc.Status = "Successful"
                                    $copyResourceGovClassifierFunc.Notes = "The old classifier function has been overwritten."
                                    $copyResourceGovClassifierFunc | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                            }
                        }
                    } catch {
                        $copyResourceGovSetting.Status = "Failed"
                        $copyResourceGovSetting.Notes = (Get-ErrorMessage -Record $_)
                        $copyResourceGovSetting | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                        $destServer.Query($sql)
                        Write-Message -Level Verbose -Message "Issue reconfiguring Resource Governor on $destinstance | $PSItem"
                    }
                }
            }

            # Pools
            if ($ResourcePool) {
                $pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -In $ResourcePool
            } elseif ($ExcludeResourcePool) {
                $pool = $sourceServer.ResourceGovernor.ResourcePools | Where-Object Name -NotIn $ExcludeResourcePool
            } else {
                $pools = $sourceServer.ResourceGovernor.ResourcePools | Where-Object { $_.Name -notin "internal", "default" }
            }

            Write-Message -Level Verbose -Message "Migrating pools."
            foreach ($pool in $pools) {
                $poolName = $pool.Name

                $copyResourceGovPool = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Resource Governor Pool"
                    Name              = $poolName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destServer.ResourceGovernor.ResourcePools[$poolName]) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Pool '$poolName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate.")) {
                            Write-Message -Level Verbose -Message "Pool '$poolName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate."
                            $copyResourceGovPool.Status = "Skipped"
                            $copyResourceGovPool.Notes = "Already exists on destination"
                            $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to drop $poolName")) {
                            Write-Message -Level Verbose -Message "Pool '$poolName' exists on $destinstance."
                            Write-Message -Level Verbose -Message "Force specified. Dropping $poolName."

                            try {
                                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                                $destPool = $destServer.ResourceGovernor.ResourcePools[$poolName]
                                $workloadGroups = $destPool.WorkloadGroups
                                foreach ($workloadGroup in $workloadGroups) {
                                    $workloadGroup.Drop()
                                }
                                $destPool.Drop()
                                $destServer.ResourceGovernor.Alter()
                            } catch {
                                $copyResourceGovPool.Status = "Failed"
                                $copyResourceGovPool.Notes = (Get-ErrorMessage -Record $_)
                                $copyResourceGovPool | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Write-Message -Level Verbose -Message "Issue dropping pool $poolName on $destinstance | $PSItem"

                                $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                                Write-Message -Level Debug -Message $sql
                                Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                                $destServer.Query($sql)
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Migrating pool $poolName")) {
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

                            $copyResourceGovWorkGroup = [PSCustomObject]@{
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

                            $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                            Write-Message -Level Debug -Message $sql
                            Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                            $destServer.Query($sql)
                        }
                    } catch {
                        if ($copyResourceGovWorkGroup) {
                            $copyResourceGovWorkGroup.Status = "Failed"
                            $copyResourceGovWorkGroup.Notes = (Get-ErrorMessage -Record $_)
                            $copyResourceGovWorkGroup | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        Write-Message -Level Verbose -Message "Issue creating $workgroupName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destinstance, "Finalizing migration by reconfiguring Resource Governor.")) {
                if ($destServer.Edition -notmatch 'Enterprise' -and $destServer.Edition -notmatch 'Datacenter' -and $destServer.Edition -notmatch 'Developer') {
                    Write-Message -Level Verbose -Message "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
                } else {

                    Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                    try {
                        if (!$sourceServer.ResourceGovernor.Enabled) {
                            $sql = "ALTER RESOURCE GOVERNOR DISABLE"
                            $destServer.Query($sql)

                            $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"
                            Write-Message -Level Debug -Message $sql
                            Write-Message -Level Verbose -Message "Reconfiguring Resource Governor."
                            $destServer.Query($sql)
                        } else {
                            $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE"
                            $destServer.Query($sql)
                        }
                    } catch {
                        $altermsg = $_.Exception
                    }


                    $copyResourceGovReconfig = [PSCustomObject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Type              = "Reconfigure Resource Governor"
                        Name              = "Reconfigure Resource Governor"
                        Status            = "Successful"
                        Notes             = $altermsg
                        DateTime          = [DbaDateTime](Get-Date)
                    }
                    $copyResourceGovReconfig | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
    }
}