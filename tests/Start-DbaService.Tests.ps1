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
                $script:outputForValidation = $services
            }

            Context "Output validation" {
                It "Returns output of the expected type" {
                    if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                    $script:outputForValidation[0].psobject.TypeNames | Should -Contain "dbatools.DbaSqlService"
                }

                It "Has the expected default display properties" {
                    if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                    $defaultProps = $script:outputForValidation[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                    $expectedDefaults = @("ComputerName", "ServiceName", "InstanceName", "ServiceType", "State", "Status", "Message")
                    foreach ($prop in $expectedDefaults) {
                        $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                    }
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