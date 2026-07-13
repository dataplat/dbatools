#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaExecutionPlan",
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
                "Database",
                "ExcludeDatabase",
                "Path",
                "SinceCreation",
                "SinceLastExecution",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-096): pin the live function's observable behavior before
    # the compiled port. The plan cache is seeded with a fresh, filterable entry so the
    # SinceCreation/Database filters keep the export volume deterministic.
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $exportPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $exportPath -ItemType Directory

        $sinceCreation = (Get-Date).AddSeconds(-2)
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "SELECT TOP 3 name FROM sys.databases"

        $splatExport = @{
            SqlInstance   = $TestConfig.InstanceSingle
            Database      = "master"
            SinceCreation = $sinceCreation
            Path          = $exportPath
        }
        $results = @(Export-DbaExecutionPlan @splatExport)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-Item -Path $exportPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When exporting execution plans from an instance" {
        It "Returns objects with the documented default-view properties" {
            $results.Count | Should -BeGreaterThan 0
            $results[0].SqlInstance | Should -Not -BeNullOrEmpty
            $results[0].DatabaseName | Should -Be "master"
            $results[0].OutputFile | Should -Match "\.sqlplan$"
        }

        It "Writes sqlplan files into the target directory" {
            @(Get-ChildItem -Path $exportPath -Filter "*.sqlplan").Count | Should -BeGreaterThan 0
        }
    }

    Context "When piping plan objects back in" {
        It "Processes only the FIRST object of an explicit -InputObject array (return-in-foreach quirk)" {
            $pipedResults = @(Export-DbaExecutionPlan -InputObject @($results[0], $results[0]) -Path $exportPath)
            $pipedResults.Count | Should -Be 1
            $pipedResults[0].OutputFile | Should -Match "\.sqlplan$"
        }
    }
}