param($ModuleName = 'dbatools')

Describe "Copy-DbaStartupProcedure" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $procName = "dbatoolsci_test_startup"
        $server.Query("CREATE OR ALTER PROCEDURE $procName
                        AS
                        SELECT @@SERVERNAME
                        GO")
        $server.Query("EXEC sp_procoption @ProcName = N'$procName'
                            , @OptionName = 'startup'
                            , @OptionValue = 'on'")
    }

    AfterAll {
        Invoke-DbaQuery -SqlInstance $script:instance2, $script:instance3 -Database "master" -Query "DROP PROCEDURE dbatoolsci_test_startup"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaStartupProcedure
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Procedure as a parameter" {
            $CommandUnderTest | Should -HaveParameter Procedure -Type String[]
        }
        It "Should have ExcludeProcedure as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeProcedure -Type String[]
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Copy-DbaStartupProcedure -Source $script:instance2 -Destination $script:instance3
        }
        It "Should include test procedure: $procName" {
            ($results | Where-Object Name -eq $procName).Name | Should -Be $procName
        }
        It "Should be successful" {
            ($results | Where-Object Name -eq $procName).Status | Should -Be 'Successful'
        }
    }
}
