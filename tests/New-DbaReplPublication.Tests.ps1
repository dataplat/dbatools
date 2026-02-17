#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaReplPublication",
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
                "Name",
                "Type",
                "LogReaderAgentCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

# Check if replication is configured before discovery - Pester 5 evaluates -Skip during discovery before BeforeAll runs
$global:skipRepl = -not (Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle).IsPublisher

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not $global:skipRepl) {
            # Create test database for replication
            $dbName = "dbatoolsci_replpub_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

            # Create a transactional publication
            $pubName = "dbatoolsci_TransPub_$(Get-Random)"
            $splatNewPub = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Name        = $pubName
                Type        = "Transactional"
            }
            $result = New-DbaReplPublication @splatNewPub -OutVariable "global:dbatoolsciOutput"
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not $global:skipRepl) {
            # Clean up publication then database
            Remove-DbaReplPublication -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Name $pubName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When creating a transactional publication" -Skip:$global:skipRepl {
        It "Should create a publication successfully" {
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $pubName
            $result.DatabaseName | Should -Be $dbName
            $result.Type | Should -Be "Transactional"
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Replication.TransPublication]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SQLInstance",
                "DatabaseName",
                "Name",
                "Type",
                "Articles",
                "Subscriptions"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Replication\.(TransPublication|MergePublication)"
        }
    }
}