param($ModuleName = 'dbatools')

Describe "Get-DbaExecutionPlan" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaExecutionPlan
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "SinceCreation",
            "SinceLastExecution",
            "ExcludeEmptyQueryPlan",
            "Force",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
