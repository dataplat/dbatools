#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaExtendedProtection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Value",
                "AcceptedSpn",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Accepted SPNs" {
            BeforeEach {
                $script:acceptedSpnValue = "existing"
                $script:extendedProtectionValue = 1
                Mock Resolve-DbaNetworkName {
                    [PSCustomObject]@{ FullComputerName = "sql1" }
                }
                Mock Invoke-ManagedComputerCommand {
                    [PSCustomObject]@{
                        DisplayName        = "SQL Server (MSSQLSERVER)"
                        ServiceAccount     = "NT Service\MSSQLSERVER"
                        AdvancedProperties = @(
                            [PSCustomObject]@{ Name = "REGROOT"; Value = "Software\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER" },
                            [PSCustomObject]@{ Name = "VSNAME"; Value = "sql1" }
                        )
                    }
                }
                Mock Set-ItemProperty {
                    if ($Name -eq "AcceptedSPNs") {
                        $script:acceptedSpnValue = $Value
                    }
                    if ($Name -eq "ExtendedProtection") {
                        $script:extendedProtectionValue = $Value
                    }
                }
                Mock Get-ItemProperty {
                    [PSCustomObject]@{
                        ExtendedProtection = $script:extendedProtectionValue
                        AcceptedSPNs       = $script:acceptedSpnValue
                    }
                }
                Mock Invoke-Command2 {
                    & $ScriptBlock @ArgumentList
                }
                Mock Test-ShouldProcess { $true }
                Mock Stop-Function { throw $Message }
            }

            It "writes accepted SPNs as a semicolon-delimited registry value" {
                $acceptedSpns = @("MSSQLSvc/sql1.domain.local:1433", "MSSQLSvc/sql1:1433")

                $result = Set-DbaExtendedProtection -SqlInstance "sql1" -Value Required -AcceptedSpn $acceptedSpns -Confirm:$false

                $script:acceptedSpnValue | Should -Be ($acceptedSpns -join ";")
                $result.AcceptedSpns | Should -Be $acceptedSpns
            }

            It "leaves accepted SPNs unchanged when AcceptedSpn is omitted" {
                $null = Set-DbaExtendedProtection -SqlInstance "sql1" -Value Required -Confirm:$false

                Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq "AcceptedSPNs" } -Exactly 0 -Scope It
            }

            It "leaves Extended Protection unchanged when only AcceptedSpn is supplied" {
                $null = Set-DbaExtendedProtection -SqlInstance "sql1" -AcceptedSpn "MSSQLSvc/sql1:1433" -Confirm:$false

                $script:extendedProtectionValue | Should -Be 1
                Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq "ExtendedProtection" } -Exactly 0 -Scope It
            }

            It "clears accepted SPNs when an empty string is supplied" {
                $null = Set-DbaExtendedProtection -SqlInstance "sql1" -AcceptedSpn "" -Confirm:$false

                $script:acceptedSpnValue | Should -Be ""
                Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq "AcceptedSPNs" -and $Value -eq "" } -Exactly 1 -Scope It
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Default set and returns '0 - Off'" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -EnableException
            $results.ExtendedProtection | Should -Be "0 - Off"
        }
    }
    Context "Command works when passed different values" {
        BeforeAll {
            Mock Test-ShouldProcess { $false } -ModuleName dbatools
            Mock Invoke-ManagedComputerCommand -MockWith {
                param (
                    $ComputerName,
                    $Credential,
                    $ScriptBlock,
                    $EnableException
                )
                $server = [DbaInstanceParameter[]]$TestConfig.InstanceSingle
                @{
                    DisplayName        = "SQL Server ($($server.InstanceName))"
                    AdvancedProperties = @(
                        @{
                            Name  = "REGROOT"
                            Value = "Software\Microsoft\Microsoft SQL Server\MSSQL10_50.SQL2008R2SP2"
                        }
                    )
                }
            } -ModuleName dbatools
        }
        It "Set explicitly to '0 - Off' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value Off -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 0"
        }
        It "Set explicitly to '0 - Off' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value 0 -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 0"
        }

        It "Set explicitly to '1 - Allowed' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value Allowed -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 1"
        }
        It "Set explicitly to '1 - Allowed' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value 1 -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 1"
        }

        It "Set explicitly to '2 - Required' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value Required -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 2"
        }
        It "Set explicitly to '2 - Required' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value 2 -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 2"
        }
    }
}
