#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Suspend-DbaAgDbDataMovement",
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
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $backupPath = "$($TestConfig.Temp)\$CommandName"
        $null = New-Item -Path $backupPath -ItemType Directory
        $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceHadr -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr
        $agname = "dbatoolsci_suspendagdb_agroup"
        $dbname = "dbatoolsci_suspendagdb_agroupdb-$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Name $dbname
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath -Type Log
        $ag = New-DbaAvailabilityGroup -Primary $TestConfig.InstanceHadr -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Certificate dbatoolsci_AGCert -UseLastBackup
        $null = Get-DbaAgDatabase -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname | Resume-DbaAgDbDataMovement
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname
        Remove-Item -Path $backupPath -Recurse
    }
    Context "Suspends data movement" {
        BeforeAll {
            # Resume data movement first so we can suspend and capture the output
            $null = Get-DbaAgDatabase -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname | Resume-DbaAgDbDataMovement -ErrorAction SilentlyContinue
            $results = Suspend-DbaAgDbDataMovement -SqlInstance $TestConfig.InstanceHadr -Database $dbname -Confirm:$false
            $script:outputForValidation = $results
        }

        It "Should return suspended results" {
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $dbname
            $results.SynchronizationState | Should -Be 'NotSynchronizing'
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                if (-not $script:outputForValidation) {
                    Set-ItResult -Skipped -Because "Suspend-DbaAgDbDataMovement returned no output in this environment"
                }
                $script:outputForValidation[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AvailabilityDatabase"
            }

            It "Has the expected default display properties" {
                if (-not $script:outputForValidation) {
                    Set-ItResult -Skipped -Because "Suspend-DbaAgDbDataMovement returned no output in this environment"
                }
                $defaultProps = $script:outputForValidation[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "AvailabilityGroup",
                    "LocalReplicaRole",
                    "Name",
                    "SynchronizationState",
                    "IsFailoverReady",
                    "IsJoined",
                    "IsSuspended"
                )
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }
        }
    }
}