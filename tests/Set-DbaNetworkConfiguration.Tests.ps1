#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaNetworkConfiguration",
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
                "EnableProtocol",
                "DisableProtocol",
                "DynamicPortForIPAll",
                "StaticPortForIPAll",
                "IpAddress",
                "RestartService",
                "InputObject",
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

        # Store original configuration for restoration after tests
        $originalNetConfPiped = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle
        $originalNetConfCommandline = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Restore original configuration
        $originalNetConfPiped.TcpIpProperties.KeepAlive = 30000
        $null = $originalNetConfPiped | Set-DbaNetworkConfiguration -WarningAction SilentlyContinue

        # Restore Named Pipes to original state
        if ($originalNetConfCommandline.NamedPipesEnabled) {
            $null = Set-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -EnableProtocol NamedPipes -WarningAction SilentlyContinue
        } else {
            $null = Set-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -DisableProtocol NamedPipes -WarningAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command works with piped input" {
        BeforeAll {
            $netConfPiped = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle
            $netConfPiped.TcpIpProperties.KeepAlive = 60000
            $pipedResults = $netConfPiped | Set-DbaNetworkConfiguration -WarningAction SilentlyContinue -OutVariable "global:dbatoolsciOutput"
        }

        It "Should Return a Result" {
            $pipedResults.ComputerName | Should -Be $netConfPiped.ComputerName
        }

        It "Should Return a Change" {
            $pipedResults.Changes | Should -Match "Changed TcpIpProperties.KeepAlive to 60000"
        }
    }

    Context "Command works with commandline input" {
        BeforeAll {
            $netConfCommandline = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle
            if ($netConfCommandline.NamedPipesEnabled) {
                $commandlineResults = Set-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -DisableProtocol NamedPipes -WarningAction SilentlyContinue
            } else {
                $commandlineResults = Set-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -EnableProtocol NamedPipes -WarningAction SilentlyContinue
            }
        }

        It "Should Return a Result" {
            $commandlineResults.ComputerName | Should -Be $netConfCommandline.ComputerName
        }

        It "Should Return a Change" {
            $commandlineResults.Changes | Should -Match "Changed NamedPipesEnabled to"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Changes",
                "RestartNeeded",
                "Restarted"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}