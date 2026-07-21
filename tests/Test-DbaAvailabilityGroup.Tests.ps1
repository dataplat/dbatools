#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAvailabilityGroup",
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
                "AvailabilityGroup",
                "Secondary",
                "SecondarySqlCredential",
                "AddDatabase",
                "SeedingMode",
                "SharedPath",
                "UseLastBackup",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: a prior revision recorded the live readiness test (replica connection
    # state, seeding/backup prerequisites) as DEFERRED-TO-AG01, but that was wrong - InstanceSingle
    # IS the AG01 primary: it hosts a healthy Availability Group whose LocalReplicaRole is Primary
    # with all replicas Connected across a primary and two secondaries, so the live readiness leg
    # and the full -AddDatabase secondary walk are characterized here rather than deferred (same
    # correction TA-085/TA-086 made). The legs discover their AG from the instance and
    # Set-ItResult -Skipped if the instance hosts no healthy primary AG, so they stay honest on a
    # lab that lacks one. Both -SqlInstance and -AvailabilityGroup are Mandatory and the command
    # connects before any guard, so there is no connection-independent leg. This command is
    # read-only ([CmdletBinding()] with no SupportsShouldProcess), so no WhatIf is passed.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random

        # Discover a healthy AG this instance is the PRIMARY of, with every replica Connected -
        # the state the readiness path requires before it emits. Derived, so the legs hold on any
        # lab rather than pinning this one's AG name.
        $healthyAg = Get-DbaAvailabilityGroup -SqlInstance $server |
            Where-Object {
                $PSItem.LocalReplicaRole -eq "Primary" -and
                @($PSItem.AvailabilityReplicas | Where-Object ConnectionState -ne "Connected").Count -eq 0
            } | Select-Object -First 1

        if ($healthyAg) {
            $agName = $healthyAg.Name
            $secondaryReplicaNames = @($healthyAg.AvailabilityReplicas | Where-Object Role -eq "Secondary").Name

            # A self-contained candidate database for the -AddDatabase success emit: Full recovery
            # and Normal status (the two prerequisites the command checks), backed up so its
            # LastBackupDate.Year is not 1 (otherwise the automatic-seeding replicas trip the
            # "never backed up" guard and no object is emitted), and NOT yet in the AG.
            $addDbName = "dbatoolsci_agready_$random"
            $splatNewDb = @{
                SqlInstance     = $server
                Name            = $addDbName
                RecoveryModel   = "Full"
                EnableException = $true
            }
            $null = New-DbaDatabase @splatNewDb
            $splatBackup = @{
                SqlInstance     = $server
                Database        = $addDbName
                Type            = "Full"
                EnableException = $true
            }
            $null = Backup-DbaDatabase @splatBackup
        }
    }

    AfterAll {
        if ($healthyAg -and $addDbName) {
            $splatRemove = @{
                SqlInstance     = $server
                Database        = $addDbName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemove -ErrorAction SilentlyContinue
        }
    }

    Context "Guarding before the readiness test" {
        It "Warns once and returns nothing when the requested Availability Group does not exist" {
            $absentName = "dbatoolsci_noag_$random"
            $splatAbsentAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = $absentName
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Test-DbaAvailabilityGroup @splatAbsentAg)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Availability Group $absentName not found on $server."
        }
    }

    Context "Testing a healthy Availability Group" {
        It "Emits one object with the documented four-property base shape when -AddDatabase is not used" {
            if (-not $healthyAg) {
                Set-ItResult -Skipped -Because "this instance is not the primary of a healthy Availability Group"
                return
            }

            $splatBase = @{
                SqlInstance       = $server
                AvailabilityGroup = $agName
            }
            $result = @(Test-DbaAvailabilityGroup @splatBase)
            $result.Count | Should -Be 1

            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup")
            $result[0].PSObject.Properties.Name | Sort-Object | Should -Be ($expectedProperties | Sort-Object)
            $result[0].AvailabilityGroup | Should -Be $agName
        }
    }

    Context "Validating -AddDatabase prerequisites" {
        It "Warns and returns nothing when the database to add does not exist" {
            if (-not $healthyAg) {
                Set-ItResult -Skipped -Because "this instance is not the primary of a healthy Availability Group"
                return
            }

            $missingDb = "dbatoolsci_nodb_$random"
            $splatMissing = @{
                SqlInstance       = $server
                AvailabilityGroup = $agName
                AddDatabase       = $missingDb
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Test-DbaAvailabilityGroup @splatMissing)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            # $server stringifies with its own brackets (e.g. [sql01]); the source interpolates it bare
            $payload | Should -Be "Database [$missingDb] is not found on $server."
        }

        It "Emits the documented eleven-property object per database when the candidate is ready" {
            if (-not $healthyAg) {
                Set-ItResult -Skipped -Because "this instance is not the primary of a healthy Availability Group"
                return
            }

            $splatAdd = @{
                SqlInstance       = $server
                AvailabilityGroup = $agName
                AddDatabase       = $addDbName
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Test-DbaAvailabilityGroup @splatAdd)
            $warn.Count | Should -Be 0
            $result.Count | Should -Be 1

            $addObject = $result[0]
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AvailabilityGroupName",
                "DatabaseName",
                "AvailabilityGroupSMO",
                "DatabaseSMO",
                "PrimaryServerSMO",
                "ReplicaServerSMO",
                "RestoreNeeded",
                "Backups"
            )
            $addObject.PSObject.Properties.Name | Sort-Object | Should -Be ($expectedProperties | Sort-Object)
            $addObject.AvailabilityGroupName | Should -Be $agName
            $addObject.DatabaseName | Should -Be $addDbName

            # the secondary walk connected to every secondary replica and stored its SMO keyed by
            # replica name (hashtable keys are case-insensitive, so exact casing does not matter)
            $addObject.ReplicaServerSMO.Count | Should -Be $secondaryReplicaNames.Count
            foreach ($replicaName in $secondaryReplicaNames) {
                $addObject.ReplicaServerSMO.ContainsKey($replicaName) | Should -BeTrue
            }

            # automatic-seeding replicas with a backed-up database need no restore, and without
            # -UseLastBackup no backup history is attached
            $addObject.RestoreNeeded.Count | Should -Be 0
            @($addObject.Backups).Count | Should -Be 0
        }
    }
}