param($ModuleName = 'dbatools')

Describe "Measure-DbaDiskSpaceRequirement" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Measure-DbaDiskSpaceRequirement
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter
        }
        It "Should have DestinationDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationDatabase -Type String
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Should Measure Disk Space Required" {
        BeforeAll {
            $server1 = Connect-DbaInstance -SqlInstance $global:instance1
            $server2 = Connect-DbaInstance -SqlInstance $global:instance2
            $Options = @{
                Source              = $global:instance1
                Destination         = $global:instance2
                Database            = "master"
                DestinationDatabase = "Dbatoolsci_DestinationDB"
            }
            $results = Measure-DbaDiskSpaceRequirement @Options
        }

        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be sourced from Master" {
            $results.SourceDatabase | Should -Be $Options.Database
        }

        It "Should be sourced from the instance $($global:instance1)" {
            $results.SourceSqlInstance | Should -Be $server1.SqlInstance
        }

        It "Should be destined for Dbatoolsci_DestinationDB" {
            $results.DestinationDatabase | Should -Be $Options.DestinationDatabase
        }

        It "Should be destined for the instance $($global:instance2)" {
            $results.DestinationSqlInstance | Should -Be $server2.SqlInstance
        }

        It "Should have files on source" {
            $results.FileLocation | Should -Be "Only on Source"
        }
    }
}
