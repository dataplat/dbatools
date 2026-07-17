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

            # Enumeration and CONTROL ride different channels (W3-084 discriminator): reads go
            # through Get-DbaCmObject's fallback chain, but the actual service control runs a
            # credential-less New-CimSession inside Invoke-Parallel workers. Where that second
            # hop is blocked, legacy and compiled BOTH warn "Multi-threaded execution returned
            # an error" and emit nothing - so probe the control channel exactly as the workers
            # open it and skip the control-effect scenarios (and their mutating setup) when it
            # is absent.
            $controlChannel = $false
            try {
                $controlSession = New-CimSession -ComputerName $computerName -OperationTimeoutSec 15 -ErrorAction Stop
                Remove-CimSession -CimSession $controlSession
                $controlChannel = $true
            } catch {
                $controlChannel = $false
            }
            $skipServiceControl = (-not $controlChannel)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
                    Set-ItResult -Skipped -Because "CIM control channel to InstanceRestart is unavailable from this runner"
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
                    Set-ItResult -Skipped -Because "CIM control channel to InstanceRestart is unavailable from this runner"
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