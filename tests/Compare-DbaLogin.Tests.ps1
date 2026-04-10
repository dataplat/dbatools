#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Compare-DbaLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Login",
                "ExcludeLogin",
                "ExcludeSystemLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Destination connection failures" {
            BeforeEach {
                function New-MockCompareDbaLoginInstance {
                    param(
                        [string]$Name
                    )

                    $instance = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Name
                    $instance | Add-Member -NotePropertyName Name -NotePropertyValue $Name -Force
                    $instance
                }

                Mock Test-FunctionInterrupt { $false }
                Mock Stop-Function { }
                Mock Connect-DbaInstance {
                    switch ("$SqlInstance") {
                        "source1" {
                            New-MockCompareDbaLoginInstance -Name "source1"
                        }
                        "dest1" {
                            New-MockCompareDbaLoginInstance -Name "dest1"
                        }
                        "dest2" {
                            throw "dest2 unavailable"
                        }
                    }
                }
                Mock Get-DbaLogin {
                    switch ($SqlInstance.Name) {
                        "source1" {
                            [PSCustomObject]@{
                                Name      = "login1"
                                LoginType = "SqlLogin"
                            }
                        }
                        "dest1" {
                            [PSCustomObject]@{
                                Name      = "login1"
                                LoginType = "SqlLogin"
                            }
                        }
                        default {
                            throw "Unexpected Get-DbaLogin call for $($SqlInstance.Name)"
                        }
                    }
                }
            }

            It "skips failed destinations without reusing the previous connection" {
                $result = Compare-DbaLogin -Source "source1" -Destination "dest1", "dest2"

                $result.Count | Should -Be 1
                $result.SourceServer | Should -Be "source1"
                $result.DestinationServer | Should -Be "dest1"
                Should -Invoke Get-DbaLogin -Times 2 -Exactly
                Should -Invoke Stop-Function -Times 1 -Exactly -ParameterFilter {
                    $Message -eq "Failure connecting to dest2" -and $Continue
                }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $loginName = "dbatoolsci_comparelogin_$(Get-Random)"

        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $loginName -SecurePassword (ConvertTo-SecureString "Password1234!" -AsPlainText -Force)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $loginName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When comparing logins between instances" {
        It "Returns a result with a DestinationOnly login" {
            $result = Compare-DbaLogin -Source $TestConfig.InstanceMulti1 -Destination $TestConfig.InstanceMulti2 -Login $loginName
            $result | Should -Not -BeNullOrEmpty
            $result.LoginName | Should -Be $loginName
            $result.Status | Should -Be "DestinationOnly"
        }
    }
}
