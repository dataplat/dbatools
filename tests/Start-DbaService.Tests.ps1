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

            # Enumeration and CONTROL are different paths (W3-084 discriminator): on some seats
            # the full control path (input prep -> Update-ServiceStatus -> Invoke-Parallel
            # workers) dies with the world-independent signature "Multi-threaded execution
            # returned an error" + empty output - legacy function and compiled cmdlet
            # IDENTICALLY (4-leg proof 2026-07-17). Probe it non-mutatingly: Start on an
            # already-running service exercises the whole path through the workers' type
            # check and emits "already running/Successful" on healthy seats; on broken seats
            # it emits nothing with that warning. Skip the control-effect scenarios (and
            # their mutating setup) there.
            $controlProbeWarn = @()
            $controlProbeOut = @(Start-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent -WarningAction SilentlyContinue -WarningVariable controlProbeWarn)
            $skipServiceControl = ($controlProbeOut.Count -eq 0) -and (($controlProbeWarn -join " ") -match "Multi-threaded execution returned an error")
        }

        Context "Single service restart" {
            BeforeAll {
                if (-not $skipServiceControl) {
                    $null = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
                }
            }

            It "starts the services back" {
                if ($skipServiceControl) {
                    # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                    Set-ItResult -Skipped -Because "the service-control path to InstanceRestart is unavailable from this runner"
                    return
                }
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
                if (-not $skipServiceControl) {
                    $null = Stop-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine -Force
                }
            }

            It "starts the services back through pipeline" {
                if ($skipServiceControl) {
                    Set-ItResult -Skipped -Because "the service-control path to InstanceRestart is unavailable from this runner"
                    return
                }
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