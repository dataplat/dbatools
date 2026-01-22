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
    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart
            $instanceName = $server.ServiceName
            $result = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent -EnableException
        }

        AfterAll {
            $null = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Wmi.Service]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'ServiceName',
                'InstanceName',
                'ServiceType',
                'State',
                'Status',
                'Message'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties accessible via Select-Object" {
            $additionalProps = @(
                'ServiceAccount',
                'StartMode',
                'Properties',
                'Parent'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }
    }

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
}