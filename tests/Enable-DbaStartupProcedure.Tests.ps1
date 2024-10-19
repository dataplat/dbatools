param($ModuleName = 'dbatools')

Describe "Enable-DbaStartupProcedure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaStartupProcedure
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "StartupProcedure",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
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

        Context "Validate returns correct output for enable" {
            BeforeAll {
                $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            }
            It "returns correct schema" {
                $result.Schema | Should -Be "dbo"
            }
            It "returns correct name" {
                $result.Name | Should -Be $startupProcName
            }
            It "returns correct action" {
                $result.Action | Should -Be "Enable"
            }
            It "returns correct status" {
                $result.Status | Should -Be $true
            }
            It "returns correct note" {
                $result.Note | Should -Be "Enable succeded"
            }
        }

        Context "Validate returns correct output for already existing state" {
            BeforeAll {
                $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            }
            It "returns correct schema" {
                $result.Schema | Should -Be "dbo"
            }
            It "returns correct name" {
                $result.Name | Should -Be $startupProcName
            }
            It "returns correct action" {
                $result.Action | Should -Be "Enable"
            }
            It "returns correct status" {
                $result.Status | Should -Be $false
            }
            It "returns correct note" {
                $result.Note | Should -Be "Action Enable already performed"
            }
        }

        Context "Validate returns correct output for missing procedures" {
            BeforeAll {
                $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure "Unknown.NotHere" -Confirm:$false
            }
            It "returns null" {
                $result | Should -BeNullOrEmpty
            }
        }

        Context "Validate returns correct output for incorrectly formed procedures" {
            BeforeAll {
                $result = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure "Four.Part.Schema.Name" -Confirm:$false
            }
            It "returns null" {
                $result | Should -BeNullOrEmpty
            }
        }
    }
}
