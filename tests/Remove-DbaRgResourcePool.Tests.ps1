#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaRgResourcePool",
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
                "ResourcePool",
                "Type",
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
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Set-DbaResourceGovernor -SqlInstance $TestConfig.instance2 -Enabled

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any remaining test resource pools
            $testPools = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 | Where-Object Name -like "dbatoolssci_poolTest*"
            if ($testPools) {
                $null = $testPools | Remove-DbaRgResourcePool
            }
        }

        It "Removes a resource pool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2
            Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
        }

        It "Works using -Type Internal" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Type                    = "Internal"
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type Internal
            Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -Type Internal
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
        }

        It "Works using -Type External" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Type                    = "External"
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type External
            Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -Type External
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type External

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
        }

        It "Accepts a list of resource pools" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName2
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2
            Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName, $resourcePoolName2
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
            $result2.Name | Should -Not -Contain $resourcePoolName2
        }

        It "Accepts input from Get-DbaRgResourcePool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName
            $null = New-DbaRgResourcePool @splatNewResourcePool -ResourcePool $resourcePoolName2
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2
            $result | Where-Object Name -in ($resourcePoolName, $resourcePoolName2) | Remove-DbaRgResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2

            $result.Count | Should -BeGreaterThan $result2.Count
            $result2.Name | Should -Not -Contain $resourcePoolName
            $result2.Name | Should -Not -Contain $resourcePoolName2
        }

        It "Skips Resource Governor reconfiguration" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -SkipReconfigure -WarningAction SilentlyContinue
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $result.ReconfigurePending | Should -Be $true
        }
    }
}