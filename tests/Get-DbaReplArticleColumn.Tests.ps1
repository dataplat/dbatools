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

    Context "Output Validation" {
        BeforeAll {
            # Mock Get-DbaReplArticle to return a test object
            Mock Get-DbaReplArticle {
                $mockArticle = New-Object PSObject -Property @{
                    ComputerName       = "localhost"
                    InstanceName       = "MSSQLSERVER"
                    SqlInstance        = "localhost"
                    DatabaseName       = "TestDB"
                    PublicationName    = "TestPub"
                    Name               = "TestArticle"
                    ArticleId          = 1
                    Description        = "Test Description"
                    Type               = "Table"
                    VerticalPartition  = $false
                    SourceObjectOwner  = "dbo"
                    SourceObjectName   = "TestTable"
                }

                # Add methods that the command expects
                Add-Member -InputObject $mockArticle -MemberType ScriptMethod -Name LoadProperties -Value { $null }

                # Mock the SqlInstance property to have Databases collection
                $mockServer = New-Object PSObject
                $mockDatabase = New-Object PSObject
                $mockTable = New-Object PSObject
                $mockColumns = @(
                    (New-Object PSObject -Property @{Name = "Column1"}),
                    (New-Object PSObject -Property @{Name = "Column2"})
                )
                Add-Member -InputObject $mockTable -MemberType NoteProperty -Name Columns -Value $mockColumns
                Add-Member -InputObject $mockDatabase -MemberType ScriptMethod -Name Tables -Value { param($name, $owner) return $mockTable }.GetNewClosure()
                Add-Member -InputObject $mockServer -MemberType ScriptMethod -Name Databases -Value { param($name) return $mockDatabase }.GetNewClosure()
                Add-Member -InputObject $mockArticle -MemberType NoteProperty -Name SqlInstance -Value $mockServer -Force

                return $mockArticle
            }

            $result = Get-DbaReplArticleColumn -SqlInstance "localhost" -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "PublicationName",
                "ArticleName",
                "ArticleId",
                "ColumnName"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the additional documented properties" {
            $additionalProps = @(
                "Description",
                "Type",
                "VerticalPartition",
                "SourceObjectOwner",
                "SourceObjectName"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>