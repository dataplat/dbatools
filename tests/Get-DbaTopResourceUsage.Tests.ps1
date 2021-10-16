$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Type', 'Limit', 'EnableException', 'ExcludeSystem'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $results = Get-DbaTopResourceUsage -SqlInstance $instances -Type Duration -Database master
    $resultsExcluded = Get-DbaTopResourceUsage -SqlInstance $instances -Type Duration -ExcludeDatabase master
    Context "Command returns proper info" {
        It "returns results" {
            $results.Count -gt 0 | Should Be $true
        }

        foreach ($result in $results) {
            It "only returns results from master" {
                $result.Database -eq 'master' | Should Be $true
            }
        }

        # Each of the 4 -Types return slightly different information so this way, we can check to ensure only duration was returned
        It "Should have correct properties for Duration" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,ObjectName,QueryHash,TotalElapsedTimeMs,ExecutionCount,AverageDurationMs,QueryTotalElapsedTimeMs,QueryText'.Split(',')
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        It "No results for excluded database" {
            $resultsExcluded.Database -notcontains 'master' | Should Be $true
        }
    }
}