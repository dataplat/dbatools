#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaService",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object {$PSItem -notin ("WhatIf", "Confirm")}
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Credential",
                "Type",
                "ServiceName",
                "AdvancedProperties",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName {$null}
            {Get-DbaService -ComputerName "DoesNotExist142" -WarningAction Stop 3> $null} | Should -Throw
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $instanceName = (Connect-DbaInstance -SqlInstance $TestConfig.instance2).ServiceName
            $allServicesResults = Get-DbaService -ComputerName $TestConfig.instance2
            $agentServicesResults = Get-DbaService -ComputerName $TestConfig.instance2 -Type Agent
            $specificInstanceResults = Get-DbaService -ComputerName $TestConfig.instance2 -InstanceName $instanceName -Type Agent -AdvancedProperties
        }

        It "shows some services" {
            $allServicesResults.DisplayName | Should -Not -BeNullOrEmpty
        }

        It "shows only one service type" {
            foreach ($result in $agentServicesResults) {
                $result.DisplayName -match "Agent" | Should -Be $true
            }
        }

        It "shows a service from a specific instance" {
            $specificInstanceResults.ServiceType | Should -Be "Agent"
        }

        It "Includes a Clustered Property" {
            $specificInstanceResults.Clustered | Should -Not -BeNullOrEmpty
        }

        It "sets startup mode of the service to 'Manual'" {
            $service = Get-DbaService -ComputerName $TestConfig.instance2 -Type Agent -InstanceName $instanceName
            {$service.ChangeStartMode("Manual")} | Should -Not -Throw
        }

        It "verifies that startup mode of the service is 'Manual'" {
            $results = Get-DbaService -ComputerName $TestConfig.instance2 -Type Agent -InstanceName $instanceName
            $results.StartMode | Should -Be "Manual"
        }

        It "sets startup mode of the service to 'Automatic'" {
            $service = Get-DbaService -ComputerName $TestConfig.instance2 -Type Agent -InstanceName $instanceName
            {$service.ChangeStartMode("Automatic")} | Should -Not -Throw
        }

        It "verifies that startup mode of the service is 'Automatic'" {
            $results = Get-DbaService -ComputerName $TestConfig.instance2 -Type Agent -InstanceName $instanceName
            $results.StartMode | Should -Be "Automatic"
        }
    }

    Context "Command actually works with SqlInstance" {
        BeforeAll {
            $sqlInstanceResults = @()
            $sqlInstanceResults += Get-DbaService -SqlInstance $TestConfig.instance2 -Type Engine
        }

        It "shows exactly one service" {
            $sqlInstanceResults.Count | Should -Be 1
        }
    }
}
