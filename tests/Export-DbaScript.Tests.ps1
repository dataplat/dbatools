#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Remove the temp directory.
        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Works as expected" {
        BeforeAll {
            $testTable = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1
            $testFilePath = "$tempPath\msdb.txt"
        }

        It "Should export some text matching create table" {
            $results = $testTable | Export-DbaScript -Passthru
            $results -match "CREATE TABLE" | Should -BeTrue
        }

        It "Should include BatchSeparator based on the Formatting.BatchSeparator configuration" {
            $results = $testTable | Export-DbaScript -Passthru
            $results -match "(Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator')" | Should -BeTrue
        }

        It "Should include the defined BatchSeparator" {
            $results = $testTable | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $results -match "MakeItSo" | Should -BeTrue
        }

        It "Should not accept non-SMO objects" {
            $null = [pscustomobject]@{ Invalid = $true } | Export-DbaScript -WarningVariable invalidWarning -WarningAction SilentlyContinue
            $invalidWarning -match "not a SQL Management Object" | Should -BeTrue
        }

        It "Should not append when using NoPrefix (#7455)" {
            $null = $testTable | Export-DbaScript -NoPrefix -FilePath $testFilePath
            $linecount1 = @(Get-Content $testFilePath).Count
            
            $null = $testTable | Export-DbaScript -NoPrefix -FilePath $testFilePath
            $linecount2 = @(Get-Content $testFilePath).Count
            $linecount1 | Should -Be $linecount2
            
            $null = $testTable | Export-DbaScript -NoPrefix -FilePath $testFilePath -Append
            $linecount3 = @(Get-Content $testFilePath).Count
            $linecount1 | Should -Not -Be $linecount3
        }
    }
}
