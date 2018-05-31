# test ouput directory to confirm creation of test files
$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $script:PesterOutputPath = "TestDrive:$commandName"


        $database = "dbatoolsci_frk_$(Get-Random)"
        $database2 = "dbatoolsci_frk_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE [$database]")
        $server.Query("CREATE DATABASE [$database2]")

    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $server -Databases @($database, $database2) | Remove-DbaDatabase -Confirm:$false
        Remove-Item $script:PesterOutputPath -recurse -erroraction silentlycontinue

    }
    AfterEach {
        Remove-Item $script:PesterOutputPath -Recurse -erroraction silentlycontinue
    }


    Context "verifying output when running queries" {
        It "runs a specific query" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'Memory Clerk Usage'
            @($results).Count | Should -Be 1
        }
        It "works with DatabaseSpecific" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific
            @($results).Count | Should -BeGreaterThan 10
        }
        It "works with Exclude Databases provided" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -ExcludeDatabase $database2
            @($results | Where-Object {$_.DatabaseName -eq $Database1}).Count | Should -BeGreaterThan 1
            @($results | Where-Object {$_.DatabaseName -eq $Database2}).Count | Should -Be 0
        }
    }

    context "verifying output when exporting queries as files instead of running" {

        It "exports queries to sql files without running" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -ExportQueries -QueryName 'Memory Clerk Usage' -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql).Count | Should -Be 1
        }

        It "verifies returns object with required properties when running with whatif" {
            [System.Management.Automation.PSObject[]]$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -WhatIf

             $results.Count                                                             | Should -BeGreaterThan 10
            ($results.ComputerName     | Where-Object {$_ -eq $null}).Count             | Should -Be 0
            ($results.InstanceName     | Where-Object {$_ -eq $null}).Count             | Should -Be 0
            ($results.SqlInstance      | Where-Object {$_ -eq $null}).Count             | Should -Be 0
            ($results.Number           | Where-Object {$_ -eq $null}).Count             | Should -Be 0
            ($results.Name             | Where-Object {$_ -eq $null}).Count             | Should -Be 0
            ($results.Description      | Where-Object {$_ -eq $null}).Count             | Should -Be 0
            ($results.DatabaseSpecific | Where-Object {$_ -eq $null}).Count             | Should -Be 0
            $results.DatabaseName.Count                                                 | Should -Be $results.Count
            $results.Notes.Count                                                        | Should -Be $results.Count
            $results.Result.Count                                                       | Should -Be $results.Count
        }

        It "exports single database specific query against single database" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2  -ExportQueries  -DatabaseSpecific -QueryName 'Database-scoped Configurations' -databasename $database -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)"}).Count | Should -Be 1
        }

        It "exports a database specific query foreach specific database provided" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2  -ExportQueries  -DatabaseSpecific -QueryName 'Database-scoped Configurations' -databasename @($database, $database2) -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)|($database2)"}).Count | Should -Be 2
        }

        It "exports database specific query when multiple specific databases are referenced" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -ExportQueries -DatabaseSpecific -QueryName 'Database-scoped Configurations' -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)|($database2)"}).Count | Should -Be 2
        }

    }

    context "verifying output when running database specific queries" {
        It "runs database specific queries against single database only when providing database name" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -databasename $database
            @($results).Count | Should -Be 1
        }

        It "runs database specific queries against set of databases when provided with multiple database names" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -databasename @($database, $database2)
            @($results).Count |  Should -Be 2
        }
    }


}
