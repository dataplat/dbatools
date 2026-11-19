#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAvailabilityGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads availability groups.
# Azure SQL Database: availability groups do not exist there (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#t-sql-syntax-not-supported-in-azure-sql-database: high availability is built in, and T-SQL statements related to availability groups are not supported); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does (correction azure-unsupported), tested below.

Describe "Get-DbaAvailabilityGroup native" -Tag IntegrationTests {
    BeforeAll {
        $hadrInstance = $TestConfig.InstanceHadr
        $random = Get-Random

        # Own CLUSTER_TYPE NONE availability groups with unique names, as the pinned test builds one; AG01 is never touched.
        $agNameA = "dbatoolsci_agavg_a_$random"
        $agNameB = "dbatoolsci_agavg_b_$random"
        $missingHost = "dbatoolsci-nohost-$random"

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

        $hadrServer = Connect-DbaInstance -SqlInstance $hadrInstance -EnableException
    }

    AfterAll {
        # Every step runs even when an earlier one fails.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -Confirm:$false
        if (-not $endpointExisted) {
            $null = Get-DbaEndpoint -SqlInstance $hadrInstance -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        }
    }

    Context "Availability groups of an instance" {
        It "returns the group with its instance properties and the pinned default display set" {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA)
            $results | Should -HaveCount 1
            $results[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.AvailabilityGroup
            $results[0].Name | Should -BeExactly $agNameA
            $results[0].AvailabilityGroup | Should -BeExactly $agNameA
            $results[0].PrimaryReplica | Should -Be $results[0].PrimaryReplicaServerName
            $results[0].ComputerName | Should -Be $hadrServer.ComputerName
            $results[0].InstanceName | Should -Be $hadrServer.ServiceName
            $results[0].SqlInstance | Should -Be $hadrServer.DomainInstanceName
            $results[0].PSObject.Properties["IsPrimary"] | Should -BeNullOrEmpty
            $defaultView = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            @($defaultView) | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "LocalReplicaRole", "AvailabilityGroup", "PrimaryReplica", "ClusterType", "DtcSupportEnabled", "AutomatedBackupPreference", "AvailabilityReplicas", "AvailabilityDatabases", "AvailabilityGroupListeners")
        }

        It "filters -AvailabilityGroup case-insensitively, as -in does" {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameB.ToUpperInvariant(), "dbatoolsci_agavg_none_$random")
            ($results.Name -join ",") | Should -BeExactly $agNameB
            @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup "dbatoolsci_agavg_none_$random").Count | Should -Be 0
        }

        It "returns every group of the instance without -AvailabilityGroup" {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance)
            $results.Name | Should -Contain $agNameA
            $results.Name | Should -Contain $agNameB
            $results.Count | Should -Be $hadrServer.AvailabilityGroups.Count
        }

        It "with -IsPrimary adds IsPrimary from LocalReplicaRole and shows the pinned five-property view" {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -IsPrimary)
            $results.Count | Should -BeGreaterThan 1
            foreach ($result in $results) {
                $result.IsPrimary | Should -BeOfType System.Boolean
                $result.IsPrimary | Should -Be ($result.LocalReplicaRole.ToString() -eq "Primary")
                $defaultView = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                @($defaultView) | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "IsPrimary")
            }
            ($results | Where-Object Name -eq $agNameA).IsPrimary | Should -BeTrue
            ($results | Where-Object Name -eq $agNameA).AvailabilityGroup | Should -BeExactly $agNameA
        }

        It "with -IsPrimary:`$false keeps the default view" -Tag NativeChecklist:switch-false {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -IsPrimary:$false)
            $results | Should -HaveCount 1
            $results[0].PSObject.Properties["IsPrimary"] | Should -BeNullOrEmpty
            @($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -HaveCount 12
        }

        It "accepts instances from the pipeline" -Tag NativeChecklist:pipeline-multiple {
            $results = @($hadrInstance, $hadrInstance | Get-DbaAvailabilityGroup -AvailabilityGroup $agNameA, $agNameB)
            ($results.Name -join ",") | Should -BeExactly ((@($hadrServer.AvailabilityGroups | Where-Object Name -in $agNameA, $agNameB | ForEach-Object Name) * 2) -join ",")
        }

        It "matches -AvailabilityGroup wildcards, as the help documents" {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup "dbatoolsci_agavg_?_$random" -WarningVariable wildcardWarnings -WarningAction SilentlyContinue)
            $wildcardWarnings | Should -BeNullOrEmpty
            ($results.Name | Sort-Object) | Should -Be @($agNameA, $agNameB)
        }
    }

    Context "An instance that cannot be reached" -Tag NativeChecklist:multi-instance-failure {
        It "warns for that instance and returns the other's groups" {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $missingHost, $hadrInstance -AvailabilityGroup $agNameA -WarningVariable reachWarnings -WarningAction SilentlyContinue)
            ($results.Name -join ",") | Should -BeExactly $agNameA
            $reachWarnings | Should -HaveCount 1
            "$reachWarnings" | Should -BeLike "*Get-DbaAvailabilityGroup*Failure*"
        }

        It "returns the earlier instance's groups, then throws the connection error under -EnableException" -Tag NativeChecklist:enable-exception {
            $strictRows = New-Object System.Collections.Generic.List[object]
            $strictCaught = $null
            try {
                Get-DbaAvailabilityGroup -SqlInstance $hadrInstance, $missingHost -AvailabilityGroup $agNameA -EnableException | ForEach-Object { $strictRows.Add($PSItem) }
            } catch {
                $strictCaught = $PSItem
            }
            ($strictRows.Name -join ",") | Should -BeExactly $agNameA
            $strictCaught | Should -Not -BeNullOrEmpty
            $strictCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
            $strictCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaAvailabilityGroup*"
        }

        It "only warns for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseCaught = $null
            $falseWarnings = $null
            try {
                $results = @(Get-DbaAvailabilityGroup -SqlInstance $missingHost -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            } catch {
                $falseCaught = $PSItem
            }
            $falseCaught | Should -BeNullOrEmpty
            $results.Count | Should -Be 0
            "$falseWarnings" | Should -BeLike "*Get-DbaAvailabilityGroup*Failure*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            $missingAgName = "dbatoolsci_agavg_missing_$random"
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base already ships the
        # compiled Get-DbaAvailabilityGroup cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAvailabilityGroup.ps1:118-127
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        #             if (-not $server.IsHadrEnabled) {
        #                 Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue
        #             }
        #
        # Without the credential the connect fails and Stop-Function -Continue warns "Failure" and moves on;
        # under -EnableException that Stop-Function throws the ConnectionError record. With the credential the
        # connect succeeds, so no "Failure" warning: the instance's groups, or the HADR warning when it is off.
        It "works with -SqlCredential" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -AvailabilityGroup $missingAgName -WarningVariable loginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$loginWarnings" | Should -Not -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noLoginWarnings" | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException: a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaAvailabilityGroup -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Get-DbaAvailabilityGroup refuses Azure SQL Database" -Tag IntegrationTests {
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

    It "warns that Azure SQL Database is not supported and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Get-DbaAvailabilityGroup @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaAvailabilityGroup -SqlInstance $azureServer -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}
