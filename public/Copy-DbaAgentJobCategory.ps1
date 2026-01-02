function Copy-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Copies custom SQL Agent categories for jobs, alerts, and operators between SQL Server instances.

    .DESCRIPTION
        Migrates custom SQL Agent categories from a source SQL Server to one or more destination servers, so you don't have to manually recreate organizational structures during server migrations or environment setups.
        This function copies only user-defined categories (ID >= 100), preserving built-in system categories on the destination.
        Essential for maintaining consistent job categorization across multiple SQL Server instances in enterprise environments.

        You can copy all categories at once or filter by category type (Job, Alert, Operator) or specify individual category names.
        Categories that already exist on the destination will be skipped unless you use -Force to drop and recreate them.
        The function uses SQL Server Management Objects (SMO) to script category definitions and recreate them on the target server.

    .PARAMETER Source
        The source SQL Server instance from which to copy Agent job categories. Requires sysadmin permissions to access MSDB and read category definitions.
        Use this to specify the server that has the custom categories you want to replicate to other instances.

    .PARAMETER SourceSqlCredential
        Alternative credentials for connecting to the source SQL Server instance. Use this when your current Windows authentication doesn't have sufficient permissions on the source server.
        Accepts credentials created with Get-Credential for SQL authentication or different Windows accounts.

    .PARAMETER Destination
        One or more destination SQL Server instances where the Agent job categories will be created. Accepts an array to copy categories to multiple servers simultaneously.
        Requires sysadmin permissions to create categories in each destination server's MSDB database.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for connecting to the destination SQL Server instances. Use this when different authentication is needed for the destination servers than your current context.
        Accepts credentials created with Get-Credential and applies to all destination servers specified.

    .PARAMETER CategoryType
        Filters the copy operation to specific category types: Job, Alert, or Operator. When specified, copies all categories of the selected type(s) from the source.
        Use this for bulk migration of entire category types rather than individual category names. Leave empty to copy all category types.

    .PARAMETER OperatorCategory
        Specific operator category names to copy from the source server. Use this for selective migration when you only need certain operator categories.
        Supports tab completion from the source server's existing operator categories for convenience.

    .PARAMETER AgentCategory
        Specific alert category names to copy from the source server. Use this for selective migration when you only need certain alert categories.
        Note: This parameter is currently not implemented in the function code and will be ignored if used.

    .PARAMETER JobCategory
        Specific job category names to copy from the source server. Use this for selective migration when you only need certain job categories.
        Supports tab completion from the source server's existing job categories for convenience.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Drops and recreates existing categories on the destination servers instead of skipping them. Use this when you need to overwrite categories that have changed on the source.
        Without this switch, categories that already exist on the destination will be skipped to prevent data loss.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per category processed (whether skipped, successfully copied, or failed). When multiple categories or multiple destination servers are specified, returns multiple objects.

        Default display properties (via Select-DefaultView with TypeName MigrationObject):
        - DateTime: The date and time when the category copy was attempted (DbaDateTime object)
        - SourceServer: The name of the source SQL Server instance
        - DestinationServer: The name of the destination SQL Server instance
        - Name: The name of the category being copied
        - Type: The type of category ("Agent Job Category", "Agent Operator Category", or "Agent Alert Category")
        - Status: The outcome of the copy operation (Successful, Failed, or Skipped)
        - Notes: Additional context about the operation result (e.g., "Already exists on destination")

        All properties are accessible using Select-Object * even though only the above default properties are displayed.

    .NOTES
        Tags: Migration, Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentJobCategory

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobCategory -Source sqlserver2014a -Destination sqlcluster

        Copies all operator categories from sqlserver2014a to sqlcluster using Windows authentication. If operator categories with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobCategory -Source sqlserver2014a -Destination sqlcluster -OperatorCategory PSOperator -SourceSqlCredential $cred -Force

        Copies a single operator category, the PSOperator operator category from sqlserver2014a to sqlcluster using SQL credentials to authenticate to sqlserver2014a and Windows credentials for sqlcluster. If an operator category with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobCategory -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Parameter(ParameterSetName = 'SpecificAlerts')]
        [ValidateSet('Job', 'Alert', 'Operator')]
        [string[]]$CategoryType,
        [string[]]$JobCategory,
        [string[]]$AgentCategory,
        [string[]]$OperatorCategory,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        function Copy-JobCategory {
            <#
                .SYNOPSIS
                    Copy-JobCategory migrates job categories from one SQL Server to another.

                .DESCRIPTION
                    By default, all job categories are copied. The -JobCategories parameter is auto-populated for command-line completion and can be used to copy only specific job categories.

                    If the associated credential for the category does not exist on the destination, it will be skipped. If the job category already exists on the destination, it will be skipped unless -Force is used.
            #>
            param (
                [string[]]$jobCategories
            )

            process {

                $serverJobCategories = $sourceServer.JobServer.JobCategories | Where-Object ID -ge 100
                $destJobCategories = $destServer.JobServer.JobCategories | Where-Object ID -ge 100

                foreach ($jobCategory in $serverJobCategories) {
                    $categoryName = $jobCategory.Name

                    $copyJobCategoryStatus = [PSCustomObject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = $categoryName
                        Type              = "Agent Job Category"
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($jobCategories.Count -gt 0 -and $jobCategories -notcontains $categoryName) {
                        continue
                    }

                    if ($destJobCategories.Name -contains $jobCategory.name) {
                        if ($force -eq $false) {
                            If ($pscmdlet.ShouldProcess($destinstance, "Job category $categoryName exists at destination. Use -Force to drop and migrate.")) {
                                $copyJobCategoryStatus.Status = "Skipped"
                                $copyJobCategoryStatus.Notes = "Already exists on destination"
                                $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Job category $categoryName exists at destination. Use -Force to drop and migrate."
                            }
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping job category $categoryName")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping Job category $categoryName"
                                    $destServer.JobServer.JobCategories[$categoryName].Drop()
                                } catch {
                                    $copyJobCategoryStatus.Status = "Failed"
                                    $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Issue dropping job category $categoryName on $destinstance | $PSItem"
                                    continue
                                }
                            }
                        }
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Creating Job category $categoryName")) {
                        try {
                            Write-Message -Level Verbose -Message "Copying Job category $categoryName"
                            $sql = $jobCategory.Script() | Out-String
                            Write-Message -Level Debug -Message "SQL Statement: $sql"
                            $destServer.Query($sql)
                            $copyJobCategoryStatus.Status = "Successful"
                            $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } catch {
                            $copyJobCategoryStatus.Status = "Failed"
                            $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue copying job category $categoryName on $destinstance | $PSItem"
                            continue
                        }
                    }
                }
            }
        }

        function Copy-OperatorCategory {
            <#
                .SYNOPSIS
                    Copy-OperatorCategory migrates operator categories from one SQL Server to another.

                .DESCRIPTION
                    By default, all operator categories are copied. The -OperatorCategories parameter is auto-populated for command-line completion and can be used to copy only specific operator categories.

                    If the associated credential for the category does not exist on the destination, it will be skipped. If the operator category already exists on the destination, it will be skipped unless -Force is used.
            #>
            [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
            param (
                [string[]]$operatorCategories
            )
            process {
                $serverOperatorCategories = $sourceServer.JobServer.OperatorCategories | Where-Object ID -ge 100
                $destOperatorCategories = $destServer.JobServer.OperatorCategories | Where-Object ID -ge 100

                foreach ($operatorCategory in $serverOperatorCategories) {
                    $categoryName = $operatorCategory.Name

                    $copyOperatorCategoryStatus = [PSCustomObject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Type              = "Agent Operator Category"
                        Name              = $categoryName
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($operatorCategories.Count -gt 0 -and $operatorCategories -notcontains $categoryName) {
                        continue
                    }

                    if ($destOperatorCategories.Name -contains $operatorCategory.Name) {
                        if ($force -eq $false) {
                            If ($pscmdlet.ShouldProcess($destinstance, "Operator category $categoryName exists at destination. Use -Force to drop and migrate.")) {
                                $copyOperatorCategoryStatus.Status = "Skipped"
                                $copyOperatorCategoryStatus.Notes = "Already exists on destination"
                                $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Operator category $categoryName exists at destination. Use -Force to drop and migrate."
                            }
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping operator category $categoryName and recreating")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping Operator category $categoryName"
                                    $destServer.JobServer.OperatorCategories[$categoryName].Drop()
                                    Write-Message -Level Verbose -Message "Copying Operator category $categoryName"
                                    $sql = $operatorCategory.Script() | Out-String
                                    Write-Message -Level Debug -Message $sql
                                    $destServer.Query($sql)
                                } catch {
                                    $copyOperatorCategoryStatus.Status = "Failed"
                                    $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Issue dropping operator category $categoryName on $destinstance | $PSItem"
                                    continue
                                }
                            }
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Creating Operator category $categoryName")) {
                            try {
                                Write-Message -Level Verbose -Message "Copying Operator category $categoryName"
                                $sql = $operatorCategory.Script() | Out-String
                                Write-Message -Level Debug -Message $sql
                                $destServer.Query($sql)

                                $copyOperatorCategoryStatus.Status = "Successful"
                                $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } catch {
                                $copyOperatorCategoryStatus.Status = "Failed"
                                $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue copying operator category $categoryName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }
            }
        }

        function Copy-AlertCategory {
            <#
                .SYNOPSIS
                    Copy-AlertCategory migrates alert categories from one SQL Server to another.

                .DESCRIPTION
                    By default, all alert categories are copied. The -AlertCategories parameter is auto-populated for command-line completion and can be used to copy only specific alert categories.

                    If the associated credential for the category does not exist on the destination, it will be skipped. If the alert category already exists on the destination, it will be skipped unless -Force is used.
            #>
            [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
            param (
                [string[]]$AlertCategories
            )

            process {
                if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
                    throw "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting."
                }

                $serverAlertCategories = $sourceServer.JobServer.AlertCategories | Where-Object ID -ge 100
                $destAlertCategories = $destServer.JobServer.AlertCategories | Where-Object ID -ge 100

                foreach ($alertCategory in $serverAlertCategories) {
                    $categoryName = $alertCategory.Name

                    $copyAlertCategoryStatus = [PSCustomObject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Type              = "Agent Alert Category"
                        Name              = $categoryName
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($alertCategories.Length -gt 0 -and $alertCategories -notcontains $categoryName) {
                        continue
                    }

                    if ($destAlertCategories.Name -contains $alertCategory.name) {
                        if ($force -eq $false) {
                            If ($pscmdlet.ShouldProcess($destinstance, "Alert category $categoryName exists at destination. Use -Force to drop and migrate.")) {
                                $copyAlertCategoryStatus.Status = "Skipped"
                                $copyAlertCategoryStatus.Notes = "Already exists on destination"
                                $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Alert category $categoryName exists at destination. Use -Force to drop and migrate."
                            }
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping alert category $categoryName and recreating")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping Alert category $categoryName"
                                    $destServer.JobServer.AlertCategories[$categoryName].Drop()
                                    Write-Message -Level Verbose -Message "Copying Alert category $categoryName"
                                    $sql = $alertcategory.Script() | Out-String
                                    Write-Message -Level Debug -Message "SQL Statement: $sql"
                                    $destServer.Query($sql)
                                } catch {
                                    $copyAlertCategoryStatus.Status = "Failed"
                                    $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Issue dropping alert category $categoryName on $destinstance | $PSItem"
                                    continue
                                }
                            }
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Creating Alert category $categoryName")) {
                            try {
                                Write-Message -Level Verbose -Message "Copying Alert category $categoryName"
                                $sql = $alertCategory.Script() | Out-String
                                Write-Message -Level Debug -Message $sql
                                $destServer.Query($sql)

                                $copyAlertCategoryStatus.Status = "Successful"
                                $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } catch {
                                $copyAlertCategoryStatus.Status = "Failed"
                                $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue creating alert category $categoryName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }
            }
        }

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            if ($CategoryType.count -gt 0) {

                switch ($CategoryType) {
                    "Job" {
                        Copy-JobCategory
                    }

                    "Alert" {
                        Copy-AlertCategory
                    }

                    "Operator" {
                        Copy-OperatorCategory
                    }
                }
                continue
            }

            if (($OperatorCategory.Count + $AlertCategory.Count + $jobCategory.Count) -gt 0) {

                if ($OperatorCategory.Count -gt 0) {
                    Copy-OperatorCategory -OperatorCategories $OperatorCategory
                }

                if ($AlertCategory.Count -gt 0) {
                    Copy-AlertCategory -AlertCategories $AlertCategory
                }

                if ($jobCategory.Count -gt 0) {
                    Copy-JobCategory -JobCategories $jobCategory
                }
                continue
            }
            Copy-OperatorCategory
            Copy-AlertCategory
            Copy-JobCategory
        }
    }
}