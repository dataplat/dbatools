param($ModuleName = 'dbatools')

Describe "Test-DbaDbQueryStore" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbQueryStore
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $dbname = "JESSdbatoolsci_querystore_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $db = New-DbaDatabase -SqlInstance $server -Name $dbname

            $null = Set-DbaDbQueryStoreOption -SqlInstance $global:instance2 -Database $dbname -State ReadWrite
            $null = Enable-DbaTraceFlag -SqlInstance $global:instance2 -TraceFlag 7745
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
            $null = Disable-DbaTraceFlag -SqlInstance $global:instance2 -TraceFlag 7745
        }

        Context 'Function works as expected' {
            BeforeAll {
                $svr = Connect-DbaInstance -SqlInstance $global:instance2
                $results = Test-DbaDbQueryStore -SqlInstance $svr -Database $dbname
            }
            It 'Should return results' {
                $results | Should -Not -BeNullOrEmpty
            }
            It 'Should show query store is enabled' {
                ($results | Where-Object Name -eq 'ActualState').Value | Should -Be 'ReadWrite'
            }
            It 'Should show recommended value for query store is to be enabled' {
                ($results | Where-Object Name -eq 'ActualState').RecommendedValue | Should -Be 'ReadWrite'
            }
            It 'Should show query store meets best practice' {
                ($results | Where-Object Name -eq 'ActualState').IsBestPractice | Should -Be $true
            }
            It 'Should show trace flag 7745 is enabled' {
                ($results | Where-Object Name -eq 'Trace Flag 7745 Enabled').Value | Should -Be 'Enabled'
            }
            It 'Should show trace flag 7745 meets best practice' {
                ($results | Where-Object Name -eq 'Trace Flag 7745 Enabled').IsBestPractice | Should -Be $true
            }
        }

        Context 'Exclude database works' {
            BeforeAll {
                $svr = Connect-DbaInstance -SqlInstance $global:instance2
                $results = Test-DbaDbQueryStore -SqlInstance $global:instance2 -ExcludeDatabase $dbname
            }
            It 'Should return results' {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should not return results for $dbname" {
                ($results | Where-Object { $_.Database -eq $dbname }) | Should -BeNullOrEmpty
            }
        }

        Context 'Function works with piping smo server object' {
            BeforeAll {
                $svr = Connect-DbaInstance -SqlInstance $global:instance2
                $results = $svr | Test-DbaDbQueryStore
            }
            It 'Should return results' {
                $results | Should -Not -BeNullOrEmpty
            }
            It 'Should show query store meets best practice' {
                ($results | Where-Object { $_.Database -eq $dbname -and $_.Name -eq 'ActualState' }).IsBestPractice | Should -Be $true
            }
            It 'Should show trace flag 7745 meets best practice' {
                ($results | Where-Object { $_.Name -eq 'Trace Flag 7745 Enabled' }).IsBestPractice | Should -Be $true
            }
        }
    }
}
