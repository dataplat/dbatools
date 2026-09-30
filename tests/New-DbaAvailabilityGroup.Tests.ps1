#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAvailabilityGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Primary",
                "PrimarySqlCredential",
                "Secondary",
                "SecondarySqlCredential",
                "Name",
                "ReuseSystemDatabases",
                "IsContained",
                "DtcSupport",
                "ClusterType",
                "AutomatedBackupPreference",
                "FailureConditionLevel",
                "HealthCheckTimeout",
                "Basic",
                "DatabaseHealthTrigger",
                "Passthru",
                "Database",
                "SharedPath",
                "UseLastBackup",
                "Force",
                "AvailabilityMode",
                "FailoverMode",
                "BackupPriority",
                "ConnectionModeInPrimaryRole",
                "ConnectionModeInSecondaryRole",
                "SeedingMode",
                "Endpoint",
                "EndpointUrl",
                "Certificate",
                "ConfigureXESession",
                "IPAddress",
                "SubnetMask",
                "Port",
                "Dhcp",
                "ClusterConnectionOption",
                "MasterKeySecurePassword",
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

        # Explain what needs to be set up for the test:
        # To create an availability group, we need a database that has been backed up for database testing.

        # Set variables. They are available in all the It blocks.
        $agName = "dbatoolsci_addag_agroup"
        $dbName = "dbatoolsci_addag_agroupdb"
        $backupFilePath = "$backupPath\$dbName.bak"

        # Clean up any existing processes that might interfere
        $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceHadr -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue

        # Create the database and backup for testing
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbName
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbName -FilePath $backupFilePath

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        # Clean up availability group and endpoints after each test
        # Use SilentlyContinue to prevent SQL Server clustering errors from failing tests
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName -ErrorAction SilentlyContinue
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint -ErrorAction SilentlyContinue
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbName -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When SharedPath is not accessible" {
        It "Warns without eating an iteration of the caller's loop" {
            # The validation guards used to run Stop-Function -Continue without an enclosing loop -
            # the continue escaped the command before its own return statement ran and consumed an
            # iteration of this very loop, so the counter fell short (#10638).
            $loopCount = 0
            foreach ($i in 1..3) {
                $splatBadPath = @{
                    Primary       = $TestConfig.InstanceHadr
                    Name          = "dbatoolsci_agbadpath"
                    ClusterType   = "None"
                    FailoverMode  = "Manual"
                    SharedPath    = "Q:\dbatoolsci\does\not\exist"
                    WarningAction = "SilentlyContinue"
                }
                $null = New-DbaAvailabilityGroup @splatBadPath
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*Cannot access*"
        }
    }

    Context "When creating availability groups" {
        It "returns an ag with a db named" {
            $splatAg = @{
                Primary      = $TestConfig.InstanceHadr
                Name         = $agName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Database     = $dbName
                Certificate  = "dbatoolsci_AGCert"
            }
            $results = New-DbaAvailabilityGroup @splatAg
            $results.AvailabilityDatabases.Name | Should -Be $dbName
            $results.AvailabilityDatabases.Count | Should -Be 1 -Because "There should be only the named database in the group"
        }

        It "returns an ag with no database if one was not named" {
            $splatAgNoDb = @{
                Primary      = $TestConfig.InstanceHadr
                Name         = $agName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
            }
            $results = New-DbaAvailabilityGroup @splatAgNoDb
            $results.AvailabilityDatabases.Count | Should -Be 0 -Because "No database was named"
        }
    }

    Context "When the pipeline is stopped" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id with records but without a completed one. The pipeline is stopped as soon as the first
            # record arrives, which is what Ctrl+C does. WhatIf keeps the instance unchanged.
            $splatStopAg = @{
                Primary      = $TestConfig.InstanceHadr
                Name         = $agName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
                WhatIf       = $true
            }
            if ($TestConfig.SqlCred) {
                $splatStopAg.PrimarySqlCredential = $TestConfig.SqlCred
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", (Get-Module -Name $ModuleName | Select-Object -First 1).Path).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $null = $stopShell.AddCommand("New-DbaAvailabilityGroup").AddParameters($splatStopAg)
            $stopAsync = $stopShell.BeginInvoke()
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($stopShell.Streams.Progress.Count -eq 0 -and -not $stopAsync.IsCompleted -and $stopWatch.Elapsed.TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 10
            }
            $stopShell.Stop()
            $stopState = $stopShell.InvocationStateInfo.State
            $stopRecords = @($stopShell.Streams.Progress)
            $stopShell.Dispose()
            $stopRunspace.Dispose()
        }

        It "Was stopped while it was running" {
            $stopState | Should -Be "Stopped"
        }

        It "Completes its progress bar" {
            $completedIds = @($stopRecords | Where-Object RecordType -eq "Completed" | Select-Object -ExpandProperty ActivityId -Unique)
            $openIds = $stopRecords | Where-Object RecordType -eq "Processing" | Select-Object -ExpandProperty ActivityId -Unique | Where-Object { $PSItem -notin $completedIds }
            $stopRecords | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}