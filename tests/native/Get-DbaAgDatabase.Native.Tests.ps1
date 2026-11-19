#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- Availability groups do not exist in Azure SQL Database (Microsoft Learn, "T-SQL differences between SQL Server and Azure SQL Database": high availability is built in, T-SQL statements related to availability groups are not supported, and the Always On dynamic management views are not supported); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.
# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads availability group databases.

Describe "Get-DbaAgDatabase native" -Tag IntegrationTests {
    BeforeAll {
        $hadrInstance = $TestConfig.InstanceHadr
        $random = Get-Random

        # Own CLUSTER_TYPE NONE availability groups with unique names, as the pinned test builds one; AG01 is never touched.
        $agNameA = "dbatoolsci_agdbn_a_$random"
        $agNameB = "dbatoolsci_agdbn_b_$random"
        $dbAlpha = "dbatoolsci_agdbn_alpha_$random"
        $dbBeta = "dbatoolsci_agdbn_beta_$random"
        $dbGamma = "dbatoolsci_agdbn_gamma_$random"
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

        # The nested Get-DbaAvailabilityGroup's Stop-Function record reaches the caller's -ErrorVariable in every call mode on both
        # editions (Get-DbaClientProtocol pin probes 236550ae and 86cfbcd7; watchman 22dc72e0, correction nested-error-variable).
        # The pin's id carries ",Stop-Function" and its list also holds the record of the connect call the nested function caught:
        # the accepted differences stop-record-id-stem-and-activity and omitted-consequential-records, so the id is matched by its stem.
        $nestedStem = "^dbatools_Get-DbaAvailabilityGroup(,|$)"

        # The engine's own record for the pinned $name -match $pattern with an invalid pattern, on this leg.
        $expectedFault = $null
        try { $null = "dbatoolsci" -match "[" } catch { $expectedFault = $PSItem }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaAgDatabase @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaAgDatabase -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaAgDatabase", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript($Script).AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        function Assert-NativePatternFault {
            param($Record)
            $Record.Exception.GetType().FullName | Should -BeExactly $expectedFault.Exception.GetType().FullName
            $Record.Exception.Message | Should -BeExactly $expectedFault.Exception.Message
            $Record.CategoryInfo.Category | Should -Be $expectedFault.CategoryInfo.Category
            $Record.TargetObject | Should -Be $expectedFault.TargetObject
            ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly ($expectedFault.FullyQualifiedErrorId -split ",")[0]
        }
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

    Context "Databases of the availability groups" {
        It "returns each database with its availability group, replica role and instance" {
            $results = @(Get-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -WarningVariable agWarnings -WarningAction SilentlyContinue)
            $agWarnings | Should -BeNullOrEmpty
            ($results.Name | Sort-Object) | Should -Be @($dbAlpha, $dbBeta, $dbGamma)
            ($results | Where-Object Name -eq $dbGamma).AvailabilityGroup | Should -Be $agNameB
            ($results | Where-Object Name -eq $dbAlpha).AvailabilityGroup | Should -Be $agNameA
            $results.LocalReplicaRole | Select-Object -Unique | Should -Be "Primary"
            $results[0].ComputerName | Should -Not -BeNullOrEmpty
            $results[0].InstanceName | Should -Not -BeNullOrEmpty
            $results[0].SqlInstance | Should -Not -BeNullOrEmpty
            $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "LocalReplicaRole", "Name", "SynchronizationState", "IsFailoverReady", "IsJoined", "IsSuspended")
        }

        It "filters with -Database and -ExcludeDatabase" {
            $included = @(Get-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Database $dbAlpha)
            $included.Name | Should -Be $dbAlpha
            $excluded = @(Get-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -ExcludeDatabase $dbAlpha)
            $excluded.Name | Should -Be $dbBeta
        }

        It "filters with -Pattern as a case-insensitive regular expression" {
            $pattern = "^DBATOOLSCI_AGDBN_(ALPHA|GAMMA)_" + $random + "$"
            $results = @(Get-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -Pattern $pattern)
            ($results.Name | Sort-Object) | Should -Be @($dbAlpha, $dbGamma)
        }

        It "ends the command with the pinned -match fault for an invalid -Pattern inside a caller try" {
            # The pinned $matchesPattern runs $name -match $pattern; an invalid pattern raises the engine's
            # statement-terminating fault, which a caller try catches before any later pattern is tried.
            # The expected record is the engine's own for that statement form, on this leg.
            $expectedFault = $null
            try { $null = "dbatoolsci" -match "[" } catch { $expectedFault = $PSItem }
            $expectedFault | Should -Not -BeNullOrEmpty
            $patternOutput = @()
            $patternFault = $null
            try {
                $patternOutput = @(Get-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Pattern "[", ".*")
            } catch {
                $patternFault = $PSItem
            }
            $patternOutput.Count | Should -Be 0
            $patternFault | Should -Not -BeNullOrEmpty
            $patternFault.Exception.GetType().FullName | Should -BeExactly $expectedFault.Exception.GetType().FullName
            $patternFault.Exception.Message | Should -BeExactly $expectedFault.Exception.Message
            $patternFault.CategoryInfo.Category | Should -Be $expectedFault.CategoryInfo.Category
            $patternFault.TargetObject | Should -Be $expectedFault.TargetObject
            ($patternFault.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly ($expectedFault.FullyQualifiedErrorId -split ",")[0]
        }

        It "outside any try, a plain call writes the -match fault for each database and goes on to the next pattern" {
            # The pinned -match fault ends only its own statement there, so the loop tries the next pattern, ".*" matches,
            # and the script's next statement runs.
            $groupA = Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -EnableException
            $outside = Invoke-NativeOutsideTry @{ InputObject = $groupA; Pattern = "[", ".*" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 0
            $outside.Output.Count | Should -Be 3
            (@($outside.Output[0].Name, $outside.Output[1].Name) | Sort-Object) | Should -Be @($dbAlpha, $dbBeta)
            $outside.Output[2] | Should -BeExactly "next statement"
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativePatternFault $record
            }

            # With no valid pattern no database is selected; each still writes the fault.
            $outside = Invoke-NativeOutsideTry @{ InputObject = $groupA; Pattern = "[" }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Output -join ",") | Should -BeExactly "next statement"
            $outside.Errors.Count | Should -Be 2
        }

        It "outside any try, -EnableException ends the command at the -match fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $groupA = Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -EnableException
            $outside = Invoke-NativeOutsideTry @{ InputObject = $groupA; Pattern = "[", ".*"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativePatternFault $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns the -match fault into the stop PowerShell gives WriteError" {
            $groupA = Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -EnableException
            $outside = Invoke-NativeOutsideTry @{ InputObject = $groupA; Pattern = "[", ".*"; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativePatternFault $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }

        It "inside a caller try, -ErrorAction Stop and -EnableException end the command with the -match fault" {
            foreach ($form in @(@{ ErrorAction = "Stop" }, @{ EnableException = $true })) {
                $patternOutput = @()
                $patternFault = $null
                try {
                    $patternOutput = @(Get-DbaAgDatabase -SqlInstance $hadrInstance -AvailabilityGroup $agNameA -Pattern "[", ".*" @form)
                } catch {
                    $patternFault = $PSItem
                }
                $patternOutput.Count | Should -Be 0
                $patternFault | Should -Not -BeNullOrEmpty
                Assert-NativePatternFault $patternFault
            }
        }

        It "accepts availability groups from the pipeline" -Tag NativeChecklist:pipeline-multiple {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB | Get-DbaAgDatabase -ExcludeDatabase $dbBeta)
            ($results.Name | Sort-Object) | Should -Be @($dbAlpha, $dbGamma)
            ($results | Where-Object Name -eq $dbGamma).AvailabilityGroup | Should -Be $agNameB
        }
    }

    Context "An instance that cannot be reached" -Tag NativeChecklist:multi-instance-failure {
        It "warns for that instance and returns the other's databases" {
            $reachErrors = @()
            $results = @(Get-DbaAgDatabase -SqlInstance $missingHost, $hadrInstance -AvailabilityGroup $agNameA -WarningVariable reachWarnings -WarningAction SilentlyContinue -ErrorVariable reachErrors)
            ($results.Name | Sort-Object) | Should -Be @($dbAlpha, $dbBeta)
            $reachWarnings | Should -HaveCount 1
            "$reachWarnings" | Should -BeLike "*Get-DbaAvailabilityGroup*Failure*"
            # -ErrorVariable holds the nested Get-DbaAvailabilityGroup's connection record for that instance, nothing else.
            $reachErrors.Count | Should -Be 1
            $reachErrors[0].FullyQualifiedErrorId | Should -Match $nestedStem
            $reachErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
            "$($reachErrors[0].TargetObject)" | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$missingHost).FullSmoName
            "$reachWarnings".EndsWith("Failure | " + $reachErrors[0].Exception.Message) | Should -BeTrue
        }

        It "only warns under -EnableException, as the nested availability group lookup does" {
            $strictErrors = @()
            $results = @(Get-DbaAgDatabase -SqlInstance $missingHost, $hadrInstance -AvailabilityGroup $agNameA -EnableException -WarningVariable strictWarnings -WarningAction SilentlyContinue -ErrorVariable strictErrors)
            ($results.Name | Sort-Object) | Should -Be @($dbAlpha, $dbBeta)
            "$strictWarnings" | Should -BeLike "*Failure*"
            # The nested call never carries -EnableException, so its record still reaches -ErrorVariable.
            $strictErrors.Count | Should -Be 1
            $strictErrors[0].FullyQualifiedErrorId | Should -Match $nestedStem
            $strictErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "Neither an instance nor an input object" -Tag NativeChecklist:enable-exception {
        It "warns and returns nothing" {
            $results = Get-DbaAgDatabase -WarningVariable noInputWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noInputWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }

        It "throws under -EnableException" {
            { Get-DbaAgDatabase -EnableException } | Should -Throw "*You must supply either -SqlInstance or an Input Object*"
        }

        It "only warns for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            { $null = Get-DbaAgDatabase -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue } | Should -Not -Throw
            $results = Get-DbaAgDatabase -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$falseWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            $missingAgName = "dbatoolsci_agdbn_missing_$random"
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb, manager 243aa465c620): no commit can run the pinned function, because the base
        # 9ed45c8a3 already ships the compiled Get-DbaAgDatabase cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgDatabase.ps1:165-167 (the nested call passes no -EnableException)
        #         if ($SqlInstance) {
        #             $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        #         }
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAvailabilityGroup.ps1:118-126
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        #             if (-not $server.IsHadrEnabled) {
        #                 Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue
        #
        # Without the credential the nested connect fails and its Stop-Function -Continue warns "Failure" and moves
        # on; Get-DbaAvailabilityGroup's $EnableException is unset, so it warns and never throws, also when the
        # caller passes -EnableException to Get-DbaAgDatabase. Nothing between the two swallows or rethrows it.
        It "works with -SqlCredential" {
            $results = Get-DbaAgDatabase -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -AvailabilityGroup $missingAgName -WarningVariable loginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$loginWarnings" | Should -Not -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginErrors = @()
            $results = Get-DbaAgDatabase -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue -ErrorVariable noLoginErrors
            $results | Should -BeNullOrEmpty
            "$noLoginWarnings" | Should -BeLike "*Failure*"
            $noLoginErrors.Count | Should -Be 1
            $noLoginErrors[0].FullyQualifiedErrorId | Should -Match $nestedStem
            $noLoginErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
            $noLoginErrors[0].Exception.Message | Should -Match "^Login failed"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $strictLoginErrors = @()
            $results = Get-DbaAgDatabase -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -EnableException -WarningVariable strictLoginWarnings -WarningAction SilentlyContinue -ErrorVariable strictLoginErrors
            $results | Should -BeNullOrEmpty
            "$strictLoginWarnings" | Should -BeLike "*Failure*"
            $strictLoginErrors.Count | Should -Be 1
            $strictLoginErrors[0].FullyQualifiedErrorId | Should -Match $nestedStem
            $strictLoginErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Get-DbaAgDatabase refuses Azure SQL Database" -Tag IntegrationTests {
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
            ErrorVariable   = "azureErrors"
        }
        @(Get-DbaAgDatabase @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        # The nested Get-DbaAvailabilityGroup's refusal record reaches -ErrorVariable (watchman 22dc72e0), nothing else.
        $azureErrors.Count | Should -Be 1
        $azureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaAvailabilityGroup(,|$)"
        $azureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        $azureErrors[0].Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "only warns for Azure SQL Database under -EnableException, as the nested availability group lookup does" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $strictAzureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            EnableException = $true
            WarningVariable = "strictAzureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorVariable   = "strictAzureErrors"
        }
        @(Get-DbaAgDatabase @splatAzure).Count | Should -Be 0
        ($strictAzureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        $strictAzureErrors.Count | Should -Be 1
        $strictAzureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaAvailabilityGroup(,|$)"
        $strictAzureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
    }
}
