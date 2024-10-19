param($ModuleName = 'dbatools')

Describe "Export-DbaSysDbUserObject" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaSysDbUserObject
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have IncludeDependencies as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeDependencies
        }
        It "Should have BatchSeparator as a string parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator
        }
        It "Should have Path as a string parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have FilePath as a string parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath
        }
        It "Should have NoPrefix as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoPrefix
        }
        It "Should have ScriptingOptionsObject as a ScriptingOptions parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptingOptionsObject
        }
        It "Should have NoClobber as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber
        }
        It "Should have PassThru as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter PassThru
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $random = Get-Random
            $tableName = "dbatoolsci_UserTable_$random"
            $viewName = "dbatoolsci_View_$random"
            $procName = "dbatoolsci_SP_$random"
            $triggerName = "[dbatoolsci_Trigger_$random]"
            $tableFunctionName = "[dbatoolsci_TableFunction_$random]"
            $scalarFunctionName = "[dbatoolsci_ScalarFunction_$random]"
            $ruleName = "[dbatoolsci_Rule_$random]"
            $server = Connect-DbaInstance -SqlInstance $global:instance2 -SqlCredential $SqlCredential
            $server.Query("CREATE TABLE dbo.$tableName (Col1 int);", "master")
            $server.Query("CREATE VIEW dbo.$viewName AS SELECT 1 as Col1;", "master")
            $server.Query("CREATE PROCEDURE dbo.$procName as select 1;", "master")
            $server.Query("CREATE TRIGGER $triggerName ON DATABASE FOR DROP_SYNONYM AS RAISERROR ('You must disable Trigger safety to drop synonyms!', 10, 1)", "master")
            $server.Query("CREATE FUNCTION dbo.$tableFunctionName () RETURNS TABLE AS RETURN SELECT 1 as test", "master")
            $server.Query("CREATE FUNCTION dbo.$scalarFunctionName (@int int) RETURNS INT AS BEGIN RETURN @int END", "master")
            $server.Query("CREATE RULE dbo.$ruleName AS @range>= 1 AND @range <10;", "master")
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2 -SqlCredential $SqlCredential
            $server.Query("DROP TABLE dbo.$tableName", "master")
            $server.Query("DROP VIEW dbo.$viewName", "master")
            $server.Query("DROP PROCEDURE dbo.$procName", "master")
            $server.Query("DROP TRIGGER $triggerName ON DATABASE", "master")
            $server.Query("DROP FUNCTION dbo.$tableFunctionName", "master")
            $server.Query("DROP FUNCTION dbo.$scalarFunctionName", "master")
            $server.Query("DROP RULE dbo.$ruleName", "master")
        }

        Context "works as expected with passthru" {
            BeforeAll {
                $script = Export-DbaSysDbUserObject -SqlInstance $global:instance2 -PassThru | Out-String
            }

            It "should export text matching table name '$tableName'" {
                $script | Should -Match $tableName
            }
            It "should export text matching view name '$viewName'" {
                $script | Should -Match $viewName
            }
            It "should export text matching stored procedure name '$procName'" {
                $script | Should -Match $procName
            }
            It "should export text matching trigger name '$triggerName'" {
                $script | Should -Match $triggerName
            }
            It "should export text matching table function name '$tableFunctionName'" {
                $script | Should -Match $tableFunctionName
            }
            It "should export text matching scalar function name '$scalarFunctionName'" {
                $script | Should -Match $scalarFunctionName
            }
            It "should export text matching rule name '$ruleName'" {
                $script | Should -Match $ruleName
            }
        }

        Context "works as expected with filename" {
            BeforeAll {
                $null = Export-DbaSysDbUserObject -SqlInstance $global:instance2 -FilePath "C:\Temp\objects_$random.sql"
                $file = Get-Content "C:\Temp\objects_$random.sql" | Out-String
            }

            It "should export text matching table name '$tableName'" {
                $file | Should -Match $tableName
            }
            It "should export text matching view name '$viewName'" {
                $file | Should -Match $viewName
            }
            It "should export text matching stored procedure name '$procName'" {
                $file | Should -Match $procName
            }
            It "should export text matching trigger name '$triggerName'" {
                $file | Should -Match $triggerName
            }
            It "should export text matching table function name '$tableFunctionName'" {
                $file | Should -Match $tableFunctionName
            }
            It "should export text matching scalar function name '$scalarFunctionName'" {
                $file | Should -Match $scalarFunctionName
            }
            It "should export text matching scalar function name '$ruleName'" {
                $file | Should -Match $ruleName
            }
        }
    }
}
