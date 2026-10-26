#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-ManagedComputerCommand",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # This is a private command, but a checkout has no dbatools.dat, so the psm1 exports
            # every function and plain Get-Command finds it. What still matters is that this stays
            # outside InModuleScope, where $TestConfig would not be readable in CI.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "ScriptBlock",
                "ArgumentList",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        BeforeAll {
            Mock -CommandName Test-ElevationRequirement -MockWith { $true }
            Mock -CommandName Resolve-DbaNetworkName -MockWith {
                [PSCustomObject]@{
                    IpAddress        = "10.0.0.1"
                    FullComputerName = "mockedserver.contoso.com"
                }
            }
        }

        Context "When the local connection attempt succeeds" {
            BeforeAll {
                Mock -CommandName Invoke-Command2 -MockWith { "LocalResult" }

                $localResult = Invoke-ManagedComputerCommand -ComputerName "mockedserver" -ScriptBlock { $wmi.Services } 3>$null 4>$null
            }

            It "Returns the result of the local connection attempt" {
                $localResult | Should -Be "LocalResult"
            }

            It "Does not try to connect remotely" {
                Should -Invoke -CommandName Invoke-Command2 -Times 1 -Exactly -Scope Context
            }
        }

        Context "When the local connection attempt fails but a remote connection attempt succeeds" {
            BeforeAll {
                $script:invokeCommandCount = 0
                Mock -CommandName Invoke-Command2 -MockWith {
                    $script:invokeCommandCount++
                    if ($script:invokeCommandCount -eq 1) {
                        throw "SQL Server WMI provider is not available on 10.0.0.1."
                    }
                    "RemoteResult"
                }

                $remoteResult = Invoke-ManagedComputerCommand -ComputerName "mockedserver" -ScriptBlock { $wmi.Services } 3>$null 4>$null
            }

            It "Returns the result of the remote connection attempt" {
                $remoteResult | Should -Be "RemoteResult"
            }

            It "Stops as soon as one version works" {
                # One local attempt plus one remote attempt with the highest version.
                Should -Invoke -CommandName Invoke-Command2 -Times 2 -Exactly -Scope Context
            }
        }

        Context "When all connection attempts fail" {
            BeforeAll {
                Mock -CommandName Invoke-Command2 -MockWith { throw "SQL Server WMI provider is not available on 10.0.0.1." }

                $thrownMessage = $null
                try {
                    $failedResult = Invoke-ManagedComputerCommand -ComputerName "mockedserver" -ScriptBlock { $wmi.Services } 3>$null 4>$null
                } catch {
                    $thrownMessage = $PSItem.Exception.Message
                }
            }

            It "Throws instead of silently returning nothing" {
                $thrownMessage | Should -BeLike "*Failed to connect to SQL WMI on mockedserver*"
            }

            It "Includes the reason of the last failed attempt in the message" {
                $thrownMessage | Should -BeLike "*SQL Server WMI provider is not available on 10.0.0.1.*"
            }

            It "Tries all versions from 17 down to 8" {
                # One local attempt plus ten remote attempts for the versions 17 to 8.
                Should -Invoke -CommandName Invoke-Command2 -Times 11 -Exactly -Scope Context
            }
        }
    }
}
