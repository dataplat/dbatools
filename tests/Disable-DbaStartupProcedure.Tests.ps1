param($ModuleName = 'dbatools')

Describe "Disable-DbaStartupProcedure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaStartupProcedure
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "StartupProcedure",
                "InputObject",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $random = Get-Random
            $startupProcName = "StartUpProc$random"
            $startupProc = "dbo.$startupProcName"
            $dbname = 'master'

            $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
            $null = $server.Query("EXEC sp_procoption '$startupProc', 'startup', 'on'", $dbname)
        }
        AfterAll {
            $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
        }

        It "Disables the startup procedure" {
            $result = Disable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -Be $true
            $result.Note | Should -Be "Disable succeded"
        }

        It "Returns correct output for already disabled procedure" {
            $result = Disable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -Be $false
            $result.Note | Should -Be "Action Disable already performed"
        }

        It "Disables startup procedure using piped input" {
            $null = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result = Get-DbaStartupProcedure -SqlInstance $global:instance2 | Disable-DbaStartupProcedure -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -Be $true
            $result.Note | Should -Be "Disable succeded"
        }
    }
}
