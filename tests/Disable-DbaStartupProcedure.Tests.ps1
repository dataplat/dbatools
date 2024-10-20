param($ModuleName = 'dbatools')

Describe "Disable-DbaStartupProcedure" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaStartupProcedure
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'StartupProcedure',
            'InputObject',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Validate disabling startup procedure" -Tag "IntegrationTests" {
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

        It "returns correct results when disabling" {
            $result = Disable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -BeTrue
            $result.Note | Should -Be "Disable succeded"
        }

        It "returns correct results for already existing state" {
            $result = Disable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -BeFalse
            $result.Note | Should -Be "Action Disable already performed"
        }

        It "returns correct results for piped input" {
            $null = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result = Get-DbaStartupProcedure -SqlInstance $global:instance2 | Disable-DbaStartupProcedure -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -BeTrue
            $result.Note | Should -Be "Disable succeded"
        }
    }
}
