#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Disable-DbaStartupProcedure" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Disable-DbaStartupProcedure
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "StartupProcedure",
                "InputObject",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Disable-DbaStartupProcedure" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
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

    Context "When disabling a startup procedure" {
        BeforeAll {
            $result = Disable-DbaStartupProcedure -SqlInstance $TestConfig.instance2 -StartupProcedure $startupProc -Confirm:$false
        }

        It "Should return correct schema" {
            $result.Schema | Should -Be "dbo"
        }

        It "Should return correct procedure name" {
            $result.Name | Should -Be $startupProcName
        }

        It "Should show Disable action" {
            $result.Action | Should -Be "Disable"
        }

        It "Should report success status" {
            $result.Status | Should -Be $true
        }

        It "Should return success note" {
            $result.Note | Should -Be "Disable succeded"
        }
    }

    Context "When disabling an already disabled procedure" {
        BeforeAll {
            $result = Disable-DbaStartupProcedure -SqlInstance $TestConfig.instance2 -StartupProcedure $startupProc -Confirm:$false
        }

        It "Should return correct schema" {
            $result.Schema | Should -Be "dbo"
        }

        It "Should return correct procedure name" {
            $result.Name | Should -Be $startupProcName
        }

        It "Should show Disable action" {
            $result.Action | Should -Be "Disable"
        }

        It "Should report unchanged status" {
            $result.Status | Should -Be $false
        }

        It "Should return already performed note" {
            $result.Note | Should -Be "Action Disable already performed"
        }
    }

    Context "When using pipeline input" {
        BeforeAll {
            $null = Enable-DbaStartupProcedure -SqlInstance $TestConfig.instance2 -StartupProcedure $startupProc -Confirm:$false
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.instance2 | Disable-DbaStartupProcedure -Confirm:$false
        }

        It "Should return correct schema" {
            $result.Schema | Should -Be "dbo"
        }

        It "Should return correct procedure name" {
            $result.Name | Should -Be $startupProcName
        }

        It "Should show Disable action" {
            $result.Action | Should -Be "Disable"
        }

        It "Should report success status" {
            $result.Status | Should -Be $true
        }

        It "Should return success note" {
            $result.Note | Should -Be "Disable succeded"
        }
    }
}
