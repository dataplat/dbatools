#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaHideInstance",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When disabling hide instance" {
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # No specific cleanup needed for this test

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns result with HideInstance set to false" {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $hideInstanceResults = Disable-DbaHideInstance -SqlInstance $TestConfig.InstanceSingle

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $hideInstanceResults.HideInstance | Should -BeFalse
        }
    }

    Context "When a later pipeline record cannot resolve its own instance name" {
        BeforeAll {
            # $instanceName is assigned inside the process block but never reset per record: when
            # $sqlwmi.DisplayName is null the .Replace() throws, the catch swallows it, and the
            # variable keeps the previous record's value. A single-record leg cannot observe this
            # cross-record persistence, and it is not reproducible against a live instance (a real
            # WMI service always has a DisplayName). The mock drives two piped records where the
            # second record's service exposes a DisplayName that matches the source's own
            # "SQL Server (name)" filter on first read but is null when .Replace() reads it again -
            # so the second record retains the first record's instance name.
            $computerPart = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $recordOne = [DbaInstanceParameter]"$computerPart\HideFirst"
            $recordTwo = [DbaInstanceParameter]"$computerPart\HideSecond"

            Mock Test-ElevationRequirement { $true } -ModuleName dbatools

            Mock Invoke-ManagedComputerCommand -ModuleName dbatools -MockWith {
                param($ComputerName, $Credential, $ScriptBlock, $EnableException)

                # Fresh objects on every call so the first record's filter pass over the second
                # service does not consume its one-shot DisplayName read.
                $serviceOne = [PSCustomObject]@{
                    DisplayName        = "SQL Server (HideFirst)"
                    AdvancedProperties = @(
                        [PSCustomObject]@{ Name = "REGROOT"; Value = "Software\Microsoft\Microsoft SQL Server\MSSQL15.HideFirst" }
                        [PSCustomObject]@{ Name = "VSNAME"; Value = "HideFirst" }
                    )
                    ServiceAccount     = "NT Service\MSSQLSERVER"
                }

                $serviceTwo = [PSCustomObject]@{
                    AdvancedProperties = @(
                        [PSCustomObject]@{ Name = "REGROOT"; Value = "Software\Microsoft\Microsoft SQL Server\MSSQL15.HideSecond" }
                        [PSCustomObject]@{ Name = "VSNAME"; Value = "HideSecond" }
                    )
                    ServiceAccount     = "NT Service\MSSQL`$HideSecond"
                    DisplayNameReads   = 0
                }
                # First read (the source's Where-Object filter) returns the matching name; the
                # second read (the source's .Replace call) returns null so .Replace throws.
                $serviceTwo | Add-Member -MemberType ScriptProperty -Name DisplayName -Value {
                    $this.DisplayNameReads++
                    if ($this.DisplayNameReads -eq 1) { "SQL Server (HideSecond)" } else { $null }
                }

                $serviceOne, $serviceTwo
            }

            # Echo the instance name the command passed into the remote registry scriptblock
            # (ArgumentList = REGROOT, VSNAME, InstanceName) without touching the registry.
            Mock Invoke-Command2 -ModuleName dbatools -MockWith {
                param($ComputerName, $Credential, $ArgumentList, $ScriptBlock, $ErrorAction)
                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    InstanceName = $ArgumentList[2]
                    SqlInstance  = $ArgumentList[1]
                    HideInstance = $false
                }
            }

            $crossRecordResult = $recordOne, $recordTwo | Disable-DbaHideInstance -Confirm:$false
        }

        It "Emits one object per piped record" {
            @($crossRecordResult).Count | Should -Be 2
        }

        It "The first record reports its own instance name" {
            @($crossRecordResult)[0].InstanceName | Should -Be "HideFirst"
        }

        It "The second record retains the first record's instance name" {
            @($crossRecordResult)[1].InstanceName | Should -Be "HideFirst"
        }
    }
}