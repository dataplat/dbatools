#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaRgWorkloadGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "WorkloadGroup",
                "ResourcePool",
                "ResourcePoolType",
                "SkipReconfigure",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
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
        
        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Functionality" {
        It "Removes a workload group in default resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName
            $result2 = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupName
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -Be $null
            $result.Status.Count | Should -BeGreaterThan $result3.Status.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -Be $true
            $result3 | Should -Be $null
        }
        It "Removes a workload group in a user defined resource pool" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolType = "Internal"
            $splatNewResourcePool = @{
                SqlInstance  = $TestConfig.instance2
                ResourcePool = $resourcePoolName
                Type         = $resourcePoolType
                Force        = $true
            }
            $splatNewWorkloadGroup = @{
                SqlInstance      = $TestConfig.instance2
                WorkloadGroup    = $wklGroupName
                ResourcePool     = $resourcePoolName
                ResourcePoolType = $resourcePoolType
                Force            = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName
            $result2 = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupName -ResourcePool $resourcePoolName -ResourcePoolType $resourcePoolType
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName

            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -Type $resourcePoolType

            $newWorkloadGroup | Should -Not -Be $null
            $result.Status.Count | Should -BeGreaterThan $result3.Status.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -Be $true
            $result3 | Should -Be $null
        }
        It "Removes multiple workload groups" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $wklGroupName2 = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                WorkloadGroup = @($wklGroupName, $wklGroupName2)
                Force         = $true
            }

            $newWorkloadGroups = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2
            $result2 = Remove-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 -WorkloadGroup $wklGroupName, $wklGroupName2
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -in $wklGroupName, $wklGroupName2

            $newWorkloadGroups | Should -Not -Be $null
            $result.Status.Count | Should -BeGreaterThan $result3.Status.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -Be $true
            $result3 | Should -Be $null
        }
        It "Removes a piped workload group" {
            $wklGroupName = "dbatoolssci_wklgroupTest"
            $splatNewWorkloadGroup = @{
                SqlInstance   = $TestConfig.instance2
                WorkloadGroup = $wklGroupName
                Force         = $true
            }
            $newWorkloadGroup = New-DbaRgWorkloadGroup @splatNewWorkloadGroup
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName
            $result2 = $newWorkloadGroup | Remove-DbaRgWorkloadGroup
            $result3 = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $wklGroupName

            $newWorkloadGroup | Should -Not -Be $null
            $result.Status.Count | Should -BeGreaterThan $result3.Status.Count
            $result2.Status | Should -Be "Dropped"
            $result2.IsRemoved | Should -Be $true
            $result3 | Should -Be $null
        }
    }
}
