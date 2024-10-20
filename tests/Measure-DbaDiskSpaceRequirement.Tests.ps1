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

        It "has all the required parameters" {
            $params = @(
                "Source",
                "Database",
                "SourceSqlCredential",
                "Destination",
                "DestinationDatabase",
                "DestinationSqlCredential",
                "Credential",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
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
