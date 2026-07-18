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

            # Enumeration and CONTROL are different paths (W3-084 discriminator): on some seats
            # the full control path (input prep -> Update-ServiceStatus -> Invoke-Parallel
            # workers) dies with the world-independent signature "Multi-threaded execution
            # returned an error" + empty output - legacy function and compiled cmdlet
            # IDENTICALLY (4-leg proof 2026-07-17). Probe it non-mutatingly: Start on an
            # already-running service exercises the whole path through the workers' type
            # check and emits "already running/Successful" on healthy seats; on broken seats
            # it emits nothing with that warning. Skip the control-effect scenarios there.
            $controlProbeWarn = @()
            $controlProbeOut = @(Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent -WarningAction SilentlyContinue -WarningVariable controlProbeWarn)
            $skipServiceControl = ($controlProbeOut.Count -eq 0) -and (($controlProbeWarn -join " ") -match "Multi-threaded execution returned an error")
        }

        It "stops some services" {
            if ($skipServiceControl) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the service-control path to InstanceRestart is unavailable from this runner"
                return
            }
            $services = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Stopped"
                $service.Status | Should -Be "Successful"
            }

            $null = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
        }

        It "stops specific services based on instance name through pipeline" {
            if ($skipServiceControl) {
                Set-ItResult -Skipped -Because "the service-control path to InstanceRestart is unavailable from this runner"
                return
            }
            $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine | Stop-DbaService -Force
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Stopped"
                $service.Status | Should -Be "Successful"
            }

            $null = Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Engine, Agent
        }
    }

    Context "When no matching services are found" {
        # Environment-independent characterization: an unresolvable computer produces the
        # command's no-services warning and no output (always executes, W1-094 law).
        It "Warns that no services were found" {
            $noServiceResults = Stop-DbaService -ComputerName "dbatoolsci-nohost-$(Get-Random)" -WarningAction SilentlyContinue -WarningVariable stopWarning
            $noServiceResults | Should -BeNullOrEmpty
            $stopWarning | Should -Not -BeNullOrEmpty
        }
    }
}
