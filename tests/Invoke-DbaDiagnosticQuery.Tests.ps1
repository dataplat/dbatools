$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'Database', 'ExcludeDatabase', 'ExcludeQuery', 'SqlCredential', 'Path', 'QueryName', 'UseSelectionHelper', 'InstanceOnly', 'DatabaseSpecific', 'ExcludeQueryTextColumn', 'ExcludePlanColumn', 'NoColumnParsing', 'OutputPath', 'ExportQueries', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $script:PesterOutputPath = "TestDrive:$commandName"
        $database = "dbatoolsci_frk_$(Get-Random)"
        $database2 = "dbatoolsci_frk_$(Get-Random)"
        $database3 = "dbatoolsci_frk_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE [$database]")
        $server.Query("CREATE DATABASE [$database2]")
        $server.Query("CREATE DATABASE [$database3]")
    }
    AfterAll {
        @($database, $database2, $database3) | Foreach-Object {
            $db = $_
            $server.Query("IF DB_ID('$db') IS NOT NULL
                begin
                    print 'Dropping $db'
                    ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK immediate;
                    DROP DATABASE [$db];
                end")
        }

        Remove-Item $script:PesterOutputPath -Recurse -ErrorAction SilentlyContinue
    }
    AfterEach {
        Remove-Item $script:PesterOutputPath -Recurse -ErrorAction SilentlyContinue
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
        It "works with specific database provided" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'File Sizes and Space', 'Log Space Usage' -Database $database2, $database3
            @($results | Where-Object {$_.Database -eq $Database}).Count | Should -Be 0
            @($results | Where-Object {$_.Database -eq $Database2}).Count | Should -Be 2
            @($results | Where-Object {$_.Database -eq $Database3}).Count | Should -Be 2
        }
        It "works with Exclude Databases provided" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -ExcludeDatabase $database2
            @($results | Where-Object {$_.Database -eq $Database}).Count | Should -BeGreaterThan 1
            @($results | Where-Object {$_.Database -eq $Database2}).Count | Should -Be 0
        }
        It "Correctly excludes queries when QueryName and ExcludeQuery parameters are used" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'Version Info', 'Core Counts', 'Server Properties' -ExcludeQuery 'Core Counts' -WhatIf
            @($results).Count | Should be 2
        }
        It "Correctly excludes queries when only ExcludeQuery parameter is used" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -ExcludeQuery "Missing Index Warnings", "Buffer Usage" -whatif
            @($results).Count | Should -BeGreaterThan 0
            @($results | Where-Object Name -eq "Missing Index Warnings").Count | Should be 0
            @($results | Where-Object Name -eq "Buffer Usage").Count | Should be 0
        }

        $columnnames = 'Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'
        $TestCases = @()
        $columnnames.ForEach{$TestCases += @{columnname = $PSItem}}
        $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'Memory Clerk Usage'
        It "correctly excludes default column name <columnname>" -TestCases $TestCases {
            Param($columnname)
            @($results.Result | Get-Member | Where-Object Name -eq $columnname).Count | Should be 0
        }
    }

    context "verifying output when exporting queries as files instead of running" {

        It "exports queries to sql files without running" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -ExportQueries -QueryName 'Memory Clerk Usage' -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql).Count | Should -Be 1
        }

        It "exports single database specific query against single database" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2  -ExportQueries  -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database $database -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)"}).Count | Should -Be 1
        }

        It "exports a database specific query foreach specific database provided" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2  -ExportQueries  -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database @($database, $database2) -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)|($database2)"}).Count | Should -Be 2
        }

        It "exports database specific query when multiple specific databases are referenced" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -ExportQueries -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database @($database, $database2) -OutputPath $script:PesterOutputPath
            @(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)|($database2)"}).Count | Should -Be 2
        }

    }

    context "verifying output when running database specific queries" {
        It "runs database specific queries against single database only when providing database name" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database $database
            @($results).Count | Should -Be 1
        }

        It "runs database specific queries against set of databases when provided with multiple database names" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database @($database, $database2)
            @($results).Count |  Should -Be 2
        }
    }
}