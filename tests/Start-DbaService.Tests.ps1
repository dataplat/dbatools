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

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $instanceName = $server.ServiceName
            $computerName = $server.NetName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        Context "Single service restart" {
            BeforeAll {
                #Stop services using native cmdlets
                if ($instanceName -eq 'MSSQLSERVER') {
                    $serviceName = "SQLSERVERAGENT"
                } else {
                    $serviceName = "SqlAgent`$$instanceName"
                }
                Get-Service -ComputerName $computerName -Name $serviceName | Stop-Service -WarningAction SilentlyContinue | Out-Null
            }

            It "starts the services back" {
                $services = Start-DbaService -ComputerName $TestConfig.instance2 -Type Agent -InstanceName $instanceName
                $services | Should -Not -BeNullOrEmpty
                foreach ($service in $services) {
                    $service.State | Should -Be 'Running'
                    $service.Status | Should -Be 'Successful'
                }
            }
        }

        Context "Multiple services through pipeline" {
            BeforeAll {
                #Stop services using native cmdlets
                if ($instanceName -eq 'MSSQLSERVER') {
                    $serviceName = "SQLSERVERAGENT", "MSSQLSERVER"
                } else {
                    $serviceName = "SqlAgent`$$instanceName", "MsSql`$$instanceName"
                }
                foreach ($sn in $servicename) { Get-Service -ComputerName $computerName -Name $sn | Stop-Service -WarningAction SilentlyContinue | Out-Null }
            }

            It "starts the services back through pipeline" {
                $services = Get-DbaService -ComputerName $TestConfig.instance2 -InstanceName $instanceName -Type Agent, Engine | Start-DbaService
                $services | Should -Not -BeNullOrEmpty
                foreach ($service in $services) {
                    $service.State | Should -Be 'Running'
                    $service.Status | Should -Be 'Successful'
                }
            }
        }

        Context "Error handling" {
            It "errors when passing an invalid InstanceName" {
                { Start-DbaService -ComputerName $TestConfig.instance2 -Type 'Agent' -InstanceName 'ThisIsInvalid' -EnableException } | Should -Throw 'No SQL Server services found with current parameters.'
            }
        }
    }
}