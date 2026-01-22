#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaTcpPort",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Port",
                "IpAddress",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $originalPortInfo = Get-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart
            $originalPort = $originalPortInfo.Port
            $testPort = $originalPort + 1000
            $instance = [DbaInstance]$TestConfig.InstanceRestart
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $result = Set-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart -Port $testPort -WarningAction SilentlyContinue -EnableException
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart -Port $originalPort -WarningAction SilentlyContinue
            $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Type Engine -Force -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Changes',
                'RestartNeeded',
                'Restarted'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "When changing TCP port configuration" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Get the current port before making any changes
            $originalPortInfo = Get-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart
            $originalPort = $originalPortInfo.Port
            $testPort = $originalPort + 1000
            $instance = [DbaInstance]$TestConfig.InstanceRestart

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Restore the original port configuration
            $null = Set-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart -Port $originalPort -WarningAction SilentlyContinue
            $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Type Engine -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should change the port" {
            $result = Set-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart -Port $testPort -WarningAction SilentlyContinue
            $result.Changes | Should -Match "Changed TcpPort"
            $result.RestartNeeded | Should -Be $true
            $result.Restarted | Should -Be $false

            $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Type Engine -Force

            $setPort = (Get-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart).Port
            $setPort | Should -Be $testPort
        }

        It "Should change the port back to the old value" {
            $result = Set-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart -Port $originalPort -WarningAction SilentlyContinue
            $result.Changes | Should -Match "Changed TcpPort"
            $result.RestartNeeded | Should -Be $true
            $result.Restarted | Should -Be $false

            $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Type Engine -Force

            $setPort = (Get-DbaTcpPort -SqlInstance $TestConfig.InstanceRestart).Port
            $setPort | Should -Be $originalPort
        }
    }
}