#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgReplica",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- Availability groups do not exist in Azure SQL Database (Microsoft Learn, "T-SQL differences between SQL Server and Azure SQL Database": high availability is built in, T-SQL statements related to availability groups are not supported, and the Always On dynamic management views are not supported); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.
# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads availability replicas.

Describe "Get-DbaAgReplica native" -Tag IntegrationTests {
    BeforeAll {
        $hadrInstance = $TestConfig.InstanceHadr
        $random = Get-Random

        # Own CLUSTER_TYPE NONE availability groups with unique names, as the pinned test builds one; AG01 is never touched.
        $agNameA = "dbatoolsci_agrep_a_$random"
        $agNameB = "dbatoolsci_agrep_b_$random"
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
        $agA = New-DbaAvailabilityGroup @splatAg
        $splatAg.Name = $agNameB
        $null = New-DbaAvailabilityGroup @splatAg
        $replicaName = $agA.PrimaryReplica

        $expectedDefaults = @(
            "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "Name", "Role", "ConnectionState",
            "RollupSynchronizationState", "AvailabilityMode", "BackupPriority", "EndpointUrl", "SessionTimeout",
            "FailoverMode", "ReadonlyRoutingList"
        )
    }

    AfterAll {
        # Every step runs even when an earlier one fails.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -Confirm:$false
        if (-not $endpointExisted) {
            $null = Get-DbaEndpoint -SqlInstance $hadrInstance -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        }
    }

    Context "Replicas of the availability groups" {
        It "returns the SMO replicas of the named groups with the pinned notes and default view" {
            $results = @(Get-DbaAgReplica -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -WarningVariable replicaWarnings -WarningAction SilentlyContinue)
            $replicaWarnings | Should -BeNullOrEmpty
            ($results.AvailabilityGroup | Sort-Object) | Should -Be @($agNameA, $agNameB)
            $results[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityReplica]

            $group = Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA
            $replicaA = $results | Where-Object AvailabilityGroup -eq $agNameA
            $replicaA.ComputerName | Should -Be $group.ComputerName
            $replicaA.InstanceName | Should -Be $group.InstanceName
            $replicaA.SqlInstance | Should -Be $group.SqlInstance
            $replicaA.Name | Should -Be $replicaName
            $replicaA.Replica | Should -Be $replicaName
            $replicaA.Role | Should -Be ([Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole]::Primary)
            $replicaA.AvailabilityMode | Should -Be "SynchronousCommit"
            $replicaA.FailoverMode | Should -Be "Manual"
            $replicaA.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be $expectedDefaults
        }

        It "filters -AvailabilityGroup case-insensitively, as the nested availability group lookup does" {
            $results = @(Get-DbaAgReplica -SqlInstance $hadrInstance -AvailabilityGroup $agNameB.ToUpperInvariant())
            $results.AvailabilityGroup | Should -Be $agNameB
        }

        It "filters with -Replica, comparing names case-insensitively" {
            $results = @(Get-DbaAgReplica -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Replica $replicaName.ToLowerInvariant())
            $results.Name | Should -Be $replicaName
            @(Get-DbaAgReplica -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Replica "dbatoolsci_noreplica_$random").Count | Should -Be 0
        }

        It "accepts availability groups from the pipeline" -Tag NativeChecklist:pipeline-multiple {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB | Get-DbaAgReplica -Replica $replicaName)
            ($results.AvailabilityGroup | Sort-Object) | Should -Be @($agNameA, $agNameB)
            ($results | Where-Object AvailabilityGroup -eq $agNameB).SqlInstance | Should -Be $agA.SqlInstance
        }
    }

    Context "An instance that cannot be reached" -Tag NativeChecklist:multi-instance-failure {
        BeforeAll {
            # "$SqlInstance" in the pinned message: the bound instances, joined by spaces.
            $missingFirst = "$([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]@($missingHost, $hadrInstance))"
            $missingSecond = "$([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]@($hadrInstance, $missingHost))"
        }

        It "warns for the whole lookup and returns nothing, as the nested -EnableException call ends it" {
            $results = @(Get-DbaAgReplica -SqlInstance $missingHost, $hadrInstance -AvailabilityGroup $agNameA -WarningVariable reachWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            "$reachWarnings" | Should -BeLike "*Failure on $missingFirst to obtain the availability group $agNameA*"
        }

        It "returns nothing either when the unreachable instance comes second" {
            $results = @(Get-DbaAgReplica -SqlInstance $hadrInstance, $missingHost -AvailabilityGroup $agNameA -WarningVariable lateWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            "$lateWarnings" | Should -BeLike "*Failure on $missingSecond to obtain the availability group $agNameA*"
        }

        It "throws the connection failure under -EnableException" {
            $thrown = $null
            try {
                $null = Get-DbaAgReplica -SqlInstance $missingHost -EnableException -WarningAction SilentlyContinue
            } catch {
                $thrown = $PSItem
            }
            "$thrown" | Should -Match "The network path was not found|No such host is known"
        }
    }

    Context "Neither an instance nor an input object" -Tag NativeChecklist:enable-exception {
        It "warns and returns nothing" {
            $results = Get-DbaAgReplica -WarningVariable noInputWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noInputWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }

        It "throws under -EnableException" {
            { Get-DbaAgReplica -EnableException } | Should -Throw "*You must supply either -SqlInstance or an Input Object*"
        }

        It "only warns for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            { $null = Get-DbaAgReplica -EnableException:$false -WarningAction SilentlyContinue } | Should -Not -Throw
            $results = Get-DbaAgReplica -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$falseWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            $missingAgName = "dbatoolsci_agrep_missing_$random"
        }

        # The pinned call adds -EnableException inside a try (public/Get-DbaAgReplica.ps1:110-117), so a failed nested
        # connect is reported by Get-DbaAgReplica's own Stop-Function, which honours the caller's -EnableException.
        It "works with -SqlCredential" {
            $results = Get-DbaAgReplica -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -AvailabilityGroup $missingAgName -WarningVariable loginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$loginWarnings" | Should -Not -BeLike "*Login failed*"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = Get-DbaAgReplica -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noLoginWarnings" | Should -BeLike "*Failure on $([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$loginInstance) to obtain the availability group $missingAgName*"
            "$noLoginWarnings" | Should -BeLike "*Login failed*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $thrown = $null
            try {
                $null = Get-DbaAgReplica -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -EnableException -WarningAction SilentlyContinue
            } catch {
                $thrown = $PSItem
            }
            "$thrown" | Should -BeLike "*Login failed*"
        }
    }

    Context "Availability group wildcards" {
        It "matches -AvailabilityGroup wildcards, as the help documents" {
            $results = @(Get-DbaAgReplica -SqlInstance $hadrInstance -AvailabilityGroup "dbatoolsci_agrep_?_$random" -WarningVariable wildcardWarnings -WarningAction SilentlyContinue)
            $wildcardWarnings | Should -BeNullOrEmpty
            ($results.AvailabilityGroup | Sort-Object) | Should -Be @($agNameA, $agNameB)
        }
    }
}

Describe "Native Get-DbaAgReplica refuses Azure SQL Database" -Tag IntegrationTests {
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
        @(Get-DbaAgReplica @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Failure on * to obtain the availability group*Azure SQL Database not supported*"
    }

    It "throws that Azure SQL Database is not supported under -EnableException, as its own Stop-Function does" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $thrown = $null
        $splatAzure = @{
            SqlInstance     = $azureServer
            EnableException = $true
            WarningAction   = "SilentlyContinue"
        }
        try {
            $null = Get-DbaAgReplica @splatAzure
        } catch {
            $thrown = $PSItem
        }
        "$thrown" | Should -BeLike "*Azure SQL Database not supported*"
    }
}
