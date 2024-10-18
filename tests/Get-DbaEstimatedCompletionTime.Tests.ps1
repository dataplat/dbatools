param($ModuleName = 'dbatools')

Describe "Get-DbaEstimatedCompletionTime" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaEstimatedCompletionTime
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Get-DbaDatabase -SqlInstance $server -Database checkdbTestDatabase | Remove-DbaDatabase -Confirm:$false
            $null = Restore-DbaDatabase -SqlInstance $server -Path $global:appveyorlabrepo\sql2008-backups\db1\SQL2008_db1_FULL_20170518_041738.bak -DatabaseName checkdbTestDatabase
            $null = New-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
            $null = New-DbaAgentJobStep -SqlInstance $server -Job checkdbTestJob -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('checkdbTestDatabase')"
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Remove-DbaAgentJob -SqlInstance $server -Job checkdbTestJob -Confirm:$false
            $null = Get-DbaDatabase -SqlInstance $server -Database checkdbTestDatabase | Remove-DbaDatabase -Confirm:$false
        }

        Context "Gets Query Estimated Completion" {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $global:instance2
                $null = Start-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
                $results = Get-DbaEstimatedCompletionTime -SqlInstance $server
                $null = Remove-DbaAgentJob -SqlInstance $server -Job checkdb -Confirm:$false
                Start-Sleep -Seconds 5
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should be DBCC" {
                $results.Command | Should -Match 'DBCC'
            }
            It "Should be login dbo" {
                $results.login | Should -Be 'dbo'
            }
        }

        Context "Gets Query Estimated Completion when using -Database" {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $global:instance2
                $null = Start-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
                $results = Get-DbaEstimatedCompletionTime -SqlInstance $server -Database checkdbTestDatabase
                Start-Sleep -Seconds 5
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should be DBCC" {
                $results.Command | Should -Match 'DBCC'
            }
            It "Should be login dbo" {
                $results.login | Should -Be 'dbo'
            }
        }

        Context "Gets no Query Estimated Completion when using -ExcludeDatabase" {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $global:instance2
                $null = Start-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
                $results = Get-DbaEstimatedCompletionTime -SqlInstance $server -ExcludeDatabase checkdbTestDatabase
                Start-Sleep -Seconds 5
            }

            It "Gets no results" {
                $results | Should -BeNullOrEmpty
            }
        }
    }
}
