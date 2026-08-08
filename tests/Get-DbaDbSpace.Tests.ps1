#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSpace",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "IncludeSystemDBs",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Set variables. They are available in all the It blocks.
        $dbName = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $server.Query("Create Database [$dbName]")

        # A standby database is the regression fixture. Its Status reads "Normal, Standby" while
        # IsAccessible stays true and the space query answers normally, so the old status test
        # turned away a database the command can read perfectly well. A log shipping secondary is
        # exactly where a DBA wants to watch file space, so this is the case that has to keep working.
        $standbyDb = "dbatoolsci_standby_$(Get-Random)"
        $standbyBackup = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Path $backupPath -Type Full
        $splatStandby = @{
            SqlInstance         = $TestConfig.InstanceSingle
            Path                = $standbyBackup.BackupPath
            DatabaseName        = $standbyDb
            StandbyDirectory    = $backupPath
            ReplaceDbNameInFile = $true
        }
        $null = Restore-DbaDatabase @splatStandby

        # A database that cannot be opened at all. Taking one offline is the cheapest way to get
        # IsAccessible false, and the command cannot tell one inaccessible state from another.
        $offlineDb = "dbatoolsci_offlinespace_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $offlineDb
        $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -Offline -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $standbyDb -ErrorAction SilentlyContinue

        # An offline database has to be brought back online before it can be dropped.
        $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -Online -Force -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace" {
        BeforeAll {
            # The BeforeAll of this file keeps an offline database around, so every scan over the whole
            # instance warns about it. That warning is expected and is asserted in the context below,
            # so it is silenced here to keep the test run free of warnings.
            $allResults = @(Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue | Where-Object Database -eq $dbName)
        }

        It "Gets results" {
            $allResults | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve space for $dbName" {
            $allResults[0].Database | Should -Be $dbName
            $allResults[0].UsedSpace | Should -Not -BeNullOrEmpty
        }

        It "Should have a physical path for $dbName" {
            $allResults[0].PhysicalName | Should -Not -BeNullOrEmpty
        }
    }

    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace when using -Database" {
        BeforeAll {
            $databaseResults = @(Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -Database $dbName)
        }

        It "Gets results" {
            $databaseResults | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve space for $dbName" {
            $databaseResults[0].Database | Should -Be $dbName
            $databaseResults[0].UsedSpace | Should -Not -BeNullOrEmpty
        }

        It "Should have a physical path for $dbName" {
            $databaseResults[0].PhysicalName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets no DbSpace for specific database when using -ExcludeDatabase" {
        It "Gets no results for excluded database" {
            $excludeResults = @(Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbName -WarningAction SilentlyContinue)
            $excludeResults.Database | Should -Not -Contain $dbName
        }
    }

    Context "Databases the command can read but the status test turned away" {
        It "Returns file space for a standby database" {
            $standbyResults = @(Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -Database $standbyDb)
            $standbyResults | Should -Not -BeNullOrEmpty
            $standbyResults[0].Database | Should -Be $standbyDb
        }

        It "Does not claim a standby database is inaccessible" {
            $null = Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -Database $standbyDb
            ($WarnVar -join " ") | Should -Not -Match "not accessible"
        }

        It "Includes the standby database in a whole instance scan" {
            $scanResults = Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $scanResults.Database | Should -Contain $standbyDb
        }
    }

    Context "Databases that cannot be opened" {
        It "Warns rather than returning nothing when the database is named" {
            # The warning is what these tests are about, so it is silenced on the stream and asserted
            # on $WarnVar instead. A test run must not print warnings.
            $offlineResults = Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -WarningAction SilentlyContinue
            $offlineResults | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -Match ([regex]::Escape($offlineDb))
        }

        It "Says the database was skipped because it is not accessible" {
            $null = Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -WarningAction SilentlyContinue
            ($WarnVar -join " ") | Should -Match "not accessible"
        }

        It "Still returns the accessible databases in a whole instance scan" {
            $scanResults = Get-DbaDbSpace -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $scanResults.Database | Should -Contain $dbName
            $scanResults.Database | Should -Not -Contain $offlineDb
        }
    }
}