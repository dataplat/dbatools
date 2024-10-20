param($ModuleName = 'dbatools')

Describe "Enable-DbaStartupProcedure" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaStartupProcedure
        }
        $parms = @(
            'SqlInstance',
            'SqlCredential',
            'StartupProcedure',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $random = Get-Random
            $startupProcName = "StartUpProc$random"
            $startupProc = "dbo.$startupProcName"
            $dbname = 'master'

            $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
        }

        AfterAll {
            $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
        }

        It "Returns correct output for enable" {
            $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false

            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Enable"
            $result.Status | Should -BeTrue
            $result.Note | Should -Be "Enable succeded"
        }

        It "Returns correct output for already existing state" {
            $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false

            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Enable"
            $result.Status | Should -BeFalse
            $result.Note | Should -Be "Action Enable already performed"
        }

        It "Returns correct output for missing procedures" {
            $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure "Unknown.NotHere" -Confirm:$false

            $result | Should -BeNullOrEmpty
        }

        It "Returns correct output for incorrectly formed procedures" {
            $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure "Four.Part.Schema.Name" -Confirm:$false

            $result | Should -BeNullOrEmpty
        }
    }
}
