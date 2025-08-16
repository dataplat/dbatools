#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName   = "dbatools",
    $CommandName = "Set-DbaRgResourcePool",
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
                "MinimumCpuPercentage",
                "MaximumCpuPercentage",
                "CapCpuPercentage",
                "MinimumMemoryPercentage",
                "MaximumMemoryPercentage",
                "MinimumIOPSPerVolume",
                "MaximumIOPSPerVolume",
                "MaximumProcesses",
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

        It "Sets a resource pool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Set-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -MaximumCpuPercentage 99

            $result2.MaximumCpuPercentage | Should -Be 99
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
            }
            $splatSetResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 99
                MaximumMemoryPercentage = 99
                MaximumIOPSPerVolume    = 99
                CapCpuPercent           = 99
                MinimumCpuPercentage    = 2
                MinimumMemoryPercentage = 2
                MinimumIOPSPerVolume    = 2
                Type                    = "Internal"
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Set-DbaRgResourcePool @splatSetResourcePool

            $result.Name | Should -Be $resourcePoolName
            $result.MaximumCpuPercentage | Should -Be $splatSetResourcePool.MaximumCpuPercentage
            $result.MaximumMemoryPercentage | Should -Be $splatSetResourcePool.MaximumMemoryPercentage
            $result.MaximumIOPSPerVolume | Should -Be $splatSetResourcePool.MaximumIOPSPerVolume
            $result.CapCpuPercentage | Should -Be $splatSetResourcePool.CapCpuPercent
            $result.MinimumCpuPercentage | Should -Be $splatSetResourcePool.MinimumCpuPercentage
            $result.MinimumMemoryPercentage | Should -Be $splatSetResourcePool.MinimumMemoryPercentage
            $result.MinimumIOPSPerVolume | Should -Be $splatSetResourcePool.MinimumIOPSPerVolume
        }

        It "Works using -Type External" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumProcesses        = 1
                Type                    = "External"
            }
            $splatSetResourcePool = @{
                SqlInstance             = $TestConfig.instance2
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 99
                MaximumMemoryPercentage = 99
                MaximumProcesses        = 2
                Type                    = "External"
            }
            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Set-DbaRgResourcePool @splatSetResourcePool

            $result.Name | Should -Be $resourcePoolName
            $result.MaximumCpuPercentage | Should -Be $splatSetResourcePool.MaximumCpuPercentage
            $result.MaximumMemoryPercentage | Should -Be $splatSetResourcePool.MaximumMemoryPercentage
            $result.MaximumProcesses | Should -Be $splatSetResourcePool.MaximumProcesses
        }

        It "Accepts resource pools from pipe" {
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
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 | Where-Object Name -in ($resourcePoolName, $resourcePoolName2)
            ($result | Where-Object Name -eq $resourcePoolName).MaximumCpuPercentage = 99
            ($result | Where-Object Name -eq $resourcePoolName2).MaximumCpuPercentage = 98
            $result2 = $result | Set-DbaRgResourcePool

            ($result2 | Where-Object Name -eq $resourcePoolName).MaximumCpuPercentage | Should -Be 99
            ($result2 | Where-Object Name -eq $resourcePoolName2).MaximumCpuPercentage | Should -Be 98
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
            }

            $null = New-DbaRgResourcePool @splatNewResourcePool
            $null = Set-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName -MaximumCpuPercentage 99 -SkipReconfigure -WarningAction SilentlyContinue
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.instance2

            $result.ReconfigurePending | Should -Be $true
        }

        AfterEach {
            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName, $resourcePoolName2 -Type Internal -ErrorAction SilentlyContinue
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -ResourcePool $resourcePoolName, $resourcePoolName2 -Type External -ErrorAction SilentlyContinue
        }
    }
}