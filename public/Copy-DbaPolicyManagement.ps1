function Copy-DbaPolicyManagement {
    <#
    .SYNOPSIS
        Copies Policy-Based Management policies, conditions, and categories between SQL Server instances

    .DESCRIPTION
        Transfers your entire Policy-Based Management framework from one SQL Server instance to another, including custom policies, conditions, and categories. This streamlines environment standardization and disaster recovery scenarios where you need identical compliance policies across multiple servers.

        By default, all non-system policies and conditions are copied. Existing objects on the destination are skipped unless -Force is used to overwrite them. You can selectively copy specific policies or conditions using the include/exclude parameters, which provide auto-completion from the source server.

    .PARAMETER Source
        Specifies the source SQL Server instance containing the Policy-Based Management objects to copy. Must be SQL Server 2008 or higher with sysadmin access.
        Use this to identify which server contains your existing policies, conditions, and categories that need to be replicated to other instances.

    .PARAMETER SourceSqlCredential
        Alternative credentials for connecting to the source SQL Server instance. Use when the current Windows credentials don't have access to the source.
        Commonly needed when copying from production servers that require SQL Authentication or different Active Directory accounts.

    .PARAMETER Destination
        Specifies one or more destination SQL Server instances where Policy-Based Management objects will be created. Must be SQL Server 2008 or higher with sysadmin access.
        Use this when standardizing compliance policies across multiple environments like development, staging, and production servers.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for connecting to the destination SQL Server instances. Use when the current Windows credentials don't have access to the destination servers.
        Particularly useful when copying to servers in different domains or when using SQL Authentication on destination instances.

    .PARAMETER Policy
        Specifies which policies to copy by name, with auto-completion from the source server. Only the specified policies and their dependent conditions are copied.
        Use this when you need to copy specific compliance policies rather than the entire Policy-Based Management framework, such as copying only security-related policies.

    .PARAMETER ExcludePolicy
        Specifies which policies to skip during the copy operation, with auto-completion from the source server. All other policies will be copied.
        Use this to exclude environment-specific policies or policies that shouldn't be replicated, such as development-only or deprecated policies.

    .PARAMETER Condition
        Specifies which conditions to copy by name, with auto-completion from the source server. Only the specified conditions are copied without their associated policies.
        Use this when you need to copy reusable conditions that can be referenced by multiple policies, such as server configuration or database naming conditions.

    .PARAMETER ExcludeCondition
        Specifies which conditions to skip during the copy operation, with auto-completion from the source server. All other conditions will be copied.
        Use this to exclude conditions that are environment-specific or no longer needed, while copying the rest of your condition library.

    .PARAMETER Force
        Overwrites existing policies and conditions on the destination server by dropping and recreating them. Without this switch, existing objects are skipped.
        Use this when updating existing Policy-Based Management objects or when you need to ensure destination objects match the source exactly.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        https://dbatools.io/Copy-DbaPolicyManagement

    .OUTPUTS
        PSCustomObject

        Returns one object per policy category, condition, and policy successfully copied or skipped. All objects use a common schema with the following properties:

        Default display properties (via Select-DefaultView):
        - DateTime: Timestamp of when the copy operation was attempted (DbaDateTime)
        - SourceServer: The source SQL Server instance name where the object was copied from
        - DestinationServer: The destination SQL Server instance name where the object was copied to
        - Name: The name of the policy category, condition, or policy that was processed
        - Type: The type of object being copied - one of "Policy Category", "Policy Condition", or "Policy"
        - Status: The result of the operation - "Successful", "Skipped", or "Failed"
        - Notes: Additional information about the operation result, such as "Already exists on destination" or error details

    .EXAMPLE
        PS C:\> Copy-DbaPolicyManagement -Source sqlserver2014a -Destination sqlcluster

        Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials.

    .EXAMPLE
        PS C:\> Copy-DbaPolicyManagement -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all policies and conditions from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaPolicyManagement -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        PS C:\> Copy-DbaPolicyManagement -Source sqlserver2014a -Destination sqlcluster -Policy 'xp_cmdshell must be disabled'

        Copies only one policy, 'xp_cmdshell must be disabled' from sqlserver2014a to sqlcluster. No conditions are migrated.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$Policy,
        [object[]]$ExcludePolicy,
        [object[]]$Condition,
        [object[]]$ExcludeCondition,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaPolicyManagement does not support Linux - we're still waiting for the Core SMOs from Microsoft"
            return
        }

        Add-PbmLibrary
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $sourceSqlConn = $sourceServer.ConnectionContext.SqlConnectionObject
        $sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
        $sourceStore = New-Object  Microsoft.SqlServer.Management.DMF.PolicyStore $sourceSqlStoreConnection
        $storePolicies = $sourceStore.Policies | Where-Object { $_.IsSystemObject -eq $false }
        $storeConditions = $sourceStore.Conditions | Where-Object { $_.IsSystemObject -eq $false }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
            $destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
            $destStore = New-Object  Microsoft.SqlServer.Management.DMF.PolicyStore $destSqlStoreConnection

            if ($Policy) {
                $storePolicies = $storePolicies | Where-Object Name -In $Policy
            }
            if ($ExcludePolicy) {
                $storePolicies = $storePolicies | Where-Object Name -NotIn $ExcludePolicy
            }
            if ($Condition) {
                $storeConditions = $storeConditions | Where-Object Name -In $Condition
            }
            if ($ExcludeCondition) {
                $storeConditions = $storeConditions | Where-Object Name -NotIn $ExcludeCondition
            }

            if ($Policy -and $Condition) {
                $storeConditions = $null
                $storePolicies = $null
            }

            <#
                            Categories
            #>

            Write-Message -Level Verbose -Message "Migrating categories"
            $uniquePolicyCategories = $storePolicies | Select-Object -ExpandProperty PolicyCategory -Unique
            $storeCategories = $sourceStore.PolicyCategories | Where-Object { $_.Name -in $uniquePolicyCategories }
            foreach ($category in $storeCategories) {
                $categoryName = $category.Name

                $copyCategoryStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $categoryName
                    Type              = "Policy Category"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destStore.PolicyCategories['Database']) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Policy category '$categoryName' was skipped because it already exists on $destination")) {
                        Write-Message -Level Verbose -Message "Policy category '$categoryName' was skipped because it already exists on $destination."
                        $copyCategoryStatus.Status = "Skipped"
                        $copyCategoryStatus.Notes = "Already exists on destination"
                        $copyCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($Pscmdlet.ShouldProcess($destination, "Migrating policy category $categoryName") -and $copyCategoryStatus.Status -ne 'Skipped') {
                    try {
                        $sql = $category.ScriptCreate().GetScript() | Out-String
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Copying policy category $categoryName"
                        $null = $destServer.Query($sql)
                        $destStore.PolicyCategories.Refresh()
                        $copyCategoryStatus.Status = "Successful"
                        $copyCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyCategoryStatus.Status = "Failed"
                        $copyCategoryStatus.Notes = $_.Exception.Message
                        $copyCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue copying policy category $categoryName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            <#
                        Conditions
            #>

            Write-Message -Level Verbose -Message "Migrating conditions"
            foreach ($condition in $storeConditions) {
                $conditionName = $condition.Name

                $copyConditionStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $conditionName
                    Type              = "Policy Condition"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destStore.Conditions[$conditionName]) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Condition '$conditionName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate")) {
                            Write-Message -Level Verbose -Message "condition '$conditionName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate"
                            $copyConditionStatus.Status = "Skipped"
                            $copyConditionStatus.Notes = "Already exists on destination"
                            $copyConditionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to drop policy condition $conditionName")) {
                            Write-Message -Level Verbose -Message "Condition '$conditionName' exists on $destinstance. Force specified. Dropping $conditionName."

                            try {
                                $dependentPolicies = $destStore.Conditions[$conditionName].EnumDependentPolicies()
                                foreach ($dependent in $dependentPolicies) {
                                    $dependent.Drop()
                                    $destStore.Conditions.Refresh()
                                }
                                $destStore.Conditions[$conditionName].Drop()
                            } catch {
                                $copyConditionStatus.Status = "Failed"
                                $copyConditionStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                $copyConditionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping policy condition $conditionName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Migrating condition $conditionName")) {
                    try {
                        $sql = $condition.ScriptCreate().GetScript() | Out-String
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Copying condition $conditionName"
                        $null = $destServer.Query($sql)
                        $destStore.Conditions.Refresh()

                        $copyConditionStatus.Status = "Successful"
                        $copyConditionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyConditionStatus.Status = "Failed"
                        $copyConditionStatus.Notes = (Get-ErrorMessage -Record $_).Message
                        $copyConditionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating policy condition $conditionName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            <#
                        Policies
            #>

            Write-Message -Level Verbose -Message "Migrating policies"
            foreach ($policy in $storePolicies) {
                $policyName = $policy.Name

                $copyPolicyStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $policyName
                    Type              = "Policy"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destStore.Policies[$policyName]) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Policy '$policyName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate")) {
                            Write-Message -Level Verbose -Message "Policy '$policyName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate"

                            $copyPolicyStatus.Status = "Skipped"
                            $copyPolicyStatus.Notes = "Already exists on destination"
                            $copyPolicyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to drop $policyName")) {
                            Write-Message -Level Verbose -Message "Policy '$policyName' exists on $destinstance. Force specified. Dropping $policyName."

                            try {
                                $destStore.Policies[$policyName].Drop()
                                $destStore.Policies.refresh()
                            } catch {
                                $copyPolicyStatus.Status = "Failed"
                                $copyPolicyStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                $copyPolicyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue creating policy $policyName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Migrating policy $policyName")) {
                    try {
                        $destStore.Conditions.Refresh()
                        $destStore.Policies.Refresh()
                        $sql = $policy.ScriptCreate().GetScript() | Out-String
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Copying policy $policyName"
                        $null = $destServer.Query($sql)

                        $copyPolicyStatus.Status = "Successful"
                        $copyPolicyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyPolicyStatus.Status = "Failed"
                        $copyPolicyStatus.Notes = (Get-ErrorMessage -Record $_).Message
                        $copyPolicyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        # This is usually because of a duplicate dependent from above. Just skip for now.
                        # (no idea what the above means)
                        Write-Message -Level Verbose -Message "Issue creating policy $policyName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}