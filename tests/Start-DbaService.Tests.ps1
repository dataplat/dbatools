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
                { Start-DbaService -ComputerName $TestConfig.InstanceRestart -Type "Agent" -InstanceName "ThisIsInvalid" -EnableException } | Should -Throw "No SQL Server services found with current parameters."
            }
        }

        # A service that was already running or disabled got no CIM call and vanished from the output, without a row
        # or a warning (#10822).
        Context "Services that are already running or disabled" {
            BeforeAll {
                $splatInstance = @{
                    ComputerName = $TestConfig.InstanceRestart
                    InstanceName = $instanceName
                }
            }

            It "returns a row for a service that is already running" {
                $results = @(Start-DbaService @splatInstance -Type Engine)
                $WarnVar | Should -BeNullOrEmpty
                @($results).Count | Should -Be 1
                $results[0].State | Should -Be "Running"
                $results[0].Status | Should -Be "Successful"
                $results[0].Message | Should -BeLike "*already started*"
            }

            It "reports a disabled service as failed, and throws with -EnableException" {
                # The start mode of the Agent differs between the CI image (Manual) and the lab (Automatic), so it is
                # restored in the finally.
                $agent = Get-DbaService @splatInstance -Type Agent -EnableException
                $agentStartMode = $agent.StartMode
                try {
                    $null = Stop-DbaService @splatInstance -Type Agent -EnableException
                    $agent.ChangeStartMode("Disabled")

                    $results = @(Start-DbaService @splatInstance -Type Agent -WarningAction SilentlyContinue)
                    @($results).Count | Should -Be 1
                    $results[0].Status | Should -Be "Failed"
                    $results[0].Message | Should -BeLike "*disabled*"
                    $WarnVar | Should -BeLike "*disabled*"

                    { Start-DbaService @splatInstance -Type Agent -EnableException -WarningAction SilentlyContinue } | Should -Throw "*disabled*"
                } finally {
                    try {
                        $agent.ChangeStartMode($agentStartMode)
                    } finally {
                        $null = Start-DbaService @splatInstance -Type Agent
                    }
                }
            }
        }
    }
}