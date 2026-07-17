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
            # Harness honesty: the restart scenarios need WMI/DCOM service access to
            # $TestConfig.InstanceRestart from the test runner. In environments where that
            # channel is blocked (guest-to-guest DCOM), Get-DbaService returns nothing and
            # the restart assertions can only fail for environmental reasons - skip them
            # instead (the warning characterization below still executes, so the run is
            # never empty per the W1-094 law).
            $restartServices = @()
            try {
                $instanceName = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart).ServiceName
                $restartServices = @(Get-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent -EnableException)
            } catch {
                $restartServices = @()
            }

            # Enumeration and CONTROL ride different channels (W3-084 discriminator): reads go
            # through Get-DbaCmObject's fallback chain, but the actual service control runs a
            # credential-less New-CimSession inside Invoke-Parallel workers. Where that second
            # hop is blocked, legacy and compiled BOTH warn "Multi-threaded execution returned
            # an error" and emit nothing - so probe the control channel exactly as the workers
            # open it and skip the control-effect scenarios when it is absent.
            $controlChannel = $false
            if ($restartServices.Count -gt 0) {
                try {
                    $controlSession = New-CimSession -ComputerName $restartServices[0].ComputerName -OperationTimeoutSec 15 -ErrorAction Stop
                    Remove-CimSession -CimSession $controlSession
                    $controlChannel = $true
                } catch {
                    $controlChannel = $false
                }
            }
            $skipRestart = ($restartServices.Count -eq 0) -or (-not $controlChannel)
        }

        It "restarts some services" {
            if ($skipRestart) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "service enumeration or CIM control channel to InstanceRestart is unavailable from this runner"
                return
            }
            $services = Restart-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Running"
                $service.Status | Should -Be "Successful"
            }
        }

        It "restarts some services through pipeline" {
            if ($skipRestart) {
                Set-ItResult -Skipped -Because "service enumeration or CIM control channel to InstanceRestart is unavailable from this runner"
                return
            }
            $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine | Restart-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Running"
                $service.Status | Should -Be "Successful"
            }
        }
    }

    Context "When no matching services are found" {
        # Environment-independent characterization: an unresolvable computer produces the
        # command's no-services warning and no output (always executes, W1-094 law).
        It "Warns that no services were found" {
            $noServiceResults = Restart-DbaService -ComputerName "dbatoolsci-nohost-$(Get-Random)" -WarningAction SilentlyContinue -WarningVariable restartWarning
            $noServiceResults | Should -BeNullOrEmpty
            $restartWarning | Should -Not -BeNullOrEmpty
        }
    }
}