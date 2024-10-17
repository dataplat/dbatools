param($ModuleName = 'dbatools')

Describe "Get-DbaQueryExecutionTime" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaQueryExecutionTime
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Mandatory:$false
        }
        It "Should have MaxResultsPerDb as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MaxResultsPerDb -Type Int32 -Mandatory:$false
        }
        It "Should have MinExecs as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MinExecs -Type Int32 -Mandatory:$false
        }
        It "Should have MinExecMs as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MinExecMs -Type Int32 -Mandatory:$false
        }
        It "Should have ExcludeSystem as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystem -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        Context "Connects and retrieves query execution times" -ForEach $global:instance1, $global:instance2 {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $_
            }

            It "Returns query execution times" {
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results.Count | Should -BeLessOrEqual 5
            }

            It "Respects the MinExecs parameter" {
                $minExecs = 2
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -MinExecs $minExecs -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results | ForEach-Object { $_.ExecutionCount | Should -BeGreaterOrEqual $minExecs }
            }

            It "Respects the MinExecMs parameter" {
                $minExecMs = 100
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -MinExecMs $minExecMs -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results | ForEach-Object { $_.AvgElapsedTime | Should -BeGreaterOrEqual $minExecMs }
            }

            It "Excludes system databases when ExcludeSystem is specified" {
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -ExcludeSystem -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results.Database | Should -Not -Contain @('master', 'model', 'msdb', 'tempdb')
            }
        }
    }
}
