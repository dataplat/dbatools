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
    BeforeAll {
        # Create unique temp path for this test run to avoid conflicts
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory -Force
    }

    AfterAll {
        # Clean up all downloaded files and temp directory
        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "When downloading diagnostic query scripts" {
        It "Should download diagnostic query scripts to specified path" {
            $results = Save-DbaDiagnosticQueryScript -Path $tempPath -OutVariable "global:dbatoolsciOutput"

            # basic retry logic in case the first download didn't get all of the files
            if ($null -eq $results -or $results.Count -eq 0) {
                Write-Message -Level Warning -Message "Retrying..."
                Start-Sleep -s 30
                $results = Save-DbaDiagnosticQueryScript -Path $tempPath -OutVariable "global:dbatoolsciOutput"
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
        }

        It "Should download .sql files" {
            $global:dbatoolsciOutput | ForEach-Object { $PSItem.Extension | Should -Be ".sql" }
        }

        It "Should save files to the specified path" {
            $global:dbatoolsciOutput | ForEach-Object { $PSItem.DirectoryName | Should -Be $tempPath }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.IO\.FileInfo"
        }
    }
}