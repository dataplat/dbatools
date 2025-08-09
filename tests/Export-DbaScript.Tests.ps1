#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaScript",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
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
    Context "works as expected" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
            # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
            $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "should export some text matching create table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results -match "CREATE TABLE" | Should -BeTrue
        }

        It "should include BatchSeparator based on the Formatting.BatchSeparator configuration" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results -match "(Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator')" | Should -BeTrue
        }

        It "should include the defined BatchSeparator" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $results -match "MakeItSo" | Should -BeTrue
        }

        It "should not accept non-SMO objects" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $null = [pscustomobject]@{ Invalid = $true } | Export-DbaScript -WarningVariable invalid -WarningAction SilentlyContinue
            $invalid -match "not a SQL Management Object" | Should -BeTrue
        }

        It "should not append when using NoPrefix (#7455)" {
            $testFile = "$backupPath\msdb.txt"
            
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