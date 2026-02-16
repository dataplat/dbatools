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

            # Create transactional publication
            $pubName = "dbatoolsci_TestTransPub_$(Get-Random)"
            $null = New-DbaReplPublication -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Type Transactional -Name $pubName
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

    Context "When adding an article to a transactional publication" -Skip:$global:skipRepl {
        It "Should add the article and return output" {
            $splatArticle = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Publication = $pubName
                Name        = "ReplicateMe"
            }
            $result = Add-DbaReplArticle @splatArticle -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be "ReplicateMe"
            $result.DatabaseName | Should -Be $dbName
            $result.PublicationName | Should -Be $pubName
            $result.SourceObjectOwner | Should -Be "dbo"
            $result.SourceObjectName | Should -Be "ReplicateMe"
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Replication.TransArticle]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "PublicationName",
                "Name",
                "Type",
                "VerticalPartition",
                "SourceObjectOwner",
                "SourceObjectName"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Replication\.(TransArticle|MergeArticle)"
        }
    }
}