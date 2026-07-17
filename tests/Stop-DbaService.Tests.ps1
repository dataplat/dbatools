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

            # Enumeration and CONTROL ride different channels (W3-084 discriminator): reads go
            # through Get-DbaCmObject's fallback chain, but the actual service control runs a
            # credential-less New-CimSession inside Invoke-Parallel workers. Where that second
            # hop is blocked, legacy and compiled BOTH warn "Multi-threaded execution returned
            # an error" and emit nothing - so probe the control channel exactly as the workers
            # open it and skip the control-effect scenarios when it is absent.
            $controlChannel = $false
            try {
                $controlSession = New-CimSession -ComputerName $computerName -OperationTimeoutSec 15 -ErrorAction Stop
                Remove-CimSession -CimSession $controlSession
                $controlChannel = $true
            } catch {
                $controlChannel = $false
            }
            $skipServiceControl = (-not $controlChannel)
        }

        It "stops some services" {
            if ($skipServiceControl) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "CIM control channel to InstanceRestart is unavailable from this runner"
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
                Set-ItResult -Skipped -Because "CIM control channel to InstanceRestart is unavailable from this runner"
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
