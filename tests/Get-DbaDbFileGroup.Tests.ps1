#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileGroup",
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
                "InputObject",
                "FileGroup",
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
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $multifgdb = "dbatoolsci_multifgdb$random"

        # Remove any existing database before creating
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $multifgdb

        # Create the test database with multiple filegroups
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("CREATE DATABASE $multifgdb; ALTER DATABASE $multifgdb ADD FILEGROUP [Test1]; ALTER DATABASE $multifgdb ADD FILEGROUP [Test2];")

        # A database that cannot be opened. Taking one offline is the cheapest way to get
        # IsAccessible false, and the command cannot tell one inaccessible state from another.
        $offlineDb = "dbatoolsci_offlinefg$random"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $offlineDb
        $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -Offline -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $multifgdb -ErrorAction SilentlyContinue

        # An offline database has to be brought back online before it can be dropped.
        $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -Online -Force -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Returns values for Instance" {
        BeforeAll {
            # The BeforeAll of this file keeps an offline database around, so every scan over the whole
            # instance warns about it. That warning is expected and is asserted in the context below,
            # so it is silenced here to keep the test run free of warnings.
            $results = Get-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Returns the correct object" {
            $results[0].GetType().ToString() | Should -Be "Microsoft.SqlServer.Management.Smo.FileGroup"
        }
    }

    Context "Accepts database and filegroup input" {
        BeforeAll {
            $allFileGroupResults = Get-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -Database $multifgdb
            $singleFileGroupResult = Get-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -Database $multifgdb -FileGroup Test1
        }

        It "Reports the right number of filegroups for database" {
            $allFileGroupResults.Count | Should -BeExactly 3
        }

        It "Reports the right number of filegroups for specific filegroup" {
            $singleFileGroupResult.Count | Should -BeExactly 1
        }
    }

    Context "Accepts piped input" {
        BeforeAll {
            $pipedResults = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeUser | Get-DbaDbFileGroup
        }

        It "Reports the right number of filegroups" {
            $pipedResults.Count | Should -BeExactly 4
        }

        It "Excludes User Databases" {
            $pipedResults.Parent.Name | Should -Not -Contain $multifgdb
            $pipedResults.Parent.Name | Should -Contain "msdb"
        }
    }

    Context "Databases that cannot be opened" {
        It "Warns rather than returning nothing when the database is named" {
            # The warning is what these tests are about, so it is silenced on the stream and asserted
            # on $WarnVar instead. A test run must not print warnings.
            $offlineResults = Get-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -WarningAction SilentlyContinue
            $offlineResults | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -Match ([regex]::Escape($offlineDb))
        }

        It "Says the database was skipped because it is not accessible" {
            $null = Get-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -WarningAction SilentlyContinue
            ($WarnVar -join " ") | Should -Match "not accessible"
        }

        It "Names the instance in the warning" {
            $null = Get-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -WarningAction SilentlyContinue
            ($WarnVar -join " ") | Should -Match ([regex]::Escape($TestConfig.InstanceSingle))
        }

        It "Still returns the accessible databases in a whole instance scan" {
            $scanResults = Get-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $scanResults.Parent.Name | Should -Contain $multifgdb
            $scanResults.Parent.Name | Should -Not -Contain $offlineDb
        }

        It "Stays quiet about a piped database that -Database narrowed away" {
            # On the pipeline path every database the caller piped in arrives in $InputObject, so
            # the name filter has to run before the accessibility test. Otherwise a database they
            # narrowed away is still reported as skipped. Collect the databases in their own
            # statement so the warning variable holds what Get-DbaDbFileGroup wrote, not what
            # Get-DbaDatabase wrote.
            $allDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $narrowedResults = $allDbs | Get-DbaDbFileGroup -Database $multifgdb
            $narrowedResults.Parent.Name | Should -Contain $multifgdb
            ($WarnVar -join " ") | Should -Not -Match ([regex]::Escape($offlineDb))
        }
    }
}