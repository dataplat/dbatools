#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaDiagnosticQueryScript",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Downloaded script handling" {
        BeforeEach {
            Mock Invoke-TlsWebRequest -ModuleName dbatools {
                $arguments = @($args)
                $outFileIndex = [Array]::IndexOf($arguments, "-OutFile")

                if ($outFileIndex -ge 0) {
                    [System.IO.File]::WriteAllText($arguments[$outFileIndex + 1], "SELECT 1;")
                    return
                }

                [pscustomobject]@{
                    Content = '<a href="https://www.dropbox.com/scl/fi/abc123/SQL-Server-2022-Diagnostic-Information-Queries.sql?rlkey=test&amp;dl=0">SQL Server 2022</a>'
                }
            }
        }

        It "discovers, downloads, names, and returns a diagnostic query file" {
            $result = Save-DbaDiagnosticQueryScript -Path $TestDrive

            $result | Should -BeOfType System.IO.FileInfo
            $result.Name | Should -Be "SQLServerDiagnosticQueries_2022.sql"
            $result.FullName | Should -Be (Join-Path $TestDrive "SQLServerDiagnosticQueries_2022.sql")
            [System.IO.File]::ReadAllText($result.FullName) | Should -Be "SELECT 1;"
            Should -Invoke Invoke-TlsWebRequest -ModuleName dbatools -Times 2 -Exactly
        }
    }
}
