#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaReplCreationScriptOptions",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @( )  # Command does not use [CmdletBinding()]
            $expectedParameters += @(
                "Options",
                "NoDefaults"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: this command is a pure object factory - it builds a
    # Microsoft.SqlServer.Replication.CreationScriptOptions flags enum and needs no instance and no
    # replication topology, so it is fully characterizable here. The enum type lives in
    # Microsoft.SqlServer.Rmo.dll, which ships in the dbatools.library drop and loads standalone;
    # only Microsoft.SqlServer.Replication.dll needs SQL native replication components, and this
    # command does not require it. The Add-Type below is a one-line load of the shipped assembly,
    # skipped when the type is already present.
    BeforeAll {
        if (-not ([System.Management.Automation.PSTypeName]"Microsoft.SqlServer.Replication.CreationScriptOptions").Type) {
            $editionFolder = if ($PSVersionTable.PSEdition -eq "Core") { "core" } else { "desktop" }
            $rmoPath = Join-Path (Get-Module dbatools.library).ModuleBase "$editionFolder/lib/Microsoft.SqlServer.Rmo.dll"
            Add-Type -Path $rmoPath
        }
    }

    Context "Building the options object" {
        It "Returns a CreationScriptOptions carrying the SSMS defaults plus the requested options" {
            $result = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics

            $result.GetType().FullName | Should -Be "Microsoft.SqlServer.Replication.CreationScriptOptions"
            # the documented default set the source seeds before adding the requested options
            foreach ($expected in "PrimaryObject", "CustomProcedures", "Identity", "KeepTimestamp", "ClusteredIndexes", "DriPrimaryKey", "Collation", "DriUniqueKeys", "Schema") {
                $result.HasFlag([Microsoft.SqlServer.Replication.CreationScriptOptions]$expected) | Should -BeTrue
            }
            # and the two explicitly requested options
            $result.HasFlag([Microsoft.SqlServer.Replication.CreationScriptOptions]::NonClusteredIndexes) | Should -BeTrue
            $result.HasFlag([Microsoft.SqlServer.Replication.CreationScriptOptions]::Statistics) | Should -BeTrue
        }

        It "Returns only the requested options when NoDefaults is used" {
            $result = New-DbaReplCreationScriptOptions -Options ClusteredIndexes, Identity -NoDefaults

            # characterization: with NoDefaults nothing is seeded, and the flags enum renders in
            # ENUM declaration order rather than the order the options were supplied
            $result.ToString() | Should -Be "Identity, ClusteredIndexes"
            $result.HasFlag([Microsoft.SqlServer.Replication.CreationScriptOptions]::PrimaryObject) | Should -BeFalse
        }
    }
}
