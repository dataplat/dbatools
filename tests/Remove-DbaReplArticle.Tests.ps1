#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaReplArticle",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip UnitTests on pwsh because command is not present.

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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Check if replication is configured - skip all tests if not
        $replServer = Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle
        $global:skipRepl = -not $replServer.IsPublisher

        if (-not $global:skipRepl) {
            # Create test database and table for replication
            $dbName = "dbatoolsci_repl_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Query "CREATE TABLE ReplicateMe (id int identity(1,1) PRIMARY KEY, col1 varchar(10))"

            # Create transactional publication and add an article
            $pubName = "dbatoolsci_TestTransPub_$(Get-Random)"
            $null = New-DbaReplPublication -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Type Transactional -Name $pubName
            $splatArticle = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Publication = $pubName
                Name        = "ReplicateMe"
            }
            $null = Add-DbaReplArticle @splatArticle
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

    Context "When removing an article from a transactional publication" -Skip:$global:skipRepl {
        It "Should remove the article and return output" {
            $splatRemove = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Publication = $pubName
                Name        = "ReplicateMe"
                Confirm     = $false
            }
            $result = Remove-DbaReplArticle @splatRemove -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.ObjectName | Should -Be "ReplicateMe"
            $result.ObjectSchema | Should -Be "dbo"
            $result.Database | Should -Be $dbName
            $result.Status | Should -Be "Removed"
            $result.IsRemoved | Should -BeTrue
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ObjectName",
                "ObjectSchema",
                "Status",
                "IsRemoved"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}