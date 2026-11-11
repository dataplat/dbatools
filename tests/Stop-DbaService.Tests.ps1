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

    # A service that was already stopped got no CIM call and vanished from the output, without a row (#10822). A service
    # that refused to stop only warned, also with -EnableException.
    Context "Services that are already stopped or refuse to stop" {
        BeforeAll {
            $splatInstance = @{
                ComputerName = $TestConfig.InstanceRestart
                InstanceName = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart).ServiceName
            }
        }

        It "returns a row for a service that is already stopped" {
            try {
                $null = Stop-DbaService @splatInstance -Type Agent -EnableException

                $results = @(Stop-DbaService @splatInstance -Type Agent)
                $WarnVar | Should -BeNullOrEmpty
                @($results).Count | Should -Be 1
                $results[0].State | Should -Be "Stopped"
                $results[0].Status | Should -Be "Successful"
                $results[0].Message | Should -BeLike "*already stopped*"
            } finally {
                $null = Start-DbaService @splatInstance -Type Agent
            }
        }

        It "reports an engine that refuses to stop as failed, and throws with -EnableException" {
            # Without -Force, the running Agent makes the engine refuse to stop (exit code 3), so nothing changes state.
            $results = @(Stop-DbaService @splatInstance -Type Engine -WarningAction SilentlyContinue)
            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Failed"
            $results[0].Message | Should -BeLike "*dependent*"
            ($WarnVar.Message -join " ") | Should -BeLike "*dependent*"

            { Stop-DbaService @splatInstance -Type Engine -EnableException -WarningAction SilentlyContinue } | Should -Throw "*dependent*"
            @(Get-DbaService @splatInstance -Type Engine, Agent -EnableException | Where-Object State -ne "Running").Count | Should -Be 0
        }
    }
}