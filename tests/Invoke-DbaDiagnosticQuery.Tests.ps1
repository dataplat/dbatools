param($ModuleName = 'dbatools')

Describe "Invoke-DbaDiagnosticQuery" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $env:PesterOutputPath = "TestDrive:$commandName"
        $database = "dbatoolsci_frk_$(Get-Random)"
        $database2 = "dbatoolsci_frk_$(Get-Random)"
        $database3 = "dbatoolsci_frk_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $server.Query("CREATE DATABASE [$database]")
        $server.Query("CREATE DATABASE [$database2]")
        $server.Query("CREATE DATABASE [$database3]")
    }

    AfterAll {
        @($database, $database2, $database3) | ForEach-Object {
            $db = $_
            $server.Query("IF DB_ID('$db') IS NOT NULL
                begin
                    print 'Dropping $db'
                    ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK immediate;
                    DROP DATABASE [$db];
                end")
        }

        Remove-Item $env:PesterOutputPath -Recurse -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item $env:PesterOutputPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDiagnosticQuery
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have ExcludeQuery as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeQuery -Type Object[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.IO.FileInfo
        }
        It "Should have QueryName as a parameter" {
            $CommandUnderTest | Should -HaveParameter QueryName -Type String[]
        }
        It "Should have UseSelectionHelper as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter UseSelectionHelper -Type Switch
        }
        It "Should have InstanceOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter InstanceOnly -Type Switch
        }
        It "Should have DatabaseSpecific as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseSpecific -Type Switch
        }
        It "Should have ExcludeQueryTextColumn as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeQueryTextColumn -Type Switch
        }
        It "Should have ExcludePlanColumn as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludePlanColumn -Type Switch
        }
        It "Should have NoColumnParsing as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoColumnParsing -Type Switch
        }
        It "Should have OutputPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutputPath -Type String
        }
        It "Should have ExportQueries as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExportQueries -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "verifying output when running queries" {
        It "runs a specific query" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -QueryName 'Memory Clerk Usage'
            @($results).Count | Should -Be 1
        }
        It "works with DatabaseSpecific" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -DatabaseSpecific
            @($results).Count | Should -BeGreaterThan 10
        }
        It "works with specific database provided" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -QueryName 'File Sizes and Space', 'Log Space Usage' -Database $database2, $database3
            @($results | Where-Object {$_.Database -eq $Database}).Count | Should -Be 0
            @($results | Where-Object {$_.Database -eq $Database2}).Count | Should -Be 2
            @($results | Where-Object {$_.Database -eq $Database3}).Count | Should -Be 2
        }
        It "works with Exclude Databases provided" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -DatabaseSpecific -ExcludeDatabase $database2
            @($results | Where-Object {$_.Database -eq $Database}).Count | Should -BeGreaterThan 1
            @($results | Where-Object {$_.Database -eq $Database2}).Count | Should -Be 0
        }
        It "Correctly excludes queries when QueryName and ExcludeQuery parameters are used" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -QueryName 'Version Info', 'Core Counts', 'Server Properties' -ExcludeQuery 'Core Counts'
            @($results).Count | Should -Be 2
        }
        It "Correctly excludes queries when only ExcludeQuery parameter is used" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -ExcludeQuery "Missing Index Warnings", "Buffer Usage"
            @($results).Count | Should -BeGreaterThan 0
            @($results | Where-Object Name -eq "Missing Index Warnings").Count | Should -Be 0
            @($results | Where-Object Name -eq "Buffer Usage").Count | Should -Be 0
        }

        BeforeAll {
            $columnnames = 'Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -QueryName 'Memory Clerk Usage'
        }
        It "correctly excludes default column name <_>" -ForEach $columnnames {
            @($results.Result | Get-Member | Where-Object Name -eq $_).Count | Should -Be 0
        }
    }

    Context "verifying output when exporting queries as files instead of running" {
        It "exports queries to sql files without running" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -ExportQueries -QueryName 'Memory Clerk Usage' -OutputPath $env:PesterOutputPath
            @(Get-ChildItem -path $env:PesterOutputPath -filter *.sql).Count | Should -Be 1
        }

        It "exports single database specific query against single database" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2  -ExportQueries  -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database $database -OutputPath $env:PesterOutputPath
            @(Get-ChildItem -path $env:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)"}).Count | Should -Be 1
        }

        It "exports a database specific query foreach specific database provided" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2  -ExportQueries  -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database @($database, $database2) -OutputPath $env:PesterOutputPath
            @(Get-ChildItem -path $env:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)|($database2)"}).Count | Should -Be 2
        }

        It "exports database specific query when multiple specific databases are referenced" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -ExportQueries -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database @($database, $database2) -OutputPath $env:PesterOutputPath
            @(Get-ChildItem -path $env:PesterOutputPath -filter *.sql | Where-Object {$_.FullName -match "($database)|($database2)"}).Count | Should -Be 2
        }
    }

    Context "verifying output when running database specific queries" {
        It "runs database specific queries against single database only when providing database name" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database $database
            @($results).Count | Should -Be 1
        }

        It "runs database specific queries against set of databases when provided with multiple database names" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -Database @($database, $database2)
            @($results).Count |  Should -Be 2
        }
    }
}
