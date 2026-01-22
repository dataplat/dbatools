#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaService",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart
            $instanceName = $server.ServiceName
            $computerName = $server.NetName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        Context "Output Validation" {
            BeforeAll {
                $null = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent -EnableException
                $result = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent -EnableException
            }

            It "Returns the documented output type" {
                $result.PSObject.TypeNames | Should -Contain "Dataplat.Dbatools.DbaSqlService"
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
                $actualProps = $result.PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            }

            It "Returns objects with correct Status for successful start" {
                $result.Status | Should -Be 'Successful'
            }

            It "Returns objects with correct State for running services" {
                $result.State | Should -Be 'Running'
            }
        }

        Context "Single service restart" {
            BeforeAll {
                $null = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
            }

            It "starts the services back" {
                $services = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
                $services | Should -Not -BeNullOrEmpty
                foreach ($service in $services) {
                    $service.State | Should -Be 'Running'
                    $service.Status | Should -Be 'Successful'
                }
            }
        }

        Context "Multiple services through pipeline" {
            BeforeAll {
                $null = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine -Force
            }

            It "starts the services back through pipeline" {
                $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine | Start-DbaService
                $services | Should -Not -BeNullOrEmpty
                foreach ($service in $services) {
                    $service.State | Should -Be 'Running'
                    $service.Status | Should -Be 'Successful'
                }
            }
        }

        Context "Error handling" {
            It "errors when passing an invalid InstanceName" {
                { Start-DbaService -ComputerName $TestConfig.InstanceRestart -Type 'Agent' -InstanceName 'ThisIsInvalid' -EnableException } | Should -Throw 'No SQL Server services found with current parameters.'
            }
        }
    }
}