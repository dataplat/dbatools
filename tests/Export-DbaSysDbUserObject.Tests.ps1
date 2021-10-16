$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'IncludeDependencies', 'BatchSeparator', 'Path', 'FilePath', 'NoPrefix', 'ScriptingOptionsObject', 'NoClobber', 'PassThru', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $tableName = "dbatoolsci_UserTable_$random"
        $viewName = "dbatoolsci_View_$random"
        $procName = "dbatoolsci_SP_$random"
        $triggerName = "[dbatoolsci_Trigger_$random]"
        $tableFunctionName = "[dbatoolsci_TableFunction_$random]"
        $scalarFunctionName = "[dbatoolsci_ScalarFunction_$random]"
        $ruleName = "[dbatoolsci_Rule_$random]"
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -SqlCredential $SqlCredential
        $server.query("CREATE TABLE dbo.$tableName (Col1 int);", "master")
        $server.query("CREATE VIEW dbo.$viewName AS SELECT 1 as Col1;", "master")
        $server.query("CREATE PROCEDURE dbo.$procName as select 1;", "master")
        $server.query("CREATE TRIGGER $triggerName ON DATABASE FOR DROP_SYNONYM AS RAISERROR ('You must disable Trigger safety to drop synonyms!', 10, 1)", "master")
        $server.query("CREATE FUNCTION dbo.$tableFunctionName () RETURNS TABLE AS RETURN SELECT 1 as test", "master")
        $server.query("CREATE FUNCTION dbo.$scalarFunctionName (@int int) RETURNS INT AS BEGIN RETURN @int END", "master")
        $server.query("CREATE RULE dbo.$ruleName AS @range>= 1 AND @range <10;", "master")
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -SqlCredential $SqlCredential
        $server.query("DROP TABLE dbo.$tableName", "master")
        $server.query("DROP VIEW dbo.$viewName", "master")
        $server.query("DROP PROCEDURE dbo.$procName", "master")
        $server.query("DROP TRIGGER $triggerName ON DATABASE", "master")
        $server.query("DROP FUNCTION dbo.$tableFunctionName", "master")
        $server.query("DROP FUNCTION dbo.$scalarFunctionName", "master")
        $server.query("DROP RULE dbo.$ruleName", "master")
    }
    Context "works as expected with passthru" {
        $script = Export-DbaSysDbUserObject -SqlInstance $script:instance2 -PassThru | Out-String
        It "should export text matching table name '$tableName'" {
            $script -match $tableName | Should be $true
        }
        It "should export text matching view name '$viewName'" {
            $script -match $viewName | Should be $true
        }
        It "should export text matching stored procedure name '$procName'" {
            $script -match $procName | Should be $true
        }
        It "should export text matching trigger name '$triggerName'" {
            $script -match $triggerName | Should be $true
        }
        It "should export text matching table function name '$tableFunctionName'" {
            $script -match $tableFunctionName | Should be $true
        }
        It "should export text matching scalar function name '$scalarFunctionName'" {
            $script -match $scalarFunctionName | Should be $true
        }
        It "should export text matching rule name '$ruleName'" {
            $script -match $ruleName | Should be $true
        }
    }

    Context "works as expected with filename" {
        $null = Export-DbaSysDbUserObject -SqlInstance $script:instance2 -FilePath "C:\Temp\objects_$random.sql"
        $file = Get-Content "C:\Temp\objects_$random.sql" | Out-String
        It "should export text matching table name '$tableName'" {
            $file -match $tableName | Should be $true
        }
        It "should export text matching view name '$viewName'" {
            $file -match $viewName | Should be $true
        }
        It "should export text matching stored procedure name '$procName'" {
            $file -match $procName | Should be $true
        }
        It "should export text matching trigger name '$triggerName'" {
            $file -match $triggerName | Should be $true
        }
        It "should export text matching table function name '$tableFunctionName'" {
            $file -match $tableFunctionName | Should be $true
        }
        It "should export text matching scalar function name '$scalarFunctionName'" {
            $file -match $scalarFunctionName | Should be $true
        }
        It "should export text matching scalar function name '$ruleName'" {
            $file -match $ruleName | Should be $true
        }
    }
}