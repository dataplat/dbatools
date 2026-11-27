#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbccFreeCache",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Operation",
                "InputValue",
                "NoInformationalMessages",
                "MarkInUseForRemoval",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $expectedProperties = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Operation",
            "Cmd",
            "Output"
        )
        $resultFreeSystemCache = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FreeSystemCache
    }

    Context "Validate standard output" {
        It "Should return all expected properties" {
            foreach ($property in $expectedProperties) {
                $resultFreeSystemCache.PSObject.Properties[$property] | Should -Not -BeNullOrEmpty
                $resultFreeSystemCache.PSObject.Properties[$property].Name | Should -Be $property
            }
        }
    }

    Context "Works correctly" {
        It "returns the right results for FREESYSTEMCACHE" {
            $resultFreeSystemCache.Operation | Should -Match "FREESYSTEMCACHE"
            $resultFreeSystemCache.Output | Should -Match "DBCC execution completed. If DBCC printed error messages, contact your system administrator."
        }

        It "returns the right results for FREESESSIONCACHE" {
            $resultFreeSessionCache = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FreeSessionCache
            $resultFreeSessionCache.Operation | Should -Match "FREESESSIONCACHE"
            $resultFreeSessionCache.Output | Should -Match "DBCC execution completed. If DBCC printed error messages, contact your system administrator."
        }

        It "returns the right results for FREEPROCCACHE" {
            $resultFreeProcCache = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FREEPROCCACHE
            $resultFreeProcCache.Operation | Should -Match "FREEPROCCACHE"
            $resultFreeProcCache.Output | Should -Match "DBCC execution completed. If DBCC printed error messages, contact your system administrator."
        }

        It "returns the right results for FREESESSIONCACHE and using NoInformationalMessages" {
            $resultNoInfo = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FreeSessionCache -NoInformationalMessages
            $resultNoInfo.Operation | Should -Match "FREESESSIONCACHE"
            $resultNoInfo.Output | Should -BeNullOrEmpty
        }

        It "leaves out the options of switches set to false" {
            $splatSwitchesOff = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Operation               = "FreeSystemCache"
                NoInformationalMessages = $false
                MarkInUseForRemoval     = $false
            }
            $resultSwitchesOff = Invoke-DbaDbccFreeCache @splatSwitchesOff
            $WarnVar | Should -BeNullOrEmpty
            $resultSwitchesOff.Cmd | Should -BeExactly "DBCC FREESYSTEMCACHE('ALL')"
            $resultSwitchesOff.Output | Should -Match "DBCC execution completed"
        }
    }

    Context "Without an operation" {
        It "refuses and lets the loop of the caller go on" {
            $rounds = 0
            $resultsNoOperation = foreach ($round in 1..3) {
                Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
                $rounds++
            }
            $rounds | Should -Be 3
            $resultsNoOperation | Should -BeNullOrEmpty
            $WarnVar | Should -Match "You must specify an operation"
        }

        It "throws with EnableException" {
            { Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw "*You must specify an operation*"
        }
    }

    Context "Resource pools" {
        It "clears the caches of the default pool" {
            $splatDefaultPool = @{
                SqlInstance = $TestConfig.InstanceSingle
                Operation   = "FreeSystemCache"
                InputValue  = "default"
            }
            $resultDefaultPool = Invoke-DbaDbccFreeCache @splatDefaultPool
            $WarnVar | Should -BeNullOrEmpty
            $resultDefaultPool.Output | Should -Match "DBCC execution completed"
        }

        It "warns and returns nothing for a pool that does not exist" {
            $splatMissingPool = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Operation     = "FreeSystemCache"
                InputValue    = "dbatoolsci_nopool"
                WarningAction = "SilentlyContinue"
            }
            $resultMissingPool = Invoke-DbaDbccFreeCache @splatMissingPool
            $resultMissingPool | Should -BeNullOrEmpty
            $WarnVar | Should -Match "Parameter 2 is incorrect for this DBCC statement"
        }

        It "throws for a pool that does not exist with EnableException" {
            $splatMissingPoolException = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Operation       = "FreeSystemCache"
                InputValue      = "dbatoolsci_nopool"
                EnableException = $true
            }
            { Invoke-DbaDbccFreeCache @splatMissingPoolException } | Should -Throw "*Parameter 2 is incorrect for this DBCC statement*"
        }
    }

    Context "Plan handles" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $planTag = "dbatoolsci_plan_$(Get-Random)"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "SELECT COUNT(*) AS ObjectCount FROM sys.objects WHERE name <> N'$planTag'"
            $planQuery = @"
SELECT cp.plan_handle AS PlanHandle
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.text LIKE N'%$planTag%' AND st.text NOT LIKE N'%dm_exec_cached_plans%'
"@
            $plan = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $planQuery | Select-Object -First 1
            $planHandle = "0x" + [System.BitConverter]::ToString($plan.PlanHandle).Replace("-", "")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "removes the plan of a handle" {
            $splatPlanHandle = @{
                SqlInstance = $TestConfig.InstanceSingle
                Operation   = "FreeProcCache"
                InputValue  = $planHandle
            }
            $resultPlanHandle = Invoke-DbaDbccFreeCache @splatPlanHandle
            $WarnVar | Should -BeNullOrEmpty
            $resultPlanHandle.Cmd | Should -BeExactly "DBCC FREEPROCCACHE($planHandle)"
            $resultPlanHandle.Output | Should -Match "DBCC execution completed"
            $planCount = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "SELECT COUNT(*) AS PlanCount FROM sys.dm_exec_cached_plans WHERE plan_handle = $planHandle"
            $planCount.PlanCount | Should -Be 0
        }
    }
}