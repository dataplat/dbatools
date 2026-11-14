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
                # The mocked server throws on purpose, so the command warns. That warning is the
                # subject of its own test below and is silenced here, because a test run must not
                # print warnings - an unexpected one is the only sign that something went wrong.
                $result = Test-DbaPath -SqlInstance "sql1" -Path "C:\temp\file1.bak" -WarningAction SilentlyContinue

                $result | Should -Be $false
            }

            It "Returns false objects for array input by default" {
                $results = Test-DbaPath -SqlInstance "sql1" -Path @("C:\temp\file1.bak", "C:\temp\file2.bak") -WarningAction SilentlyContinue

                ($results | Measure-Object).Count | Should -Be 2
                ($results | Where-Object FilePath -eq "C:\temp\file1.bak").FileExists | Should -Be $false
                ($results | Where-Object FilePath -eq "C:\temp\file2.bak").IsContainer | Should -Be $false
            }

            It "Honors EnableException when xp_fileexist execution fails" {
                { Test-DbaPath -SqlInstance "sql1" -Path "C:\temp\file1.bak" -EnableException } | Should -Throw -ExpectedMessage "*xp_fileexist*"
            }

            It "Warns that existence could not be determined instead of silently reporting not found" {
                # The execution failure used to be demoted to Verbose, making a batch-level
                # failure indistinguishable from files that genuinely do not exist (#10512)
                $null = Test-DbaPath -SqlInstance "sql1" -Path "C:\temp\file1.bak" -WarningVariable warnvar 3> $null

                $warnvar | Should -BeLike "*could not be determined*"
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

    Context "Logins without sysadmin and paths that need quoting (#10835)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Before SQL Server 2017 there is only xp_fileexist, which answers only for members of sysadmin
            $supportsFileExistsDmf = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1).VersionMajor -ge 14

            # A new login is only a member of public
            $loginName = "dbatoolsci_testpath_$(Get-Random)"
            $loginPassword = ConvertTo-SecureString -String "dbatools.IO$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $loginName -SecurePassword $loginPassword
            $loginCredential = New-Object System.Management.Automation.PSCredential($loginName, $loginPassword)

            # The instance checks these folders, so they go to the temp folder that the instance can reach.
            # The name of the second one is built from code points, because Windows PowerShell reads a test
            # file without byte order mark in the ANSI code page.
            $quoteFolder = "$($TestConfig.Temp)\dbatoolsci_O'Brien_$(Get-Random)"
            $unicodeFolder = "$($TestConfig.Temp)\dbatoolsci_M$([char]0x00FC)ller_$([char]0x65E5)$([char]0x672C)_$(Get-Random)"
            $null = New-Item -Path $quoteFolder, $unicodeFolder -ItemType Directory

            # sys.dm_os_file_exists fails for a share on a host that does not exist, xp_fileexist answers "not found"
            $unreachablePath = "\\dbatoolsci-nohost-$(Get-Random)\share\file.bak"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Force, because Test-DbaPath leaves the session of the login in the connection pool
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $loginName -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $quoteFolder, $unicodeFolder -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Finds an existing file for a login that is not sysadmin" {
            if (-not $supportsFileExistsDmf) {
                Set-ItResult -Skipped -Because "xp_fileexist answers only for members of sysadmin before SQL Server 2017"
            }
            $result = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $loginCredential -Path $trueTest
            $result | Should -Be $true
        }

        It "Finds a path with a quote without failing the other paths of the batch" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $quoteFolder, $trueTest
            ($results | Where-Object FilePath -eq $quoteFolder).IsContainer | Should -Be $true
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Finds a path with characters outside the code page of the instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $unicodeFolder
            $result | Should -Be $true
        }

        It "Reports an unreachable share as not found without failing the other paths of the batch" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $unreachablePath, $trueTest
            ($results | Where-Object FilePath -eq $unreachablePath).FileExists | Should -Be $false
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}