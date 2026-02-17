#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Join-DbaPath",
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
                "Child",
                "EnableException"
            )
            # NOTE: SqlCredential and EnableException are new in the C# cmdlet vs. the PS1.
            # This test requires the PS1 stub at public/Join-DbaPath.ps1 to be retired
            # and 'Join-DbaPath' added to CmdletsToExport in dbatools.library.psd1.
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "No SqlInstance - local path separator behavior" {
        It "Should join a path with no children and return a string" {
            $result = Join-DbaPath -Path "C:\temp"
            $result | Should -BeOfType [string]
            $result | Should -Be "C:\temp"
        }

        It "Should join a path with one child segment" {
            $result = Join-DbaPath -Path "C:\temp" -Child "subdir"
            $result | Should -BeOfType [string]
            $result | Should -Be "C:\temp\subdir"
        }

        It "Should join a path with multiple child segments" {
            $result = Join-DbaPath -Path "C:\temp" -Child "subdir", "nested"
            $result | Should -BeOfType [string]
            $result | Should -Be "C:\temp\subdir\nested"
        }

        It "Should accept child segments via ValueFromRemainingArguments (ChildPath alias)" {
            $result = Join-DbaPath -Path "C:\temp" "subdir" "nested"
            $result | Should -BeOfType [string]
            $result | Should -Be "C:\temp\subdir\nested"
        }

        It "Should normalize forward slashes to backslashes on Windows" {
            $result = Join-DbaPath -Path "C:/temp/foo"
            $result | Should -Be "C:\temp\foo"
        }
    }

    Context "With SqlInstance targeting Windows SQL Server" {
        It "Should return a string with backslash separators for Windows instance" {
            $result = Join-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path "C:\temp" -Child "backups" -OutVariable "global:dbatoolsciOutput"
            $result | Should -BeOfType [string]
            $result | Should -Match "\\"
        }

        It "Should join multiple children with backslash for Windows instance" {
            $result = Join-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path "C:\temp" -Child "backups", "daily"
            $result | Should -BeOfType [string]
            $result | Should -Be "C:\temp\backups\daily"
        }
    }

    if (Test-NetConnection -ComputerName localhost -Port 14331 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TcpTestSucceeded) {
        Context "With SqlInstance targeting Linux SQL Server" {
            BeforeAll {
                $securePassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
                $sqlCred = New-Object System.Management.Automation.PSCredential ("sqladmin", $securePassword)
            }

            It "Should return a string with forward slash separators for Linux instance" {
                $result = Join-DbaPath -SqlInstance "localhost,14331" -SqlCredential $sqlCred -Path "/var/opt/mssql" -Child "backups"
                $result | Should -BeOfType [string]
                $result | Should -Match "/"
                $result | Should -Not -Match "\\"
            }

            It "Should normalize backslashes to forward slashes for Linux instance" {
                $result = Join-DbaPath -SqlInstance "localhost,14331" -SqlCredential $sqlCred -Path "C:\temp" -Child "backups"
                $result | Should -BeOfType [string]
                $result | Should -Match "/"
                $result | Should -Not -Match "\\"
            }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a System.String type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [string]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.String"
        }
    }
}
