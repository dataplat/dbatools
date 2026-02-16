#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaSysDbUserObject",
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
                "IncludeDependencies",
                "BatchSeparator",
                "Path",
                "FilePath",
                "NoPrefix",
                "ScriptingOptionsObject",
                "NoClobber",
                "PassThru",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        $random = Get-Random
        $tableName = "dbatoolsci_UserTable_$random"
        $viewName = "dbatoolsci_View_$random"
        $procName = "dbatoolsci_SP_$random"
        $triggerName = "[dbatoolsci_Trigger_$random]"
        $tableFunctionName = "[dbatoolsci_TableFunction_$random]"
        $scalarFunctionName = "[dbatoolsci_ScalarFunction_$random]"
        $ruleName = "[dbatoolsci_Rule_$random]"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $SqlCredential
        $server.query("CREATE TABLE dbo.$tableName (Col1 int);", "master")
        $server.query("CREATE VIEW dbo.$viewName AS SELECT 1 as Col1;", "master")
        $server.query("CREATE PROCEDURE dbo.$procName as select 1;", "master")
        $server.query("CREATE TRIGGER $triggerName ON DATABASE FOR DROP_SYNONYM AS RAISERROR ('You must disable Trigger safety to drop synonyms!', 10, 1)", "master")
        $server.query("CREATE FUNCTION dbo.$tableFunctionName () RETURNS TABLE AS RETURN SELECT 1 as test", "master")
        $server.query("CREATE FUNCTION dbo.$scalarFunctionName (@int int) RETURNS INT AS BEGIN RETURN @int END", "master")
        $server.query("CREATE RULE dbo.$ruleName AS @range>= 1 AND @range <10;", "master")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $SqlCredential
        $server.query("DROP TABLE dbo.$tableName", "master")
        $server.query("DROP VIEW dbo.$viewName", "master")
        $server.query("DROP PROCEDURE dbo.$procName", "master")
        $server.query("DROP TRIGGER $triggerName ON DATABASE", "master")
        $server.query("DROP FUNCTION dbo.$tableFunctionName", "master")
        $server.query("DROP FUNCTION dbo.$scalarFunctionName", "master")
        $server.query("DROP RULE dbo.$ruleName", "master")

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "works as expected with passthru" {
        BeforeAll {
            $script = Export-DbaSysDbUserObject -SqlInstance $TestConfig.InstanceSingle -PassThru | Out-String
        }

        It "should export text matching table name '$tableName'" {
            $script -match $tableName | Should -Be $true
        }
        It "should export text matching view name '$viewName'" {
            $script -match $viewName | Should -Be $true
        }
        It "should export text matching stored procedure name '$procName'" {
            $script -match $procName | Should -Be $true
        }
        It "should export text matching trigger name '$triggerName'" {
            $script -match $triggerName | Should -Be $true
        }
        It "should export text matching table function name '$tableFunctionName'" {
            $script -match $tableFunctionName | Should -Be $true
        }
        It "should export text matching scalar function name '$scalarFunctionName'" {
            $script -match $scalarFunctionName | Should -Be $true
        }
        It "should export text matching rule name '$ruleName'" {
            $script -match $ruleName | Should -Be $true
        }
    }

    Context "works as expected with filename" {
        BeforeAll {
            $filePath = "$backupPath\objects_$random.sql"
            $null = Export-DbaSysDbUserObject -SqlInstance $TestConfig.InstanceSingle -FilePath $filePath -OutVariable "global:dbatoolsciOutput"
            $file = Get-Content $filePath | Out-String
        }

        AfterAll {
            Remove-Item -Path $filePath -ErrorAction SilentlyContinue
        }

        It "should export text matching table name '$tableName'" {
            $file -match $tableName | Should -Be $true
        }
        It "should export text matching view name '$viewName'" {
            $file -match $viewName | Should -Be $true
        }
        It "should export text matching stored procedure name '$procName'" {
            $file -match $procName | Should -Be $true
        }
        It "should export text matching trigger name '$triggerName'" {
            $file -match $triggerName | Should -Be $true
        }
        It "should export text matching table function name '$tableFunctionName'" {
            $file -match $tableFunctionName | Should -Be $true
        }
        It "should export text matching scalar function name '$scalarFunctionName'" {
            $file -match $scalarFunctionName | Should -Be $true
        }
        It "should export text matching scalar function name '$ruleName'" {
            $file -match $ruleName | Should -Be $true
        }
    }

    Context "ScriptingOptionsObject parameter works correctly" {
        It "should respect IncludeIfNotExists scripting option when specified" {
            $scriptOpts = New-DbaScriptingOption
            $scriptOpts.IncludeIfNotExists = $true
            $splatExport = @{
                SqlInstance            = $TestConfig.InstanceSingle
                ScriptingOptionsObject = $scriptOpts
                PassThru               = $true
            }
            $script = Export-DbaSysDbUserObject @splatExport | Out-String
            $script -match "IF NOT EXISTS" | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.IO\.FileInfo"
        }
    }
}