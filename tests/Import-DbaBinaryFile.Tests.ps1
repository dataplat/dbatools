#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaBinaryFile",
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
                "Table",
                "Schema",
                "Statement",
                "FileNameColumn",
                "BinaryColumn",
                "NoFileNameColumn",
                "InputObject",
                "FilePath",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $null = $db.Query("CREATE TABLE [dbo].[dbatoolsci_BinaryImport]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $null = $db.Query("IF OBJECT_ID('dbo.dbatoolsci_BinaryImport') IS NOT NULL DROP TABLE dbo.dbatoolsci_BinaryImport")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When importing binary files" {
        It "Should import a single file successfully" {
            $splatImport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = "dbatoolsci_BinaryImport"
                FilePath    = "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"
            }
            $result = Import-DbaBinaryFile @splatImport -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Success"
            $result.FilePath | Should -Match "localhost\.crt"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "FilePath",
                "Status"
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
