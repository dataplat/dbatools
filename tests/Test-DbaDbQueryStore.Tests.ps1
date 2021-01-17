$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "JESSdbatoolsci_querystore_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db = New-DbaDatabase -SqlInstance $server -Name $dbname

        $null = Set-DbaDbQueryStoreOption -SqlInstance $script:instance2 -Database $dbname -State ReadWrite
        $null = Enable-DbaTraceFlag -SqlInstance $script:instance2 -TraceFlag 7745
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
        $null = Disable-DbaTraceFlag -SqlInstance $script:instance2 -TraceFlag 7745
    }
    Context 'Function works as expected' {
        $svr = Connect-DbaInstance -SqlInstance $script:instance2

        $results = Test-DbaDbQueryStore -SqlInstance $svr -Database $dbname
        It 'Should return results' {
            $results | Should Not BeNullOrEmpty
        }
        It 'Should show query store is enabled' {
            ($results | Where-Object Name -eq 'ActualState').Value | Should Be 'ReadWrite'
        }
        It 'Should show recommended value for query store is to be enabled' {
            ($results | Where-Object Name -eq 'ActualState').RecommendedValue | Should Be 'ReadWrite'
        }
        It 'Should show query store meets best practice' {
            ($results | Where-Object Name -eq 'ActualState').IsBestPractice | Should Be $true
        }
        It 'Should show trace flag  7745 is enabled' {
            ($results | Where-Object Name -eq 'Trace Flag 7745 Enabled').Value | Should Be 'Enabled'
        }
        It 'Should show trace flag 7745 meets best practice' {
            ($results | Where-Object Name -eq 'Trace Flag 7745 Enabled').IsBestPractice | Should Be $true
        }
    }

    Context 'Exclude database works' {
        $svr = Connect-DbaInstance -SqlInstance $script:instance2

        $results = Test-DbaDbQueryStore -SqlInstance $script:instance2 -ExcludeDatabase $dbname
        It 'Should return results' {
            $results | Should Not BeNullOrEmpty
        }
        It "Should not return results for $dbname" {
            ($results | Where-Object { $_.Database -eq $dbname }) | Should BeNullOrEmpty
        }
    }

    Context 'Function works with piping smo server object' {
        $svr = Connect-DbaInstance -SqlInstance $script:instance2

        $results = $svr | Test-DbaDbQueryStore
        It 'Should return results' {
            $results | Should Not BeNullOrEmpty
        }
        It 'Should show query store meets best practice' {
            ($results | Where-Object { $_.Database -eq $dbname -and $_.Name -eq 'ActualState' }).IsBestPractice | Should Be $true
        }
        It 'Should show trace flag 7745 meets best practice' {
            ($results | Where-Object { $_.Name -eq 'Trace Flag 7745 Enabled' }).IsBestPractice | Should Be $true
        }
    }
}