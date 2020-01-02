function Copy-DbaPolicyManagement {
    <#
    .SYNOPSIS
        Migrates SQL Policy Based Management Objects, including both policies and conditions.

    .DESCRIPTION
        By default, all policies and conditions are copied. If an object already exist on the destination, it will be skipped unless -Force is used.

        The -Policy and -Condition parameters are auto-populated for command-line completion and can be used to copy only specific objects.

    .PARAMETER Source
        Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Policy
        The policy(ies) to process - this list is auto-populated from the server. If unspecified, all policies will be processed.

    .PARAMETER ExcludePolicy
        The policy(ies) to exclude - this list is auto-populated from the server

    .PARAMETER Condition
        The condition(s) to process - this list is auto-populated from the server. If unspecified, all conditions will be processed.

    .PARAMETER ExcludeCondition
        The condition(s) to exclude - this list is auto-populated from the server

    .PARAMETER Force
        If policies exists on destination server, it will be dropped and recreated.

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
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
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
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
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

                $copyCategoryStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $categoryName
                    Type              = "Policy Category"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destStore.PolicyCategories['Database']) {
                    Write-Message -Level Verbose -Message "Policy category '$categoryName' was skipped because it already exists on $destination."

                    $copyCategoryStatus.Status = "Skipped"
                    $copyCategoryStatus.Notes = "Already exists on destination"
                    $copyCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
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

                        Stop-Function -Message "Issue creating policy category on $destination" -Target $categoryName -ErrorRecord $_
                    }
                }
            }

            <#
                        Conditions
            #>

            Write-Message -Level Verbose -Message "Migrating conditions"
            foreach ($condition in $storeConditions) {
                $conditionName = $condition.Name

                $copyConditionStatus = [pscustomobject]@{
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
                        Write-Message -Level Verbose -Message "condition '$conditionName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate"

                        $copyConditionStatus.Status = "Skipped"
                        $copyConditionStatus.Notes = "Already exists on destination"
                        $copyConditionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to drop $conditionName")) {
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
                                Stop-Function -Message "Issue dropping condition on $destinstance" -Target $conditionName -ErrorRecord $_ -Continue
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

                        Stop-Function -Message "Issue creating condition on $destinstance" -Target $conditionName -ErrorRecord $_
                    }
                }
            }

            <#
                        Policies
            #>

            Write-Message -Level Verbose -Message "Migrating policies"
            foreach ($policy in $storePolicies) {
                $policyName = $policy.Name

                $copyPolicyStatus = [pscustomobject]@{
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
                        Write-Message -Level Verbose -Message "Policy '$policyName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate"

                        $copyPolicyStatus.Status = "Skipped"
                        $copyPolicyStatus.Notes = "Already exists on destination"
                        $copyPolicyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
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

                                Stop-Function -Message "Issue dropping policy on $destinstance" -Target $policyName -ErrorRecord $_ -Continue
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
                        Stop-Function -Message "Issue creating policy on $destinstance" -Target $policyName -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}