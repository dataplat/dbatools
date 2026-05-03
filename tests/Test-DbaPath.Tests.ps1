#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        BeforeAll {
            function New-MockTestDbaPathServer {
                $connectionContext = [PSCustomObject]@{
                }
                Add-Member -InputObject $connectionContext -Name ExecuteWithResults -MemberType ScriptMethod -Value {
                    param($Query)
                    throw "xp_fileexist failed"
                } -Force

                [PSCustomObject]@{
                    Name              = "sql1"
                    ServiceName       = "MSSQLSERVER"
                    ComputerName      = "sql1"
                    ConnectionContext = $connectionContext
                }
            }
        }

        Context "xp_fileexist execution failures" {
            BeforeAll {
                Mock Connect-DbaInstance {
                    New-MockTestDbaPathServer
                }
            }

            It "Returns false for a single path by default" {
                $result = Test-DbaPath -SqlInstance "sql1" -Path "C:\temp\file1.bak"

                $result | Should -Be $false
            }

            It "Returns false objects for array input by default" {
                $results = Test-DbaPath -SqlInstance "sql1" -Path @("C:\temp\file1.bak", "C:\temp\file2.bak")

                ($results | Measure-Object).Count | Should -Be 2
                ($results | Where-Object FilePath -eq "C:\temp\file1.bak").FileExists | Should -Be $false
                ($results | Where-Object FilePath -eq "C:\temp\file2.bak").IsContainer | Should -Be $false
            }

            It "Honors EnableException when xp_fileexist execution fails" {
                { Test-DbaPath -SqlInstance "sql1" -Path "C:\temp\file1.bak" -EnableException } | Should -Throw
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $trueTest = (Get-DbaDbFile -SqlInstance $TestConfig.InstanceMulti1 -Database master)[0].PhysicalName
        if ($trueTest.Length -eq 0) {
            $setupFailed = $true
        } else {
            $setupFailed = $false
        }
        $falseTest = "B:\FloppyDiskAreAwesome"
        $trueTestPath = [System.IO.Path]::GetDirectoryName($trueTest)
    }

    Context "Command actually works" {
        It "Should only return true if the path IS accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest
            $result | Should -Be $true
        }

        It "Should only return false if the path IS NOT accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $falseTest
            $result | Should -Be $false
        }

        It "Should return multiple results when passed multiple paths" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest, $falseTest
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $falseTest).FileExists | Should -Be $false
        }

        It "Should return multiple results when passed multiple instances" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Path $falseTest
            foreach ($result in $results) {
                $result.FileExists | Should -Be $false
            }
            ($results.SqlInstance | Sort-Object -Unique).Count | Should -Be 2
        }

        It "Should return PSCustomObject results when passed an array (even with one path)" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path @($trueTest)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
        }

        It "Should return PSCustomObject results indicating if the path is a file or a directory" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path @($trueTest, $trueTestPath)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $trueTestPath).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $trueTest).IsContainer | Should -Be $false
            ($results | Where-Object FilePath -eq $trueTestPath).IsContainer | Should -Be $true
        }
    }
}