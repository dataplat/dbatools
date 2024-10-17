param($ModuleName = 'dbatools')

Describe "Get-DbaTopResourceUsage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaTopResourceUsage
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
        It "Should have Type as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[] -Mandatory:$false
        }
        It "Should have Limit as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Limit -Type Int32 -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
        It "Should have ExcludeSystem as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystem -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $results = Get-DbaTopResourceUsage -SqlInstance $instances -Type Duration -Database master
            $resultsExcluded = Get-DbaTopResourceUsage -SqlInstance $instances -Type Duration -ExcludeDatabase master
        }

        It "returns results" {
            $results.Count | Should -BeGreaterThan 0
        }

        It "only returns results from master" {
            $results | ForEach-Object {
                $_.Database | Should -Be 'master'
            }
        }

        It "Should have correct properties for Duration" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'ObjectName', 'QueryHash', 'TotalElapsedTimeMs', 'ExecutionCount', 'AverageDurationMs', 'QueryTotalElapsedTimeMs', 'QueryText'
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "No results for excluded database" {
            $resultsExcluded.Database | Should -Not -Contain 'master'
        }
    }
}
