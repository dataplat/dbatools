param($ModuleName = 'dbatools')

Describe "Enable-DbaStartupProcedure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaStartupProcedure
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have StartupProcedure as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartupProcedure -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
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
                $result = Enable-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Confirm:$false
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
                $result = Enable-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Confirm:$false
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
                $result = Enable-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure "Unknown.NotHere" -Confirm:$false
            }
            It "returns null" {
                $result | Should -BeNullOrEmpty
            }
        }

        Context "Validate returns correct output for incorrectly formed procedures" {
            BeforeAll {
                $result = Enable-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure "Four.Part.Schema.Name" -Confirm:$false
            }
            It "returns null" {
                $result | Should -BeNullOrEmpty
            }
        }
    }
}
