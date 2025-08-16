#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName   = "dbatools",
    $CommandName = "Set-DbaRgWorkloadGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "WorkloadGroup",
                "ResourcePool",
                "ResourcePoolType",
                "Importance",
                "RequestMaximumMemoryGrantPercentage",
                "RequestMaximumCpuTimeInSeconds",
                "RequestMemoryGrantTimeoutInSeconds",
                "MaximumDegreeOfParallelism",
                "GroupMaximumRequests",
                "SkipReconfigure",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Functionality" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $null = Set-DbaResourceGovernor -SqlInstance $TestConfig.instance2 -Enabled

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            # Cleanup any remaining workload groups
            $wklGroupCleanupNames = @("dbatoolssci_wklgroupTest", "dbatoolssci_wklgroupTest2")
            $resourcePoolCleanupName = "dbatoolssci_poolTest"

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupCleanupNames -ErrorAction SilentlyContinue
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolCleanupName -Type "Internal" -ErrorAction SilentlyContinue

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Sets a workload group in default resource pool" {
            $wklGroupTestName = "dbatoolssci_wklgroupTest"
            $resourcePoolTestType = "Internal"
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $wklGroupTestName
                ResourcePool                        = "default"
                ResourcePoolType                    = $resourcePoolTestType
                Importance                          = "MEDIUM"
                RequestMaximumMemoryGrantPercentage = 25
                RequestMaximumCpuTimeInSeconds      = 0
                RequestMemoryGrantTimeoutInSeconds  = 0
                MaximumDegreeOfParallelism          = 0
                GroupMaximumRequests                = 0
                Force                               = $true
            }
            $splatSetWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $wklGroupTestName
                ResourcePool                        = "default"
                ResourcePoolType                    = $resourcePoolTestType
                Importance                          = "HIGH"
                RequestMaximumMemoryGrantPercentage = 26
                RequestMaximumCpuTimeInSeconds      = 5
                RequestMemoryGrantTimeoutInSeconds  = 5
                MaximumDegreeOfParallelism          = 2
                GroupMaximumRequests                = 1
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Set-DbaRgWorkloadGroup @splatSetWorkloadGroup
            $resGov = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $newWorkloadGroup | Should -Not -Be $null
            $resGov.ReconfigurePending | Should -Be $false
            $result.Importance | Should -Be $splatSetWorkloadGroup.Importance
            $result.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroup.RequestMaximumMemoryGrantPercentage
            $result.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroup.RequestMaximumCpuTimeInSeconds
            $result.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroup.RequestMemoryGrantTimeoutInSeconds
            $result.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroup.MaximumDegreeOfParallelism
            $result.GroupMaximumRequests | Should -Be $splatSetWorkloadGroup.GroupMaximumRequests
        }

        It "Sets a workload group in a user defined resource pool" {
            $wklGroupUserTestName = "dbatoolssci_wklgroupTest"
            $resourcePoolUserTestName = "dbatoolssci_poolTest"
            $resourcePoolUserTestType = "Internal"
            $splatNewResourcePool = @{
                SqlInstance  = $TestConfig.instance2
                ResourcePool = $resourcePoolUserTestName
                Type         = $resourcePoolUserTestType
                Force        = $true
            }
            $splatNewWorkloadGroupUser = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $wklGroupUserTestName
                ResourcePool                        = $resourcePoolUserTestName
                ResourcePoolType                    = $resourcePoolUserTestType
                Importance                          = "MEDIUM"
                RequestMaximumMemoryGrantPercentage = 25
                RequestMaximumCpuTimeInSeconds      = 0
                RequestMemoryGrantTimeoutInSeconds  = 0
                MaximumDegreeOfParallelism          = 0
                GroupMaximumRequests                = 0
                Force                               = $true
            }
            $splatSetWorkloadGroupUser = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $wklGroupUserTestName
                ResourcePool                        = $resourcePoolUserTestName
                ResourcePoolType                    = $resourcePoolUserTestType
                Importance                          = "HIGH"
                RequestMaximumMemoryGrantPercentage = 26
                RequestMaximumCpuTimeInSeconds      = 5
                RequestMemoryGrantTimeoutInSeconds  = 5
                MaximumDegreeOfParallelism          = 2
                GroupMaximumRequests                = 1
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroupUser
            $result = Set-DbaRgWorkloadGroup @splatSetWorkloadGroupUser
            $resGov = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupUserTestName -ResourcePool $resourcePoolUserTestName
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolUserTestName -Type $resourcePoolUserTestType

            $newWorkloadGroup | Should -Not -Be $null
            $resGov.ReconfigurePending | Should -Be $false
            $result.Importance | Should -Be $splatSetWorkloadGroupUser.Importance
            $result.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroupUser.RequestMaximumMemoryGrantPercentage
            $result.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroupUser.RequestMaximumCpuTimeInSeconds
            $result.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroupUser.RequestMemoryGrantTimeoutInSeconds
            $result.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroupUser.MaximumDegreeOfParallelism
            $result.GroupMaximumRequests | Should -Be $splatSetWorkloadGroupUser.GroupMaximumRequests
        }

        It "Sets multiple workload groups" {
            $wklGroupMultiTestName = "dbatoolssci_wklgroupTest"
            $wklGroupMultiTestName2 = "dbatoolssci_wklgroupTest2"
            $splatNewWorkloadGroupMulti = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = @($wklGroupMultiTestName, $wklGroupMultiTestName2)
                Importance                          = "MEDIUM"
                RequestMaximumMemoryGrantPercentage = 25
                RequestMaximumCpuTimeInSeconds      = 0
                RequestMemoryGrantTimeoutInSeconds  = 0
                MaximumDegreeOfParallelism          = 0
                GroupMaximumRequests                = 0
                Force                               = $true
            }
            $splatSetWorkloadGroupMulti = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = @($wklGroupMultiTestName, $wklGroupMultiTestName2)
                ResourcePool                        = "default"
                Importance                          = "HIGH"
                RequestMaximumMemoryGrantPercentage = 26
                RequestMaximumCpuTimeInSeconds      = 5
                RequestMemoryGrantTimeoutInSeconds  = 5
                MaximumDegreeOfParallelism          = 2
                GroupMaximumRequests                = 1
            }
            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroupMulti
            $result = Set-DbaRgWorkloadGroup @splatSetWorkloadGroupMulti
            $resGov = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $newWorkloadGroups | Should -Not -Be $null
            $resGov.ReconfigurePending | Should -Be $false
            $result.Foreach{ $PSItem.Importance | Should -Be $splatSetWorkloadGroupMulti.Importance }
            $result.Foreach{ $PSItem.RequestMaximumMemoryGrantPercentage | Should -Be $splatSetWorkloadGroupMulti.RequestMaximumMemoryGrantPercentage }
            $result.Foreach{ $PSItem.RequestMaximumCpuTimeInSeconds | Should -Be $splatSetWorkloadGroupMulti.RequestMaximumCpuTimeInSeconds }
            $result.Foreach{ $PSItem.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatSetWorkloadGroupMulti.RequestMemoryGrantTimeoutInSeconds }
            $result.Foreach{ $PSItem.MaximumDegreeOfParallelism | Should -Be $splatSetWorkloadGroupMulti.MaximumDegreeOfParallelism }
            $result.Foreach{ $PSItem.GroupMaximumRequests | Should -Be $splatSetWorkloadGroupMulti.GroupMaximumRequests }
        }

        It "Sets a piped workload group" {
            $wklGroupPipeTestName = "dbatoolssci_wklgroupTest"
            $oldGroupMaximumRequests = 10
            $newGroupMaximumRequests = 10
            $splatNewWorkloadGroupPipe = @{
                SqlInstance          = $TestConfig.instance2
                WorkloadGroup        = $wklGroupPipeTestName
                ResourcePool         = "default"
                GroupMaximumRequests = $oldGroupMaximumRequests
                Force                = $true
            }
            $result = New-DbaRgWorkloadGroup @splatNewWorkloadGroupPipe
            $result2 = $result | Set-DbaRgWorkloadGroup -GroupMaximumRequests $newGroupMaximumRequests

            $result.GroupMaximumRequests | Should -Be $oldGroupMaximumRequests
            $result2.GroupMaximumRequests | Should -Be $newGroupMaximumRequests
        }

        It "Skips Resource Governor reconfiguration" {
            $wklGroupSkipTestName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroupSkip = @{
                SqlInstance     = $TestConfig.instance2
                WorkloadGroup   = $wklGroupSkipTestName
                SkipReconfigure = $false
                Force           = $true
            }
            $splatSetWorkloadGroupSkip = @{
                SqlInstance      = $TestConfig.instance2
                WorkloadGroup    = $wklGroupSkipTestName
                ResourcePool     = "default"
                ResourcePoolType = "Internal"
                Importance       = "HIGH"
                SkipReconfigure  = $true
                WarningAction    = "SilentlyContinue"
            }

            $null = New-DbaRgWorkloadGroup @splatNewWorkloadGroupSkip
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2
            $result.ReconfigurePending | Should -Be $false

            $null = Set-DbaRgWorkloadGroup @splatSetWorkloadGroupSkip
            $result2 = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2
            $result2.ReconfigurePending | Should -Be $true
        }

        AfterEach {
            $wklGroupCleanupName = "dbatoolssci_wklgroupTest"
            $wklGroupCleanupName2 = "dbatoolssci_wklgroupTest2"
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupCleanupName, $wklGroupCleanupName2 -ErrorAction SilentlyContinue
        }
    }
}