$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemView', 'View', 'InputObject', 'EnableException'
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $viewName = ("dbatoolsci_{0}" -f $(Get-Random))
        $server.Query("CREATE VIEW $viewName AS (SELECT 1 as col1)", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP VIEW $viewName", 'tempdb')
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbView -SqlInstance $script:instance2 -Database tempdb
        }
        It "Should have standard properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance'.Split(',')
            ($results[0].PsObject.Properties.Name | Where-Object { $_ -in $ExpectedProps } | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Should get test view: $viewName" {
            ($results | Where-Object Name -eq $viewName).Name | Should -Be $viewName
        }
        It "Should include system views" {
            ($results | Where-Object IsSystemObject -eq $true).Count | Should -BeGreaterThan 0
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no views from master database" {
            $results = Get-DbaDbView -SqlInstance $script:instance2 -ExcludeDatabase master
            'master' | Should -Not -BeIn $results.Database
        }
        It "Should exclude system views" {
            $results = Get-DbaDbView -SqlInstance $script:instance2 -Database master -ExcludeSystemView
            ($results | Where-Object IsSystemObject -eq $true).Count | Should -Be 0
        }
    }

    Context "Piping workings" {
        It "Should allow piping from string" {
            $results = $script:instance2 | Get-DbaDbView -Database tempdb
            ($results | Where-Object Name -eq $viewName).Name | Should -Be $viewName
        }
        It "Should allow piping from Get-DbaDatabase" {
            $results = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb | Get-DbaDbView
            ($results | Where-Object Name -eq $viewName).Name | Should -Be $viewName
        }
    }
}