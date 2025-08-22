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
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $instanceName = $server.ServiceName
            $computerName = $server.NetName
        }

        It "stops some services" {
            $services = Stop-DbaService -ComputerName $TestConfig.instance2 -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Stopped'
                $service.Status | Should -Be 'Successful'
            }

            # Start services using native cmdlets
            if ($instanceName -eq 'MSSQLSERVER') {
                $serviceName = "SQLSERVERAGENT"
            } else {
                $serviceName = "SqlAgent`$$instanceName"
            }
            Get-Service -ComputerName $computerName -Name $serviceName | Start-Service -WarningAction SilentlyContinue | Out-Null
        }

        It "stops specific services based on instance name through pipeline" {
            $services = Get-DbaService -ComputerName $TestConfig.instance2 -InstanceName $instanceName -Type Agent, Engine | Stop-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Stopped'
                $service.Status | Should -Be 'Successful'
            }

            # Start services using native cmdlets
            if ($instanceName -eq 'MSSQLSERVER') {
                $serviceName = "MSSQLSERVER", "SQLSERVERAGENT"
            } else {
                $serviceName = "MsSql`$$instanceName", "SqlAgent`$$instanceName"
            }
            foreach ($sn in $servicename) { Get-Service -ComputerName $computerName -Name $sn | Start-Service -WarningAction SilentlyContinue | Out-Null }
        }
    }
}