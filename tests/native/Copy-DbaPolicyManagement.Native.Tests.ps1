#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaPolicyManagement",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; destination arrays are covered below.
# NativeChecklist: sql-login N/A -- the pinned command has SourceSqlCredential and DestinationSqlCredential but no SqlCredential parameter.
# NativeChecklist: azure-sqldb N/A -- Policy-Based Management applies to SQL Server only and stores its policies, conditions, object sets and categories in msdb (Microsoft Learn, Policy-Based Management Storage), which Azure SQL Database does not have (Microsoft Learn, msdb database: SQL Server and Azure SQL Managed Instance); the command also requires SQL Server 2008 or higher through -MinimumVersion 10. The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.
# NativeMock: Copy-DbaPolicyManagement.Object set selection.copies only object sets required by selected policies -- covered by "copies only the object sets the selected policy needs".
Describe "Native Copy-DbaPolicyManagement" -Tag IntegrationTests {
    BeforeAll {
        $nativePbmSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $nativePbmDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $nativePbmSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $nativePbmCategory = "dbatoolsci_category_$nativePbmSuffix"
        $nativePbmConditionA = "dbatoolsci_conditiona_$nativePbmSuffix"
        $nativePbmConditionB = "dbatoolsci_conditionb_$nativePbmSuffix"
        $nativePbmObjectSetA = "dbatoolsci_objectseta_$nativePbmSuffix"
        $nativePbmObjectSetB = "dbatoolsci_objectsetb_$nativePbmSuffix"
        $nativePbmPolicyA = "dbatoolsci_policya_$nativePbmSuffix"
        $nativePbmPolicyB = "dbatoolsci_policyb_$nativePbmSuffix"
        # No source policy uses conditions C and D. D and the destination-only object set E and policy Kept are made
        # on the destination by the Force context.
        $nativePbmConditionC = "dbatoolsci_conditionc_$nativePbmSuffix"
        $nativePbmConditionD = "dbatoolsci_conditiond_$nativePbmSuffix"
        $nativePbmObjectSetE = "dbatoolsci_objectsete_$nativePbmSuffix"
        $nativePbmPolicyKept = "dbatoolsci_policykept_$nativePbmSuffix"
        # A destination-only policy and object set on condition A, which a -Force copy drops and recreates.
        $nativePbmObjectSetShared = "dbatoolsci_objectsetshared_$nativePbmSuffix"
        $nativePbmPolicyShared = "dbatoolsci_policyshared_$nativePbmSuffix"
        $nativePbmMine = @($nativePbmConditionA, $nativePbmConditionB, $nativePbmConditionC, $nativePbmConditionD)

        function Invoke-NativePbmSql ($Server, $Sql) {
            $Server.Databases["msdb"].ExecuteWithResults($Sql).Tables | ForEach-Object { $PSItem.Rows }
        }
        function Get-NativePbmName ($Server, $View) {
            # syspolicy_object_sets names its objects in object_set_name; the other views use name.
            $column = if ($View -eq "syspolicy_object_sets") { "object_set_name" } else { "name" }
            Invoke-NativePbmSql -Server $Server -Sql "SELECT $column AS name FROM msdb.dbo.$View WHERE $column LIKE N'dbatoolsci[_]%$nativePbmSuffix'" | ForEach-Object { $PSItem.name }
        }
        function Add-NativePbmCondition ($Server, $Name) {
            $splatCondition = @{
                Server = $Server
                Sql    = "DECLARE @condition_id int; EXEC msdb.dbo.sp_syspolicy_add_condition @name = N'$Name', @description = N'', @facet = N'Database', @expression = N'<Operator><TypeClass>Bool</TypeClass><OpType>GE</OpType><Count>2</Count><Attribute><TypeClass>Numeric</TypeClass><Name>SpaceAvailable</Name></Attribute><Constant><TypeClass>Numeric</TypeClass><ObjType>System.Double</ObjType><Value>0</Value></Constant></Operator>', @is_name_condition = 0, @obj_name = N'', @condition_id = @condition_id OUTPUT"
            }
            $null = Invoke-NativePbmSql @splatCondition
        }
        function Add-NativePbmObjectSet ($Server, $Name) {
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @object_set_id int; EXEC msdb.dbo.sp_syspolicy_add_object_set @object_set_name = N'$Name', @facet = N'Database', @object_set_id = @object_set_id OUTPUT"
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @target_set_id int; EXEC msdb.dbo.sp_syspolicy_add_target_set @object_set_name = N'$Name', @type_skeleton = N'Server/Database', @type = N'DATABASE', @enabled = True, @target_set_id = @target_set_id OUTPUT; EXEC msdb.dbo.sp_syspolicy_add_target_set_level @target_set_id = @target_set_id, @type_skeleton = N'Server/Database', @level_name = N'Database', @condition_name = N'', @target_set_level_id = 0"
        }
        function Add-NativePbmCategory ($Server, $Name) {
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @policy_category_id int; EXEC msdb.dbo.sp_syspolicy_add_policy_category @name = N'$Name', @mandate_database_subscriptions = 0, @policy_category_id = @policy_category_id OUTPUT"
        }
        function Add-NativePbmPolicy ($Server, $Name, $ConditionName, $ObjectSet, $Category) {
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @policy_id int; EXEC msdb.dbo.sp_syspolicy_add_policy @name = N'$Name', @condition_name = N'$ConditionName', @policy_category = N'$Category', @execution_mode = 0, @policy_id = @policy_id OUTPUT, @object_set = N'$ObjectSet'"
        }
        function Remove-NativePbmNamed ($Server, $Policies, $ObjectSets, $Conditions) {
            # Policies first, then the object sets and conditions they reference.
            foreach ($name in $Policies) {
                $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policies WHERE name = N'$name') EXEC msdb.dbo.sp_syspolicy_delete_policy @name = N'$name'"
            }
            foreach ($name in $ObjectSets) {
                $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_object_sets WHERE object_set_name = N'$name') EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_name = N'$name'"
            }
            foreach ($name in $Conditions) {
                $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = N'$name') EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$name'"
            }
        }
        function Remove-NativePbm ($Server) {
            $splatRemoveAll = @{
                Server     = $Server
                Policies   = @($nativePbmPolicyA, $nativePbmPolicyB, $nativePbmPolicyKept, $nativePbmPolicyShared)
                ObjectSets = @($nativePbmObjectSetA, $nativePbmObjectSetB, $nativePbmObjectSetE, $nativePbmObjectSetShared)
                Conditions = $nativePbmMine
            }
            Remove-NativePbmNamed @splatRemoveAll
            $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policy_categories WHERE name = N'$nativePbmCategory') EXEC msdb.dbo.sp_syspolicy_delete_policy_category @name = N'$nativePbmCategory'"
        }
        function Get-NativePbmConditionId ($Server, $Name) {
            Invoke-NativePbmSql -Server $Server -Sql "SELECT condition_id FROM msdb.dbo.syspolicy_conditions WHERE name = N'$Name'" | ForEach-Object { $PSItem.condition_id }
        }
        function Get-NativePbmPolicyDefinition ($Server, $Name) {
            # What the policy, its object set and their target sets define, with names in place of the ids, dates and
            # authors that change when an object is recreated. One sorted line per row.
            $skipColumns = @("policy_id", "condition_id", "root_condition_id", "object_set_id", "job_id", "date_created", "date_modified", "created_by", "modified_by", "target_set_id", "target_set_level_id")
            $definitionQueries = @(
                "SELECT p.*, c.name AS condition_name, os.object_set_name FROM msdb.dbo.syspolicy_policies p LEFT JOIN msdb.dbo.syspolicy_conditions c ON c.condition_id = p.condition_id LEFT JOIN msdb.dbo.syspolicy_object_sets os ON os.object_set_id = p.object_set_id WHERE p.name = N'$Name'",
                "SELECT ts.* FROM msdb.dbo.syspolicy_target_sets ts JOIN msdb.dbo.syspolicy_policies p ON p.object_set_id = ts.object_set_id WHERE p.name = N'$Name'",
                "SELECT tsl.* FROM msdb.dbo.syspolicy_target_set_levels tsl JOIN msdb.dbo.syspolicy_target_sets ts ON ts.target_set_id = tsl.target_set_id JOIN msdb.dbo.syspolicy_policies p ON p.object_set_id = ts.object_set_id WHERE p.name = N'$Name'"
            )
            foreach ($definitionQuery in $definitionQueries) {
                Invoke-NativePbmSql -Server $Server -Sql $definitionQuery | ForEach-Object {
                    $definitionRow = $PSItem
                    ($definitionRow.Table.Columns | Where-Object { $PSItem.ColumnName -notin $skipColumns } | ForEach-Object { "$($PSItem.ColumnName)=$($definitionRow[$PSItem.ColumnName])" }) -join ";"
                } | Sort-Object
            }
        }
        function Set-NativePbmShared ($Server) {
            # A destination-only policy on condition A, with an object set of its own and the category.
            $splatRemoveShared = @{
                Server     = $Server
                Policies   = @($nativePbmPolicyShared)
                ObjectSets = @($nativePbmObjectSetShared)
                Conditions = @()
            }
            Remove-NativePbmNamed @splatRemoveShared
            if (-not (Get-NativePbmConditionId -Server $Server -Name $nativePbmConditionA)) {
                Add-NativePbmCondition -Server $Server -Name $nativePbmConditionA
            }
            Add-NativePbmObjectSet -Server $Server -Name $nativePbmObjectSetShared
            Add-NativePbmPolicy -Server $Server -Name $nativePbmPolicyShared -ConditionName $nativePbmConditionA -ObjectSet $nativePbmObjectSetShared -Category $nativePbmCategory
        }

        Remove-NativePbm -Server $nativePbmSource
        Remove-NativePbm -Server $nativePbmDestination
        Add-NativePbmCategory -Server $nativePbmSource -Name $nativePbmCategory
        Add-NativePbmCondition -Server $nativePbmSource -Name $nativePbmConditionA
        Add-NativePbmCondition -Server $nativePbmSource -Name $nativePbmConditionB
        Add-NativePbmCondition -Server $nativePbmSource -Name $nativePbmConditionC
        Add-NativePbmCondition -Server $nativePbmSource -Name $nativePbmConditionD
        Add-NativePbmObjectSet -Server $nativePbmSource -Name $nativePbmObjectSetA
        Add-NativePbmObjectSet -Server $nativePbmSource -Name $nativePbmObjectSetB
        Add-NativePbmPolicy -Server $nativePbmSource -Name $nativePbmPolicyA -ConditionName $nativePbmConditionA -ObjectSet $nativePbmObjectSetA -Category $nativePbmCategory
        Add-NativePbmPolicy -Server $nativePbmSource -Name $nativePbmPolicyB -ConditionName $nativePbmConditionB -ObjectSet $nativePbmObjectSetB -Category ""
        # The destination already holds the category of the selected policy.
        Add-NativePbmCategory -Server $nativePbmDestination -Name $nativePbmCategory

        # Without -Condition every source condition is copied; the other conditions of the source are excluded so
        # the copies (and their -Force drops) touch only this file's objects.
        $nativePbmOtherConditions = @(Invoke-NativePbmSql -Server $nativePbmSource -Sql "SELECT name FROM msdb.dbo.syspolicy_conditions WHERE is_system = 0" | ForEach-Object { $PSItem.name } | Where-Object { $PSItem -notin $nativePbmMine })
        # For a copy without -Policy: the source's other policies are excluded, so it copies only this file's policies.
        $nativePbmOtherPolicies = @(Invoke-NativePbmSql -Server $nativePbmSource -Sql "SELECT name FROM msdb.dbo.syspolicy_policies" | ForEach-Object { $PSItem.name } | Where-Object { $PSItem -notin @($nativePbmPolicyA, $nativePbmPolicyB) })
        $splatNativePbm = @{
            Source           = $nativePbmSource
            ExcludeCondition = $nativePbmOtherConditions
            WarningAction    = "SilentlyContinue"
        }
    }

    AfterAll {
        Remove-NativePbm -Server $nativePbmSource
        Remove-NativePbm -Server $nativePbmDestination
    }

    It "honors WhatIf with Force" -Tag "NativeChecklist:whatif-confirm" {
        $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -Policy $nativePbmPolicyA -Force -WhatIf)
        $nativePbmResult.Count | Should -Be 0
        Get-NativePbmName -Server $nativePbmDestination -View "syspolicy_policies" | Should -BeNullOrEmpty
        Get-NativePbmName -Server $nativePbmDestination -View "syspolicy_conditions" | Should -BeNullOrEmpty
    }

    Context "Copying a selected policy" {
        BeforeAll {
            $nativePbmSelected = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -Policy $nativePbmPolicyA.ToUpperInvariant() -Confirm:$false)
        }

        It "copies only the object sets the selected policy needs" {
            $nativePbmPolicyRows = @($nativePbmSelected | Where-Object Type -eq "Policy")
            $nativePbmPolicyRows.Name | Should -Be @($nativePbmPolicyA)
            $nativePbmPolicyRows.Status | Should -Be @("Successful")
            $nativePbmPolicyRows[0].SourceServer | Should -Be $nativePbmSource.Name
            $nativePbmPolicyRows[0].DestinationServer | Should -Be $nativePbmDestination.Name
            $nativePbmPolicyRows[0].Notes | Should -BeNullOrEmpty
            $nativePbmPolicyRows[0].DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
            $nativePbmPolicyRows[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
            $nativePbmObjectSetRows = @($nativePbmSelected | Where-Object Type -eq "Policy ObjectSet")
            $nativePbmObjectSetRows.Name | Should -Be @($nativePbmObjectSetA)
            $nativePbmObjectSetRows.Status | Should -Be @("Successful")
            Get-NativePbmName -Server $nativePbmDestination -View "syspolicy_object_sets" | Should -Be @($nativePbmObjectSetA)
            Get-NativePbmName -Server $nativePbmDestination -View "syspolicy_policies" | Should -Be @($nativePbmPolicyA)
        }

        It "skips a policy category that exists on the destination" {
            $nativePbmCategoryRows = @($nativePbmSelected | Where-Object Type -eq "Policy Category")
            $nativePbmCategoryRows.Name | Should -Be @($nativePbmCategory)
            $nativePbmCategoryRows.Status | Should -Be @("Skipped")
            $nativePbmCategoryRows.Notes | Should -Be @("Already exists on destination")
        }
    }

    It "skips an existing policy without Force" {
        $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -Policy $nativePbmPolicyA -Confirm:$false)
        $nativePbmPolicyRows = @($nativePbmResult | Where-Object Type -eq "Policy")
        $nativePbmPolicyRows.Status | Should -Be @("Skipped")
        $nativePbmPolicyRows.Notes | Should -Be @("Already exists on destination")
        @($nativePbmResult | Where-Object { $PSItem.Type -eq "Policy Condition" -and $PSItem.Name -eq $nativePbmConditionA }).Status | Should -Be @("Skipped")
    }

    It "continues destination arrays after a connection failure with explicit false switches" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false", "NativeChecklist:enable-exception" {
        $splatNativePbmContinue = @{
            Destination     = @("tcp:127.0.0.1,1", $nativePbmDestination)
            Policy          = $nativePbmPolicyA
            Force           = $false
            EnableException = $false
            Confirm         = $false
            WarningVariable = "nativePbmWarning"
        }
        $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm @splatNativePbmContinue)
        @($nativePbmResult | Where-Object Type -eq "Policy").Status | Should -Be @("Skipped")
        ($nativePbmWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "throws on a destination connection failure when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        $nativePbmError = $null
        try {
            $null = Copy-DbaPolicyManagement -Source $nativePbmSource -Destination "tcp:127.0.0.1,1" -Policy $nativePbmPolicyA -EnableException -Confirm:$false
        } catch {
            $nativePbmError = $PSItem
        }
        $nativePbmError | Should -Not -BeNullOrEmpty
        $nativePbmError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }

    It "copies to every destination of the array" {
        $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination, $nativePbmDestination -Policy $nativePbmPolicyB -Confirm:$false)
        @($nativePbmResult | Where-Object Type -eq "Policy").Status | Should -Be @("Successful", "Skipped")
        @($nativePbmResult | Where-Object Type -eq "Policy ObjectSet").Status | Should -Be @("Successful", "Skipped")
        Get-NativePbmName -Server $nativePbmDestination -View "syspolicy_policies" | Sort-Object | Should -Be @($nativePbmPolicyA, $nativePbmPolicyB)
    }

    It "replaces an existing condition and its dependent policies with Force" {
        $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -Policy $nativePbmPolicyA -Force)
        @($nativePbmResult | Where-Object { $PSItem.Type -eq "Policy Condition" -and $PSItem.Name -eq $nativePbmConditionA }).Status | Should -Be @("Successful")
        @($nativePbmResult | Where-Object Type -eq "Policy").Status | Should -Be @("Successful")
        $nativePbmCopied = Invoke-NativePbmSql -Server $nativePbmDestination -Sql "SELECT c.name FROM msdb.dbo.syspolicy_policies p JOIN msdb.dbo.syspolicy_conditions c ON c.condition_id = p.condition_id WHERE p.name = N'$nativePbmPolicyA'"
        $nativePbmCopied.name | Should -Be $nativePbmConditionA
    }

    # The -Policy help: "Only the specified policies and their dependent conditions are copied."
    It "copies only the conditions the selected policy depends on" {
        $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -Policy $nativePbmPolicyA -Confirm:$false)
        @($nativePbmResult | Where-Object Type -eq "Policy Condition").Name | Should -Be @($nativePbmConditionA)
        Get-NativePbmName -Server $nativePbmDestination -View "syspolicy_conditions" | Should -Not -Contain $nativePbmConditionC
    }

    Context "Copying a selected policy with Force" {
        BeforeAll {
            # The destination holds condition D, which the selected policy does not use, and a policy of its own on D.
            $splatRemoveKept = @{
                Server     = $nativePbmDestination
                Policies   = @($nativePbmPolicyKept)
                ObjectSets = @($nativePbmObjectSetE)
                Conditions = @($nativePbmConditionD)
            }
            Remove-NativePbmNamed @splatRemoveKept
            Add-NativePbmCondition -Server $nativePbmDestination -Name $nativePbmConditionD
            Add-NativePbmObjectSet -Server $nativePbmDestination -Name $nativePbmObjectSetE
            Add-NativePbmPolicy -Server $nativePbmDestination -Name $nativePbmPolicyKept -ConditionName $nativePbmConditionD -ObjectSet $nativePbmObjectSetE -Category ""
            $nativePbmKeptId = Get-NativePbmConditionId -Server $nativePbmDestination -Name $nativePbmConditionD
            $nativePbmForced = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -Policy $nativePbmPolicyA -Force)
        }

        It "keeps an unrelated destination condition and its policies with Force" {
            @($nativePbmForced | Where-Object Type -eq "Policy Condition").Name | Should -Be @($nativePbmConditionA)
            Get-NativePbmConditionId -Server $nativePbmDestination -Name $nativePbmConditionD | Should -Be $nativePbmKeptId
            Get-NativePbmName -Server $nativePbmDestination -View "syspolicy_policies" | Should -Contain $nativePbmPolicyKept
        }
    }

    # -Force drops and recreates an existing condition, and with it every policy that uses the condition; a policy
    # the call does not copy itself comes back as it was.
    Context "Replacing a condition that a destination-only policy uses, with Force" {
        It "keeps a destination-only policy on a replaced condition when copying without -Policy" {
            Set-NativePbmShared -Server $nativePbmDestination
            $nativePbmSharedBefore = @(Get-NativePbmPolicyDefinition -Server $nativePbmDestination -Name $nativePbmPolicyShared)
            $nativePbmSharedBefore.Count | Should -BeGreaterThan 0
            $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -ExcludePolicy $nativePbmOtherPolicies -Force)
            @($nativePbmResult | Where-Object { $PSItem.Type -eq "Policy Condition" -and $PSItem.Name -eq $nativePbmConditionA }).Status | Should -Be @("Successful")
            @($nativePbmResult | Where-Object Name -eq $nativePbmPolicyShared).Count | Should -Be 0
            (@(Get-NativePbmPolicyDefinition -Server $nativePbmDestination -Name $nativePbmPolicyShared) -join "`n") | Should -BeExactly ($nativePbmSharedBefore -join "`n")
        }

        It "keeps a destination-only policy on a replaced condition when copying a selected policy" {
            Set-NativePbmShared -Server $nativePbmDestination
            $nativePbmSharedBefore = @(Get-NativePbmPolicyDefinition -Server $nativePbmDestination -Name $nativePbmPolicyShared)
            $nativePbmSharedBefore.Count | Should -BeGreaterThan 0
            $nativePbmResult = @(Copy-DbaPolicyManagement @splatNativePbm -Destination $nativePbmDestination -Policy $nativePbmPolicyA -Force)
            @($nativePbmResult | Where-Object { $PSItem.Type -eq "Policy Condition" -and $PSItem.Name -eq $nativePbmConditionA }).Status | Should -Be @("Successful")
            @($nativePbmResult | Where-Object Type -eq "Policy").Status | Should -Be @("Successful")
            @($nativePbmResult | Where-Object Name -eq $nativePbmPolicyShared).Count | Should -Be 0
            (@(Get-NativePbmPolicyDefinition -Server $nativePbmDestination -Name $nativePbmPolicyShared) -join "`n") | Should -BeExactly ($nativePbmSharedBefore -join "`n")
        }
    }
}

Describe "Native Copy-DbaPolicyManagement refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        # A name no instance has, so nothing is ever copied by these tests.
        $azurePolicyName = "dbatoolsci_pbmazure_" + [Guid]::NewGuid().ToString("N")
    }

    It "refuses an Azure SQL Database source with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureSource = @{
            Source          = $azureServer
            Destination     = $TestConfig.InstanceCopy2
            Policy          = $azurePolicyName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
            Confirm         = $false
        }
        @(Copy-DbaPolicyManagement @splatAzureSource).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses an Azure SQL Database destination with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureDestination = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $azureServer
            Policy          = $azurePolicyName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
            Confirm         = $false
        }
        @(Copy-DbaPolicyManagement @splatAzureDestination).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws the refusal as a connection error for an Azure SQL Database destination under EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaPolicyManagement -Source $TestConfig.InstanceCopy1 -Destination $azureServer -Policy $azurePolicyName -EnableException -Confirm:$false -ErrorAction SilentlyContinue
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}
