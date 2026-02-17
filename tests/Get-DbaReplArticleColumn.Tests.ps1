#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplArticleColumn",
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
                "Article",
                "Column",
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
            $dbName = "dbatoolsci_replcol_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Query "CREATE TABLE ReplicateMe (id int identity(1,1) PRIMARY KEY, col1 varchar(10), col2 varchar(20))"

            # Create transactional publication and add an article
            $pubName = "dbatoolsci_TestTransPub_$(Get-Random)"
            $null = New-DbaReplPublication -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Type Transactional -Name $pubName
            $null = Add-DbaReplArticle -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Publication $pubName -Name "ReplicateMe"
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

    Context "When getting article columns from a publication" -Skip:$global:skipRepl {
        It "Should return article columns" {
            $splatArticleCol = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Publication = $pubName
            }
            $result = Get-DbaReplArticleColumn @splatArticleCol -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.ColumnName | Should -Contain "id"
            $result.ColumnName | Should -Contain "col1"
            $result.ArticleName | Select-Object -Unique | Should -Be "ReplicateMe"
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "PublicationName",
                "ArticleName",
                "ArticleId",
                "ColumnName"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
