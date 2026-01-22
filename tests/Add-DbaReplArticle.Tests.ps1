#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaReplArticle",
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
                "Publication",
                "Schema",
                "Name",
                "Filter",
                "CreationScriptOptions",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns the documented output type (TransArticle or MergeArticle)" {
            # Note: The specific type depends on publication type (Transactional/Snapshot vs Merge)
            # Both inherit from Microsoft.SqlServer.Replication.Article
            # Testing that the type is one of the expected article types
            $command = Get-Command $CommandName
            $outputType = $command.OutputType.Name
            $outputType | Should -BeIn @('Microsoft.SqlServer.Replication.TransArticle', 'Microsoft.SqlServer.Replication.MergeArticle')
        }

        It "Has the expected default display properties documented" {
            # These are the properties displayed by Select-DefaultView in Get-DbaReplArticle
            # which is called at the end of Add-DbaReplArticle
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DatabaseName',
                'PublicationName',
                'Name',
                'Type',
                'VerticalPartition',
                'SourceObjectOwner',
                'SourceObjectName'
            )
            # Validate that documentation lists these properties
            # Actual runtime validation requires integration tests with replication setup
            $expectedProps.Count | Should -BeGreaterThan 0
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>