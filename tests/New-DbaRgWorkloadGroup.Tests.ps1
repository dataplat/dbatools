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
        $testWorkloadGroup = "dbatoolssci_wklgroupTest"
        $testWorkloadGroup2 = "dbatoolssci_wklgroupTest2"
        $testResourcePool = "dbatoolssci_poolTest"
        $testResourcePoolType = "Internal"

        # Enable Resource Governor for all tests
        $null = Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -Enabled

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining test workload groups and resource pools
        $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle -WorkloadGroup $testWorkloadGroup, $testWorkloadGroup2 -ErrorAction SilentlyContinue
        $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -ResourcePool $testResourcePool -Type $testResourcePoolType -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When creating workload groups" {
        AfterEach {
            # Clean up after each test
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle -WorkloadGroup $testWorkloadGroup, $testWorkloadGroup2 -ErrorAction SilentlyContinue
        }

        It "Creates a workload group in default resource pool" {
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.InstanceSingle
                WorkloadGroup = $testWorkloadGroup
                Force         = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq $testWorkloadGroup
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq $testWorkloadGroup

            $newWorkloadGroup | Should -Not -Be $null
            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $testWorkloadGroup
        }

        It "Does nothing without -Force if workload group exists" {
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.InstanceSingle
                WorkloadGroup = $testWorkloadGroup
                WarningAction = "SilentlyContinue"
            }
            $result1 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result2 = New-DbaRgWorkloadGroup @splatNewWorkloadGroup

            $result1 | Should -Not -Be $null
            $result2 | Should -Be $null
        }

        It "Creates a workload group in a user defined resource pool" {
            $splatNewResourcePool = @{
                SqlInstance  = $TestConfig.InstanceSingle
                ResourcePool = $testResourcePool
                Type         = $testResourcePoolType
                Force        = $true
            }
            $splatNewWorkloadGroup = @{
                SqlInstance                         = $TestConfig.InstanceSingle
                WorkloadGroup                       = $testWorkloadGroup
                ResourcePool                        = $testResourcePool
                ResourcePoolType                    = $testResourcePoolType
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

            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle -WorkloadGroup $testWorkloadGroup -ResourcePool $testResourcePool
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -ResourcePool $testResourcePool -Type $testResourcePoolType

            $newWorkloadGroup.Parent.Name | Should -Be $testResourcePool
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
                SqlInstance = $TestConfig.InstanceSingle
                Force       = $true
            }
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -in $testWorkloadGroup, $testWorkloadGroup2
            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup -WorkloadGroup $testWorkloadGroup, $testWorkloadGroup2
            $result2 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -in $testWorkloadGroup, $testWorkloadGroup2

            $newWorkloadGroups | Should -Not -Be $null
            $result2.Count | Should -Be 2
            $result.Count | Should -Be ($result2.Count - 2)
        }

        It "Skips Resource Governor reconfiguration" {
            $splatNewWorkloadGroup = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WorkloadGroup   = $testWorkloadGroup
                SkipReconfigure = $true
                Force           = $true
                WarningAction   = "SilentlyContinue"
            }

            $null = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle

            $result.ReconfigurePending | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.InstanceSingle
                WorkloadGroup = $testWorkloadGroup
                Force         = $true
            }
            $result = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle -WorkloadGroup $testWorkloadGroup -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.WorkloadGroup]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Id',
                'Name',
                'ExternalResourcePoolName',
                'GroupMaximumRequests',
                'Importance',
                'IsSystemObject',
                'MaximumDegreeOfParallelism',
                'RequestMaximumCpuTimeInSeconds',
                'RequestMaximumMemoryGrantPercentage',
                'RequestMemoryGrantTimeoutInSeconds'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}