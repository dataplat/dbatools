#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Restart-DbaService",
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
    Context "Command actually works" {
        BeforeAll {
            $instanceName = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart).ServiceName
        }

        It "restarts some services" {
            $services = Restart-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Running"
                $service.Status | Should -Be "Successful"
            }
        }

        It "restarts some services through pipeline" {
            $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine | Restart-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Running"
                $service.Status | Should -Be "Successful"
            }
        }
    }

    # A service that was already stopped vanished from the output of the stop step, so Restart-DbaService never started it
    # and wrote no row and no warning (#10822). The tests change the state and the start mode of the Agent, so each one
    # restores them in a finally: the CI image sets the Agent to Manual, the lab to Automatic.
    Context "Services that are stopped or disabled" {
        BeforeAll {
            $splatInstance = @{
                ComputerName = $TestConfig.InstanceRestart
                InstanceName = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart).ServiceName
            }
        }

        It "starts a stopped engine, and the Agent with it when the Agent starts automatically" {
            $agent = Get-DbaService @splatInstance -Type Agent -EnableException
            $agentStartMode = $agent.StartMode
            try {
                if ($agentStartMode -ne "Automatic") {
                    $agent.ChangeStartMode("Automatic")
                }
                $null = Stop-DbaService @splatInstance -Type Engine -Force -EnableException

                $results = @(Restart-DbaService @splatInstance -Type Engine -Force)
                $WarnVar | Should -BeNullOrEmpty
                @($results | Where-Object ServiceType -eq "Engine").Count | Should -Be 1
                @($results | Where-Object ServiceType -eq "Agent").Count | Should -Be 1
                foreach ($result in $results) {
                    $result.State | Should -Be "Running"
                    $result.Status | Should -Be "Successful"
                }
                @(Get-DbaService @splatInstance -Type Engine, Agent -EnableException | Where-Object State -ne "Running").Count | Should -Be 0
            } finally {
                # The services are started even when the start mode cannot be restored, so that the engine is not left
                # down for the next test file.
                try {
                    if ($agentStartMode -ne "Automatic") {
                        $agent.ChangeStartMode($agentStartMode)
                    }
                } finally {
                    $null = Start-DbaService @splatInstance -Type Engine, Agent
                }
            }
        }

        It "starts a stopped engine without the Agent when the Agent does not start automatically" {
            $agent = Get-DbaService @splatInstance -Type Agent -EnableException
            $agentStartMode = $agent.StartMode
            try {
                if ($agentStartMode -ne "Manual") {
                    $agent.ChangeStartMode("Manual")
                }
                $null = Stop-DbaService @splatInstance -Type Engine -Force -EnableException

                $results = @(Restart-DbaService @splatInstance -Type Engine -Force)
                $WarnVar | Should -BeNullOrEmpty
                @($results | Where-Object ServiceType -eq "Agent").Count | Should -Be 0
                $engineResult = $results | Where-Object ServiceType -eq "Engine"
                $engineResult.State | Should -Be "Running"
                $engineResult.Status | Should -Be "Successful"
                (Get-DbaService @splatInstance -Type Agent -EnableException).State | Should -Be "Stopped"
            } finally {
                try {
                    if ($agentStartMode -ne "Manual") {
                        $agent.ChangeStartMode($agentStartMode)
                    }
                } finally {
                    $null = Start-DbaService @splatInstance -Type Engine, Agent
                }
            }
        }

        It "leaves a stopped Agent stopped when it restarts the running engine with -Force" {
            try {
                $null = Stop-DbaService @splatInstance -Type Agent -EnableException

                $results = @(Restart-DbaService @splatInstance -Type Engine -Force)
                $WarnVar | Should -BeNullOrEmpty
                @($results | Where-Object ServiceType -eq "Agent").Count | Should -Be 0
                $engineResult = $results | Where-Object ServiceType -eq "Engine"
                $engineResult.State | Should -Be "Running"
                $engineResult.Status | Should -Be "Successful"
                (Get-DbaService @splatInstance -Type Agent -EnableException).State | Should -Be "Stopped"
            } finally {
                $null = Start-DbaService @splatInstance -Type Agent
            }
        }

        It "reports a disabled service as failed, and throws with -EnableException" {
            $agent = Get-DbaService @splatInstance -Type Agent -EnableException
            $agentStartMode = $agent.StartMode
            try {
                $null = Stop-DbaService @splatInstance -Type Agent -EnableException
                $agent.ChangeStartMode("Disabled")

                $results = @(Restart-DbaService @splatInstance -Type Agent -WarningAction SilentlyContinue)
                @($results).Count | Should -Be 1
                $results[0].Status | Should -Be "Failed"
                $results[0].Message | Should -BeLike "*disabled*"
                $WarnVar | Should -BeLike "*disabled*"

                { Restart-DbaService @splatInstance -Type Agent -EnableException -WarningAction SilentlyContinue } | Should -Throw "*disabled*"
            } finally {
                try {
                    $agent.ChangeStartMode($agentStartMode)
                } finally {
                    $null = Start-DbaService @splatInstance -Type Agent
                }
            }
        }

        It "reports an engine that refuses to stop as failed, and throws with -EnableException" {
            # Without -Force, the running Agent makes the engine refuse to stop (exit code 3), so nothing changes state.
            $results = @(Restart-DbaService @splatInstance -Type Engine -WarningAction SilentlyContinue)
            @($results).Count | Should -Be 1
            $results[0].Status | Should -Be "Failed"
            $results[0].Message | Should -BeLike "*dependent*"
            ($WarnVar.Message -join " ") | Should -BeLike "*dependent*"

            { Restart-DbaService @splatInstance -Type Engine -EnableException -WarningAction SilentlyContinue } | Should -Throw "*dependent*"
            @(Get-DbaService @splatInstance -Type Engine, Agent -EnableException | Where-Object State -ne "Running").Count | Should -Be 0
        }
    }
}