#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaRgResourcePool",
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
                "Force",
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

            $null = Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -Enabled

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        It "Creates a resource pool" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.InstanceSingle
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool | Should -Not -Be $null

            # Capture for output validation
            $script:outputValidationResult = $newResourcePool

        }
        It "Works using -Type Internal" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.InstanceSingle
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                MinimumCpuPercentage    = 1
                MinimumMemoryPercentage = 1
                MinimumIOPSPerVolume    = 1
                Type                    = "Internal"
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -Type Internal
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -Type Internal

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool.MaximumCpuPercentage | Should -Be $splatNewResourcePool.MaximumCpuPercentage
            $newResourcePool.MaximumMemoryPercentage | Should -Be $splatNewResourcePool.MaximumMemoryPercentage
            $newResourcePool.MaximumIOPSPerVolume | Should -Be $splatNewResourcePool.MaximumIOPSPerVolume
            $newResourcePool.CapCpuPercentage | Should -Be $splatNewResourcePool.CapCpuPercent
            $newResourcePool.MinimumCpuPercentage | Should -Be $splatNewResourcePool.MinimumCpuPercentage
            $newResourcePool.MinimumMemoryPercentage | Should -Be $splatNewResourcePool.MinimumMemoryPercentage
            $newResourcePool.MinimumIOPSPerVolume | Should -Be $splatNewResourcePool.MinimumIOPSPerVolume
        }
        It "Works using -Type External" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.InstanceSingle
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumProcesses        = 5
                Type                    = "External"
                Force                   = $true
            }
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -Type External
            $newResourcePool = New-DbaRgResourcePool @splatNewResourcePool
            $result2 = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -Type External

            $result.Count | Should -BeLessThan $result2.Count
            $result2.Name | Should -Contain $resourcePoolName
            $newResourcePool.MaximumCpuPercentage | Should -Be $splatNewResourcePool.MaximumCpuPercentage
            $newResourcePool.MaximumMemoryPercentage | Should -Be $splatNewResourcePool.MaximumMemoryPercentage
            $newResourcePool.MaximumProcesses | Should -Be $splatNewResourcePool.MaximumProcesses
        }
        It "Skips Resource Governor reconfiguration" {
            $resourcePoolName = "dbatoolssci_poolTest"
            $splatNewResourcePool = @{
                SqlInstance             = $TestConfig.InstanceSingle
                ResourcePool            = $resourcePoolName
                MaximumCpuPercentage    = 100
                MaximumMemoryPercentage = 100
                MaximumIOPSPerVolume    = 100
                CapCpuPercent           = 100
                Force                   = $true
                SkipReconfigure         = $true
                WarningAction           = "SilentlyContinue"
            }

            $null = New-DbaRgResourcePool @splatNewResourcePool
            $result = Get-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle

            $result.ReconfigurePending | Should -Be $true
        }
        It "Returns output of the documented type" {
            $script:outputValidationResult | Should -Not -BeNullOrEmpty
            $script:outputValidationResult[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourcePool
        }
        It "Has the expected default display properties" {
            $defaultProps = $script:outputValidationResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Name",
                "CapCpuPercentage",
                "IsSystemObject",
                "MaximumCpuPercentage",
                "MaximumIopsPerVolume",
                "MaximumMemoryPercentage",
                "MinimumCpuPercentage",
                "MinimumIopsPerVolume",
                "MinimumMemoryPercentage",
                "WorkloadGroups"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
        AfterEach {
            # We want to run all commands in the AfterEach block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $resourcePoolName = "dbatoolssci_poolTest"
            $resourcePoolName2 = "dbatoolssci_poolTest2"
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -ResourcePool $resourcePoolName, $resourcePoolName2 -Type Internal -ErrorAction SilentlyContinue
            $null = Remove-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -ResourcePool $resourcePoolName, $resourcePoolName2 -Type External -ErrorAction SilentlyContinue

            # Reset for next test
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }
}