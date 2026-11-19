#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgDatabaseReplicaState",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- Availability groups do not exist in Azure SQL Database (Microsoft Learn, "T-SQL differences between SQL Server and Azure SQL Database": high availability is built in, T-SQL statements related to availability groups are not supported, and the Always On dynamic management views are not supported); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.
# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads database replica states.

Describe "Get-DbaAgDatabaseReplicaState native" -Tag IntegrationTests {
    BeforeAll {
        $hadrInstance = $TestConfig.InstanceHadr
        $random = Get-Random

        # Own CLUSTER_TYPE NONE availability groups with unique names, as the pinned test builds one; AG01 is never touched.
        $agNameA = "dbatoolsci_agdbrs_a_$random"
        $agNameB = "dbatoolsci_agdbrs_b_$random"
        $dbAlpha = "dbatoolsci_agdbrs_alpha_$random"
        $dbBeta = "dbatoolsci_agdbrs_beta_$random"
        $dbGamma = "dbatoolsci_agdbrs_gamma_$random"
        $missingHost = "dbatoolsci-nohost-$random"

        $backupPath = "$($TestConfig.Temp)\$CommandName-native-$random"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Only an endpoint this file creates is removed again.
        $endpointExisted = @(Get-DbaEndpoint -SqlInstance $hadrInstance -Type DatabaseMirroring -EnableException).Count -gt 0

        $splatAg = @{
            Primary         = $hadrInstance
            Name            = $agNameA
            ClusterType     = "None"
            FailoverMode    = "Manual"
            Certificate     = "dbatoolsci_AGCert"
            EnableException = $true
        }
        $null = New-DbaAvailabilityGroup @splatAg
        $splatAg.Name = $agNameB
        $null = New-DbaAvailabilityGroup @splatAg

        $null = New-DbaDatabase -SqlInstance $hadrInstance -Name $dbAlpha, $dbBeta, $dbGamma -EnableException
        foreach ($dbName in $dbAlpha, $dbBeta, $dbGamma) {
            $null = Backup-DbaDatabase -SqlInstance $hadrInstance -Database $dbName -Path $backupPath -Type Full -EnableException
        }
        $null = Add-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Database $dbAlpha -EnableException
        $null = Add-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Database $dbBeta -EnableException
        $null = Add-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameB -Database $dbGamma -EnableException

        $expectedProperties = @(
            "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "PrimaryReplica", "ReplicaServerName",
            "ReplicaRole", "ReplicaAvailabilityMode", "ReplicaFailoverMode", "ReplicaConnectionState", "ReplicaJoinState",
            "ReplicaSynchronizationState", "DatabaseName", "SynchronizationState", "IsFailoverReady", "IsJoined",
            "IsSuspended", "SuspendReason", "EstimatedRecoveryTime", "EstimatedDataLoss", "SynchronizationPerformance",
            "LogSendQueueSize", "LogSendRate", "RedoQueueSize", "RedoRate", "FileStreamSendRate", "EndOfLogLSN",
            "RecoveryLSN", "TruncationLSN", "LastCommitLSN", "LastCommitTime", "LastHardenedLSN", "LastHardenedTime",
            "LastReceivedLSN", "LastReceivedTime", "LastRedoneLSN", "LastRedoneTime", "LastSentLSN", "LastSentTime"
        )
    }

    AfterAll {
        # Every step runs even when an earlier one fails.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -Confirm:$false
        if (-not $endpointExisted) {
            $null = Get-DbaEndpoint -SqlInstance $hadrInstance -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        }
        $null = Remove-DbaDatabase -SqlInstance $hadrInstance -Database $dbAlpha, $dbBeta, $dbGamma -Confirm:$false
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "Database replica states of the availability groups" {
        It "returns one object per database and replica with the pinned properties, in order, from the replica state" {
            $results = @(Get-DbaAgDatabaseReplicaState -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -WarningVariable stateWarnings -WarningAction SilentlyContinue)
            $stateWarnings | Should -BeNullOrEmpty
            ($results.DatabaseName | Sort-Object) | Should -Be @($dbAlpha, $dbBeta, $dbGamma)
            $results[0].PSObject.TypeNames[0] | Should -Be "System.Management.Automation.PSCustomObject"
            $results[0].PSObject.Properties.Name | Should -Be $expectedProperties

            $group = Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA
            $replica = $group.AvailabilityReplicas | Select-Object -First 1
            $state = $group.DatabaseReplicaStates | Where-Object AvailabilityDatabaseName -eq $dbAlpha
            $alpha = $results | Where-Object DatabaseName -eq $dbAlpha
            $alpha.ComputerName | Should -Be $group.ComputerName
            $alpha.InstanceName | Should -Be $group.InstanceName
            $alpha.SqlInstance | Should -Be $group.SqlInstance
            $alpha.AvailabilityGroup | Should -Be $agNameA
            $alpha.PrimaryReplica | Should -Be $group.PrimaryReplicaServerName
            $alpha.ReplicaServerName | Should -Be $state.AvailabilityReplicaServerName
            $alpha.ReplicaRole | Should -Be ([Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole]::Primary)
            $alpha.ReplicaRole | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole]
            $alpha.ReplicaAvailabilityMode | Should -Be $replica.AvailabilityMode
            $alpha.ReplicaFailoverMode | Should -Be $replica.FailoverMode
            $alpha.ReplicaJoinState | Should -Be $replica.JoinState
            $alpha.SynchronizationState | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityDatabaseSynchronizationState]
            $alpha.IsJoined | Should -BeTrue
            $alpha.IsSuspended | Should -Be $state.IsSuspended
            $alpha.SuspendReason | Should -Be $state.SuspendReason
            ($results | Where-Object DatabaseName -eq $dbGamma).AvailabilityGroup | Should -Be $agNameB
        }

        It "filters with -Database, comparing names case-insensitively" {
            $results = @(Get-DbaAgDatabaseReplicaState -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Database $dbAlpha.ToUpperInvariant())
            $results.DatabaseName | Should -Be $dbAlpha
        }

        It "filters -AvailabilityGroup case-insensitively, as the nested availability group lookup does" {
            $results = @(Get-DbaAgDatabaseReplicaState -SqlInstance $hadrInstance -AvailabilityGroup $agNameB.ToUpperInvariant())
            $results.DatabaseName | Should -Be $dbGamma
        }

        It "accepts availability groups from the pipeline" -Tag NativeChecklist:pipeline-multiple {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB | Get-DbaAgDatabaseReplicaState -Database $dbAlpha, $dbGamma)
            ($results.DatabaseName | Sort-Object) | Should -Be @($dbAlpha, $dbGamma)
            ($results | Where-Object DatabaseName -eq $dbGamma).AvailabilityGroup | Should -Be $agNameB
            ($results | Where-Object DatabaseName -eq $dbAlpha).AvailabilityGroup | Should -Be $agNameA
        }
    }

    Context "An instance that cannot be reached" -Tag NativeChecklist:multi-instance-failure {
        It "warns for that instance and returns the other's replica states" {
            $results = @(Get-DbaAgDatabaseReplicaState -SqlInstance $missingHost, $hadrInstance -AvailabilityGroup $agNameA -WarningVariable reachWarnings -WarningAction SilentlyContinue)
            ($results.DatabaseName | Sort-Object) | Should -Be @($dbAlpha, $dbBeta)
            "$reachWarnings" | Should -BeLike "*Get-DbaAvailabilityGroup*Failure*"
        }

        It "only warns under -EnableException, as the nested availability group lookup does" {
            $results = @(Get-DbaAgDatabaseReplicaState -SqlInstance $missingHost, $hadrInstance -AvailabilityGroup $agNameA -EnableException -WarningVariable strictWarnings -WarningAction SilentlyContinue)
            ($results.DatabaseName | Sort-Object) | Should -Be @($dbAlpha, $dbBeta)
            "$strictWarnings" | Should -BeLike "*Failure*"
        }
    }

    Context "Neither an instance nor an input object" -Tag NativeChecklist:enable-exception {
        It "warns and returns nothing" {
            $results = Get-DbaAgDatabaseReplicaState -WarningVariable noInputWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noInputWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }

        It "throws under -EnableException" {
            { Get-DbaAgDatabaseReplicaState -EnableException } | Should -Throw "*You must supply either -SqlInstance or an Input Object*"
        }

        It "only warns for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            { $null = Get-DbaAgDatabaseReplicaState -EnableException:$false -WarningAction SilentlyContinue } | Should -Not -Throw
            $results = Get-DbaAgDatabaseReplicaState -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$falseWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            $missingAgName = "dbatoolsci_agdbrs_missing_$random"
        }

        It "works with -SqlCredential" {
            $results = Get-DbaAgDatabaseReplicaState -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -AvailabilityGroup $missingAgName -WarningVariable loginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$loginWarnings" | Should -Not -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = Get-DbaAgDatabaseReplicaState -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noLoginWarnings" | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $results = Get-DbaAgDatabaseReplicaState -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -EnableException -WarningVariable strictLoginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$strictLoginWarnings" | Should -BeLike "*Failure*"
        }
    }
}

Describe "Native Get-DbaAgDatabaseReplicaState refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Get-DbaAgDatabaseReplicaState @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "only warns for Azure SQL Database under -EnableException, as the nested availability group lookup does" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $strictAzureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            EnableException = $true
            WarningVariable = "strictAzureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Get-DbaAgDatabaseReplicaState @splatAzure).Count | Should -Be 0
        ($strictAzureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }
}
