param($ModuleName = 'dbatools')

Describe "Get-DbaTopResourceUsage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaTopResourceUsage
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Type",
                "Limit",
                "EnableException",
                "ExcludeSystem"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param -Mandatory:$false
            }
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
