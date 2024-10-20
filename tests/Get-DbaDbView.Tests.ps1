param($ModuleName = 'dbatools')

Describe "Get-DbaDbView Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbView
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "ExcludeSystemView",
            "View",
            "Schema",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaDbView Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $SkipAzureTests = [Environment]::GetEnvironmentVariable('azuredbpasswd') -ne "failstoooften"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $viewName = ("dbatoolsci_{0}" -f $(Get-Random))
        $viewNameWithSchema = ("dbatoolsci_{0}" -f $(Get-Random))
        $server.Query("CREATE VIEW $viewName AS (SELECT 1 as col1)", 'tempdb')
        $server.Query("CREATE SCHEMA [someschema]", 'tempdb')
        $server.Query("CREATE VIEW [someschema].$viewNameWithSchema AS (SELECT 1 as col1)", 'tempdb')
    }

    AfterAll {
        $null = $server.Query("DROP VIEW $viewName", 'tempdb')
        $null = $server.Query("DROP VIEW [someschema].$viewNameWithSchema", 'tempdb')
        $null = $server.Query("DROP SCHEMA [someschema]", 'tempdb')
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbView -SqlInstance $global:instance2 -Database tempdb
        }
        It "Should have standard properties" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance'
            $results[0].PsObject.Properties.Name | Should -Contain $ExpectedProps
        }
        It "Should get test view: $viewName" {
            $results | Where-Object Name -eq $viewName | Select-Object -ExpandProperty Name | Should -Be $viewName
        }
        It "Should include system views" {
            ($results | Where-Object IsSystemObject -eq $true).Count | Should -BeGreaterThan 0
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no views from master database" {
            $results = Get-DbaDbView -SqlInstance $global:instance2 -ExcludeDatabase master
            $results.Database | Should -Not -Contain 'master'
        }
        It "Should exclude system views" {
            $results = Get-DbaDbView -SqlInstance $global:instance2 -Database master -ExcludeSystemView
            $results | Where-Object IsSystemObject -eq $true | Should -BeNullOrEmpty
        }
    }

    Context "Piping works" {
        It "Should allow piping from string" {
            $results = $global:instance2 | Get-DbaDbView -Database tempdb
            $results | Where-Object Name -eq $viewName | Select-Object -ExpandProperty Name | Should -Be $viewName
        }
        It "Should allow piping from Get-DbaDatabase" {
            $results = Get-DbaDatabase -SqlInstance $global:instance2 -Database tempdb | Get-DbaDbView
            $results | Where-Object Name -eq $viewName | Select-Object -ExpandProperty Name | Should -Be $viewName
        }
    }

    Context "Schema parameter (see #9445)" {
        It "Should return just one view with schema 'someschema'" {
            $results = $global:instance2 | Get-DbaDbView -Database tempdb -Schema 'someschema'
            $results | Where-Object Name -eq $viewNameWithSchema | Select-Object -ExpandProperty Name | Should -Be $viewNameWithSchema
            $results | Where-Object Schema -ne 'someschema' | Should -BeNullOrEmpty
        }
    }
}
