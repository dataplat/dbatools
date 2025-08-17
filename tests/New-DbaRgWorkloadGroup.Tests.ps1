#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaRgWorkloadGroup",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set up test variables that will be used across all tests
        $global:testWorkloadGroup = "dbatoolssci_wklgroupTest"
        $global:testWorkloadGroup2 = "dbatoolssci_wklgroupTest2"
        $global:testResourcePool = "dbatoolssci_poolTest"
        $global:testResourcePoolType = "Internal"

        # Enable Resource Governor for all tests
        $null = Set-DbaResourceGovernor -SqlInstance $TestConfig.instance2 -Enabled

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining test workload groups and resource pools
        $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $global:testWorkloadGroup, $global:testWorkloadGroup2 -ErrorAction SilentlyContinue
        $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $global:testResourcePool -Type $global:testResourcePoolType -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When creating workload groups" {
        AfterEach {
            # Clean up after each test
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $global:testWorkloadGroup, $global:testWorkloadGroup2 -ErrorAction SilentlyContinue
        }

        It "Creates a workload group in default resource pool" {
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                WorkloadGroup = $global:testWorkloadGroup
                Force         = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $global:testWorkloadGroup
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $global:testWorkloadGroup

            $newWorkloadGroup | Should -Not -Be $null
            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $global:testWorkloadGroup
        }

        It "Does nothing without -Force if workload group exists" {
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                WorkloadGroup = $global:testWorkloadGroup
                WarningAction = "SilentlyContinue"
            }
            $result1 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup

            $result1 | Should -Not -Be $null
            $result2 | Should -Be $null
        }

        It "Creates a workload group in a user defined resource pool" {
            $splatNewResourcePool = @{
                SqlInstance  = $TestConfig.instance2
                ResourcePool = $global:testResourcePool
                Type         = $global:testResourcePoolType
                Force        = $true
            }
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $TestConfig.instance2
                WorkloadGroup                       = $global:testWorkloadGroup
                ResourcePool                        = $global:testResourcePool
                ResourcePoolType                    = $global:testResourcePoolType
                Importance                          = "HIGH"
                RequestMaximumMemoryGrantPercentage = 26
                RequestMaximumCpuTimeInSeconds      = 5
                RequestMemoryGrantTimeoutInSeconds  = 5
                MaximumDegreeOfParallelism          = 2
                GroupMaximumRequests                = 1
                Force                               = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $global:testWorkloadGroup -ResourcePool $global:testResourcePool
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $global:testResourcePool -Type $global:testResourcePoolType

            $newWorkloadGroup.Parent.Name | Should -Be $global:testResourcePool
            $newWorkloadGroup.Parent.GetType().Name | Should -Be "ResourcePool"
            $newWorkloadGroup.Importance | Should -Be $splatNewWorkloadGroup.Importance
            $newWorkloadGroup.RequestMaximumMemoryGrantPercentage | Should -Be $splatNewWorkloadGroup.RequestMaximumMemoryGrantPercentage
            $newWorkloadGroup.RequestMaximumCpuTimeInSeconds | Should -Be $splatNewWorkloadGroup.RequestMaximumCpuTimeInSeconds
            $newWorkloadGroup.RequestMemoryGrantTimeoutInSeconds | Should -Be $splatNewWorkloadGroup.RequestMemoryGrantTimeoutInSeconds
            $newWorkloadGroup.MaximumDegreeOfParallelism | Should -Be $splatNewWorkloadGroup.MaximumDegreeOfParallelism
            $newWorkloadGroup.GroupMaximumRequests | Should -Be $splatNewWorkloadGroup.GroupMaximumRequests
        }

        It "Creates multiple workload groups" {
            $splatNewWorkloadGroup = @{
                SqlInstance = $TestConfig.instance2
                Force       = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -in $global:testWorkloadGroup, $global:testWorkloadGroup2
            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup -WorkloadGroup $global:testWorkloadGroup, $global:testWorkloadGroup2
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -in $global:testWorkloadGroup, $global:testWorkloadGroup2

            $newWorkloadGroups | Should -Not -Be $null
            $result2.Count | Should -Be 2
            $result.Count | Should -Be ($result2.Count - 2)
        }

        It "Skips Resource Governor reconfiguration" {
            $splatNewWorkloadGroup = @{
                SqlInstance     = $TestConfig.instance2
                WorkloadGroup   = $global:testWorkloadGroup
                SkipReconfigure = $true
                Force           = $true
                WarningAction   = "SilentlyContinue"
            }

            $null = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $result.ReconfigurePending | Should -Be $true
        }
    }
}