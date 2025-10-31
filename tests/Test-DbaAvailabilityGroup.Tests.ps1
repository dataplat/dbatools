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
                "HealthCheck",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $agName = "dbatoolsci_agroup_healthcheck"
        $dbName = "dbatoolsci_agdb_$(Get-Random)"

        $splatPrimary = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatPrimary

        $splatDatabase = @{
            SqlInstance = $TestConfig.instance3
            Name        = $dbName
            Owner       = "sa"
        }
        $null = New-DbaDatabase @splatDatabase

        $splatAddDatabase = @{
            SqlInstance       = $TestConfig.instance3
            AvailabilityGroup = $agName
            Database          = $dbName
            SeedingMode       = "Automatic"
        }
        $null = Add-DbaAgDatabase @splatAddDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When using -HealthCheck parameter" -Skip:$env:AppVeyor {
        It "Returns health check results with expected properties" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0

            $firstResult = $results | Select-Object -First 1
            $firstResult.ComputerName | Should -Not -BeNullOrEmpty
            $firstResult.InstanceName | Should -Not -BeNullOrEmpty
            $firstResult.SqlInstance | Should -Not -BeNullOrEmpty
            $firstResult.AvailabilityGroup | Should -Be $agName
            $firstResult.PrimaryReplica | Should -Not -BeNullOrEmpty
        }

        It "Returns replica-level health information" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $firstResult = $results | Select-Object -First 1

            $firstResult.ReplicaServerName | Should -Not -BeNullOrEmpty
            $firstResult.ReplicaRole | Should -BeIn @("Primary", "Secondary")
            $firstResult.ReplicaAvailabilityMode | Should -BeIn @("SynchronousCommit", "AsynchronousCommit")
            $firstResult.ReplicaFailoverMode | Should -BeIn @("Manual", "Automatic")
            $firstResult.ReplicaConnectionState | Should -BeIn @("Connected", "Disconnected")
            $firstResult.ReplicaJoinState | Should -BeIn @("Joined", "NotJoined")
            $firstResult.ReplicaSynchronizationState | Should -BeIn @("Synchronized", "Synchronizing", "NotSynchronizing", "PartiallyHealthy", "Healthy")
        }

        It "Returns database-level synchronization information" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $dbResult = $results | Where-Object DatabaseName -eq $dbName

            $dbResult | Should -Not -BeNullOrEmpty
            $dbResult.DatabaseName | Should -Be $dbName
            $dbResult.SynchronizationState | Should -BeIn @("Synchronized", "Synchronizing", "NotSynchronizing", "Initializing", "Reverting")
            $dbResult.PSObject.Properties.Name | Should -Contain "IsFailoverReady"
            $dbResult.PSObject.Properties.Name | Should -Contain "IsJoined"
            $dbResult.PSObject.Properties.Name | Should -Contain "IsSuspended"
            $dbResult.PSObject.Properties.Name | Should -Contain "SuspendReason"
        }

        It "Returns performance metrics for databases" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $firstResult = $results | Select-Object -First 1

            $firstResult.PSObject.Properties.Name | Should -Contain "LogSendQueueSize"
            $firstResult.PSObject.Properties.Name | Should -Contain "LogSendRate"
            $firstResult.PSObject.Properties.Name | Should -Contain "RedoQueueSize"
            $firstResult.PSObject.Properties.Name | Should -Contain "RedoRate"
            $firstResult.PSObject.Properties.Name | Should -Contain "FileStreamSendRate"
        }

        It "Returns LSN tracking information" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $firstResult = $results | Select-Object -First 1

            $firstResult.PSObject.Properties.Name | Should -Contain "LastCommitLSN"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastCommitTime"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastHardenedLSN"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastHardenedTime"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastReceivedLSN"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastReceivedTime"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastRedoneLSN"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastRedoneTime"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastSentLSN"
            $firstResult.PSObject.Properties.Name | Should -Contain "LastSentTime"
        }

        It "Returns recovery metrics" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $firstResult = $results | Select-Object -First 1

            $firstResult.PSObject.Properties.Name | Should -Contain "EstimatedRecoveryTime"
            $firstResult.PSObject.Properties.Name | Should -Contain "EstimatedDataLoss"
            $firstResult.PSObject.Properties.Name | Should -Contain "SynchronizationPerformance"
        }

        It "Works with Linux AGs (instance3 is Linux)" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
            $results.AvailabilityGroup | Should -Contain $agName
        }

        It "Returns multiple results when AG has multiple databases" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $secondDbName = "dbatoolsci_agdb2_$(Get-Random)"

            $splatDatabase2 = @{
                SqlInstance = $TestConfig.instance3
                Name        = $secondDbName
                Owner       = "sa"
            }
            $null = New-DbaDatabase @splatDatabase2

            $splatAddDatabase2 = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Database          = $secondDbName
                SeedingMode       = "Automatic"
            }
            $null = Add-DbaAgDatabase @splatAddDatabase2
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $results.Count | Should -BeGreaterOrEqual 2

            $dbNames = $results.DatabaseName | Select-Object -Unique
            $dbNames | Should -Contain $dbName
            $dbNames | Should -Contain $secondDbName

            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaAgDatabase -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -Database $secondDbName
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $secondDbName
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "When using -HealthCheck without AddDatabase compatibility" -Skip:$env:AppVeyor {
        It "Returns health check data without requiring database validation parameters" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $results | Should -Not -BeNullOrEmpty
            $results.AvailabilityGroup | Should -Contain $agName
        }

        It "Does not require primary replica connection when using -HealthCheck" {
            $results = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -HealthCheck
            $results | Should -Not -BeNullOrEmpty
        }
    }
}