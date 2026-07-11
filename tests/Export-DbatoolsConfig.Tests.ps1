#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Module",
                "Name",
                "Config",
                "ModuleName",
                "ModuleVersion",
                "Scope",
                "OutPath",
                "SkipUnchanged",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>

Describe "$CommandName compiled-cmdlet characterization" -Tag IntegrationTests {
    BeforeAll {
        # Characterization scenarios for the migration gate (which executes -Tag IntegrationTests):
        # Export-DbatoolsConfig is pure config/file work, so these run everywhere with no SQL
        # instance. Expected values were captured against the current script function on both
        # editions before the compiled-cmdlet flip. Session-scope config mutations are restored.
        $exportWork = Join-Path ([System.IO.Path]::GetTempPath()) "dbatoolsci-exportconfig-$(Get-Random)"
        $null = New-Item -Path $exportWork -ItemType Directory
        $originalSeparator = Get-DbatoolsConfigValue -FullName "formatting.batchseparator"
    }

    AfterAll {
        Set-DbatoolsConfig -FullName "formatting.batchseparator" -Value $originalSeparator
        Remove-Item -Path $exportWork -Recurse -ErrorAction SilentlyContinue
    }

    Context "File exports" {
        It "Exports a single FullName setting as one naked json object and emits nothing" {
            $outFile = Join-Path $exportWork "single.json"
            $result = Export-DbatoolsConfig -FullName "formatting.batchseparator" -OutPath $outFile
            @($result).Count | Should -Be 0
            $parsed = Get-Content -Path $outFile -Raw | ConvertFrom-Json
            @($parsed).Count | Should -Be 1
            $parsed.FullName | Should -Be "formatting.batchseparator"
            $parsed.PSObject.Properties.Name | Should -Contain "Value"
            $parsed.PSObject.Properties.Name | Should -Contain "Version"
            $parsed.PSObject.Properties.Name | Should -Contain "Type"
        }

        It "Exports a whole module and matches the live config inventory" {
            $outFile = Join-Path $exportWork "module.json"
            $null = Export-DbatoolsConfig -Module formatting -OutPath $outFile
            # Assign first, then pipe to enumerate: 5.1 ConvertFrom-Json emits a json array as
            # ONE object while 7 enumerates it - piping the assigned value counts identically.
            $parsedRaw = Get-Content -Path $outFile -Raw | ConvertFrom-Json
            $parsed = @($parsedRaw | ForEach-Object { $PSItem })
            $live = @(Get-DbatoolsConfig -Module formatting)
            $parsed.Count | Should -Be $live.Count
            $parsed.FullName | Should -Contain "formatting.batchseparator"
        }

        It "Exports piped Config objects" {
            $outFile = Join-Path $exportWork "piped.json"
            $null = Get-DbatoolsConfig -Module formatting | Export-DbatoolsConfig -OutPath $outFile
            $parsedRaw = Get-Content -Path $outFile -Raw | ConvertFrom-Json
            $parsed = @($parsedRaw | ForEach-Object { $PSItem })
            $live = @(Get-DbatoolsConfig -Module formatting)
            $parsed.Count | Should -Be $live.Count
        }

        It "SkipUnchanged keeps only modified settings" {
            Set-DbatoolsConfig -FullName "formatting.batchseparator" -Value "GOGO"
            $outFile = Join-Path $exportWork "changed.json"
            $null = Export-DbatoolsConfig -Module formatting -OutPath $outFile -SkipUnchanged
            $parsedRaw = Get-Content -Path $outFile -Raw | ConvertFrom-Json
            $parsed = @($parsedRaw | ForEach-Object { $PSItem })
            $parsed.Count | Should -Be 1
            $parsed[0].FullName | Should -Be "formatting.batchseparator"
            $parsed[0].Value | Should -Be "GOGO"
            Set-DbatoolsConfig -FullName "formatting.batchseparator" -Value $originalSeparator
        }
    }

    Context "Failure contracts" {
        It "Refuses a registry scope for module cache exports" {
            $result = Export-DbatoolsConfig -ModuleName "dbatoolscitest" -Scope UserDefault -WarningVariable charWarn -WarningAction SilentlyContinue
            @($result).Count | Should -Be 0
            $charWarn | Should -Match "Cannot export modulecache to registry"
        }

        It "Throws on a registry scope when EnableException is set" {
            { Export-DbatoolsConfig -ModuleName "dbatoolscitest" -Scope UserDefault -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Cannot export modulecache to registry*"
        }

        It "Warns when the export file cannot be written" {
            $result = Export-DbatoolsConfig -FullName "formatting.batchseparator" -OutPath "Q:\nosuch\dir\x.json" -WarningVariable charWarn -WarningAction SilentlyContinue 2>$null
            @($result).Count | Should -Be 0
            $charWarn | Should -Match "Failed to export to file"
        }
    }
}