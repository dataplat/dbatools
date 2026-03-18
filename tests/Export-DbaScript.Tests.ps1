#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaScript",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When exporting scripts" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For all temp files that we want to clean up after the test, we create a directory that we can delete at the end.
            $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $tempPath -ItemType Directory

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Remove the temp directory.
            Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should export some text matching create table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results -match "CREATE TABLE"
        }

        It "Should include BatchSeparator based on the Formatting.BatchSeparator configuration" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results -match "(Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator')"
        }

        It "Should include the defined BatchSeparator" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $results -match "MakeItSo"
        }

        It "Should not accept non-SMO objects" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $null = [PSCustomObject]@{ Invalid = $true } | Export-DbaScript -WarningVariable invalid -WarningAction SilentlyContinue
            $invalid -match "not a SQL Management Object"
        }

        It "Should not append when using NoPrefix (#7455)" {
            $tempFile = "$tempPath\msdb-$(Get-Random).txt"

            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath $tempFile
            $linecount1 = (Get-Content $tempFile).Count
            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath $tempFile
            $linecount2 = (Get-Content $tempFile).Count
            $linecount1 | Should -Be $linecount2
            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath $tempFile -Append
            $linecount3 = (Get-Content $tempFile).Count
            $linecount1 | Should -Not -Be $linecount3
        }
    }
}