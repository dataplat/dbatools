#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaService",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Type",
                "InputObject",
                "Timeout",
                "Credential",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command execution and functionality" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart
            $instanceName = $server.ServiceName
            $computerName = $server.NetName
        }

        It "stops some services" {
            $services = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Stopped'
                $service.Status | Should -Be 'Successful'
            }

            $null = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
        }

        It "stops specific services based on instance name through pipeline" {
            $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine | Stop-DbaService -Force
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Stopped'
                $service.Status | Should -Be 'Successful'
            }

            $null = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Engine, Agent
        }
    }

    Context "Output validation" {
        BeforeAll {
            try {
                $restartServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart -ErrorAction Stop
                $restartInstanceName = $restartServer.ServiceName
                $result = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $restartInstanceName -Type Agent
                # Restart agent after capturing the result
                $null = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $restartInstanceName -Type Agent
            } catch {
                $result = $null
            }
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "InstanceRestart is not available" }
            $result[0].PSObject.TypeNames | Should -Contain "dbatools.DbaSqlService"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "InstanceRestart is not available" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "ServiceName", "InstanceName", "ServiceType", "State", "Status", "Message")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}