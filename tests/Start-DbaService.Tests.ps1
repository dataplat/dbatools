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
                $services = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent -OutVariable "global:dbatoolsciOutput"
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

        Context "Output validation" {
            AfterAll {
                $global:dbatoolsciOutput = $null
            }

            It "Should have the custom dbatools type name" {
                $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.DbaSqlService"
            }

            It "Should have the correct default display columns" {
                $expectedColumns = @(
                    "ComputerName",
                    "ServiceName",
                    "InstanceName",
                    "ServiceType",
                    "State",
                    "Status",
                    "Message"
                )
                $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
            }

            It "Should have accurate .OUTPUTS documentation" {
                $help = Get-Help $CommandName -Full
                $help.returnValues.returnValue.type.name | Should -Match "DbaSqlService"
            }
        }
    }
}