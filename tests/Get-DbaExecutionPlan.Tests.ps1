param($ModuleName = 'dbatools')

Describe "Get-DbaExecutionPlan" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaExecutionPlan
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
        It "Should have SinceCreation as a parameter" {
            $CommandUnderTest | Should -HaveParameter SinceCreation -Type System.DateTime
        }
        It "Should have SinceLastExecution as a parameter" {
            $CommandUnderTest | Should -HaveParameter SinceLastExecution -Type System.DateTime
        }
        It "Should have ExcludeEmptyQueryPlan as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeEmptyQueryPlan -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        Context "Gets Execution Plan" {
            BeforeAll {
                $results = Get-DbaExecutionPlan -SqlInstance $global:instance2 | Where-Object {$_.statementtype -eq 'SELECT'} | Select-Object -First 1
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
        }

        Context "Gets Execution Plan when using -Database" {
            BeforeAll {
                $results = Get-DbaExecutionPlan -SqlInstance $global:instance2 -Database Master | Select-Object -First 1
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should be execution plan on Master" {
                $results.DatabaseName | Should -Be 'Master'
            }
        }

        Context "Gets no Execution Plan when using -ExcludeDatabase" {
            BeforeAll {
                $results = Get-DbaExecutionPlan -SqlInstance $global:instance2 -ExcludeDatabase Master | Select-Object -First 1
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should not be execution plan on Master" {
                $results.DatabaseName | Should -Not -Be 'Master'
            }
        }

        Context "Gets Execution Plan when using -SinceCreation" {
            BeforeAll {
                $results = Get-DbaExecutionPlan -SqlInstance $global:instance2 -Database Master -SinceCreation '01-01-2000' | Select-Object -First 1
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should be execution plan on Master" {
                $results.DatabaseName | Should -Be 'Master'
            }
            It "Should have a creation date Greater than 01-01-2000" {
                $results.CreationTime | Should -BeGreaterThan '01-01-2000'
            }
        }

        Context "Gets Execution Plan when using -SinceLastExecution" {
            BeforeAll {
                $results = Get-DbaExecutionPlan -SqlInstance $global:instance2 -Database Master -SinceLastExecution '01-01-2000' | Select-Object -First 1
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should be execution plan on Master" {
                $results.DatabaseName | Should -Be 'Master'
            }
            It "Should have a execution time Greater than 01-01-2000" {
                $results.LastExecutionTime | Should -BeGreaterThan '01-01-2000'
            }
        }

        Context "Gets Execution Plan when using -ExcludeEmptyQueryPlan" {
            BeforeAll {
                $results = Get-DbaExecutionPlan -SqlInstance $global:instance2 -ExcludeEmptyQueryPlan
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
        }
    }
}
