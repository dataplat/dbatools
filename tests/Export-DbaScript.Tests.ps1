#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Export-DbaScript",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "ScriptingOptionsObject",
                "Path",
                "FilePath",
                "Encoding",
                "BatchSeparator",
                "NoPrefix",
                "Passthru",
                "NoClobber",
                "Append",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Works as expected" {
        BeforeAll {
            # Create unique temp path for this test run to avoid conflicts
            $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $testFile = "$tempPath\msdb.txt"
            $null = New-Item -Path $tempPath -ItemType Directory -Force
        }

        AfterAll {
            # Clean up temp files
            Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Should export some text matching create table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results -match "CREATE TABLE" | Should -Be $true
        }

        It "Should include BatchSeparator based on the Formatting.BatchSeparator configuration" {
            $batchSeparator = Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            ($results -join "`n") | Should -Match [regex]::Escape($batchSeparator)
        }

        It "Should include the defined BatchSeparator" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            ($results -join "`n") | Should -Match "MakeItSo"
        }

        It "Should not accept non-SMO objects" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $null = [PSCustomObject]@{ Invalid = $true } | Export-DbaScript -WarningVariable invalid -WarningAction SilentlyContinue
            ($invalid -join "`n") | Should -Match "not a SQL Management Object"
        }

        It "Should not append when using NoPrefix (#7455)" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath $testFile
            $linecount1 = (Get-Content $testFile).Count
            $null = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath $testFile
            $linecount2 = (Get-Content $testFile).Count
            $linecount1 | Should -Be $linecount2
            $null = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath $testFile -Append
            $linecount3 = (Get-Content $testFile).Count
            $linecount1 | Should -Not -Be $linecount3
        }
    }
}