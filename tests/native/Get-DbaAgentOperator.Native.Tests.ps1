#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentOperator",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.

Describe "Get-DbaAgentOperator native behavior" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeOperatorPrefix = "native_operator_$([Guid]::NewGuid().ToString("N"))"
        $nativeOperatorNames = @("${nativeOperatorPrefix}_a", "${nativeOperatorPrefix}_b")
        $nativeJobNames = @("${nativeOperatorPrefix}_job1", "${nativeOperatorPrefix}_job2")
        $nativeAlertName = "${nativeOperatorPrefix}_alert"
        $nativeAlertDatabaseName = "${nativeOperatorPrefix}_db"
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativeOperatorServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        foreach ($nativeOperatorName in $nativeOperatorNames) {
            $nativeFixtureOperator = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator($nativeOperatorServer.JobServer, $nativeOperatorName)
            $nativeFixtureOperator.EmailAddress = "native-test@example.invalid"
            $nativeFixtureOperator.Create()
        }
        foreach ($nativeJobName in $nativeJobNames) {
            $nativeFixtureJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($nativeOperatorServer.JobServer, $nativeJobName)
            $nativeFixtureJob.IsEnabled = $false
            $nativeFixtureJob.OperatorToEmail = $nativeOperatorNames[0]
            $nativeFixtureJob.EmailLevel = [Microsoft.SqlServer.Management.Smo.Agent.CompletionAction]::Always
            $nativeFixtureJob.Create()
            $nativeFixtureJob.ApplyToTargetServer("(local)")
        }
        # Existing instance-wide alerts use every severity; isolate this alert by database.
        $nativeFixtureDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database($nativeOperatorServer, $nativeAlertDatabaseName)
        $nativeFixtureDatabase.Create()
        $nativeFixtureAlert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert($nativeOperatorServer.JobServer, $nativeAlertName)
        $nativeFixtureAlert.Severity = 17
        $nativeFixtureAlert.DatabaseName = $nativeAlertDatabaseName
        $nativeFixtureAlert.IsEnabled = $false
        $nativeFixtureAlert.Create()
        $nativeFixtureAlert.AddNotification($nativeOperatorNames[0], [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]::NotifyEmail)
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        # Direct SMO cleanup does not depend on the retrieval command being correct.
        $nativeCleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $nativeCleanupServer.JobServer.Alerts.Refresh()
        $nativeCleanupAlert = $nativeCleanupServer.JobServer.Alerts[$nativeAlertName]
        if ($null -ne $nativeCleanupAlert) { $nativeCleanupAlert.Drop() }
        $nativeCleanupServer.JobServer.Jobs.Refresh()
        foreach ($nativeCleanupJobName in $nativeJobNames) {
            $nativeCleanupJob = $nativeCleanupServer.JobServer.Jobs[$nativeCleanupJobName]
            if ($null -ne $nativeCleanupJob) { $nativeCleanupJob.Drop() }
        }
        $nativeCleanupServer.JobServer.Operators.Refresh()
        foreach ($nativeCleanupOperatorName in $nativeOperatorNames) {
            $nativeCleanupOperator = $nativeCleanupServer.JobServer.Operators[$nativeCleanupOperatorName]
            if ($null -ne $nativeCleanupOperator) { $nativeCleanupOperator.Drop() }
        }
        $nativeCleanupServer.Databases.Refresh()
        $nativeCleanupDatabase = $nativeCleanupServer.Databases[$nativeAlertDatabaseName]
        if ($null -ne $nativeCleanupDatabase) { $nativeCleanupDatabase.Drop() }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "uses exact case-insensitive names, inclusion precedence and source truthiness" {
        $splatNativeFilters = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Operator        = @($nativeOperatorNames[0].ToUpperInvariant(), $nativeOperatorNames[0])
            ExcludeOperator = $nativeOperatorNames[0]
            EnableException = $true
        }
        $nativeFiltered = @(Get-DbaAgentOperator @splatNativeFilters)
        $nativeFiltered.Count | Should -Be 1
        $nativeFiltered[0].Name | Should -BeExactly $nativeOperatorNames[0]
        $splatNativeFilters.Operator = "${nativeOperatorPrefix}_*"
        @(Get-DbaAgentOperator @splatNativeFilters).Count | Should -Be 0
        $splatNativeFilters.Operator = @()
        $nativeExcluded = @(Get-DbaAgentOperator @splatNativeFilters)
        $nativeExcluded.Name | Should -Not -Contain $nativeOperatorNames[0]
        $nativeExcluded.Name | Should -Contain $nativeOperatorNames[1]
    }

    It "materializes filtered operators before downstream deletion" {
        foreach ($filterMode in @('Include', 'Exclude')) {
            $dropPrefix = 'native_operator_drop_' + [guid]::NewGuid().ToString('N')
            $dropNames = @("${dropPrefix}_a", "${dropPrefix}_b")
            $createdNames = New-Object 'System.Collections.Generic.List[string]'
            try {
                foreach ($name in $dropNames) {
                    $item = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator($nativeOperatorServer.JobServer, $name)
                    $item.Enabled = $false
                    $item.Create()
                    $createdNames.Add($name)
                }
                $nativeOperatorServer.JobServer.Operators.Refresh()
                $filter = @{ SqlInstance = $nativeOperatorServer; EnableException = $true }
                if ($filterMode -eq 'Include') {
                    $filter.Operator = $dropNames
                } else {
                    # Exclude every pre-existing operator so only this test's fixtures can be dropped.
                    $filter.ExcludeOperator = @($nativeOperatorServer.JobServer.Operators |
                        Where-Object { $_.Name -notin $dropNames } | ForEach-Object Name)
                    $filter.ExcludeOperator.Count | Should -BeGreaterThan 0
                }
                $dropped = @(Get-DbaAgentOperator @filter | ForEach-Object {
                    $name = $_.Name
                    $dropNames | Should -Contain $name
                    $_.Drop()
                    $name
                })
                $dropped.Count | Should -Be 2
                foreach ($name in $dropNames) { $dropped | Should -Contain $name }
                $nativeOperatorServer.JobServer.Operators.Refresh()
                foreach ($name in $dropNames) {
                    $nativeOperatorServer.JobServer.Operators[$name] | Should -BeNullOrEmpty
                }
                foreach ($name in $nativeOperatorNames) {
                    $nativeOperatorServer.JobServer.Operators[$name] | Should -Not -BeNullOrEmpty
                }
            } finally {
                $nativeOperatorServer.JobServer.Operators.Refresh()
                foreach ($name in $createdNames) {
                    $remaining = $nativeOperatorServer.JobServer.Operators[$name]
                    if ($null -ne $remaining) { $remaining.Drop() }
                }
            }
        }
    }

    It "reports the latest occurrence among all matching alerts" {
        $datePrefix = 'native_operator_date_' + [guid]::NewGuid().ToString('N')
        $dateOperator = $null
        $dateAlerts = New-Object 'System.Collections.Generic.List[object]'
        $dates = @([datetime]'2026-10-01T12:00:00', [datetime]'2026-10-02T13:00:00', [datetime]::MinValue)
        try {
            $dateOperator = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator($nativeOperatorServer.JobServer, $datePrefix)
            $dateOperator.Enabled = $false
            $dateOperator.Create()
            foreach ($index in 0..2) {
                $suffix = @('_a', '_m', '_z')[$index]
                $alert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert($nativeOperatorServer.JobServer, ($datePrefix + $suffix))
                $alert.DatabaseName = $nativeAlertDatabaseName
                $alert.Severity = 18 + $index
                $alert.IsEnabled = $false
                $alert.Create()
                $dateAlerts.Add($alert)
                $alert.AddNotification($datePrefix, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]::NotifyEmail)
            }
            $nativeOperatorServer.JobServer.Alerts.Refresh()
            foreach ($index in 0..2) {
                $cached = $nativeOperatorServer.JobServer.Alerts[$dateAlerts[$index].Name]
                # LastOccurrenceDate has a public SMO setter. Set controlled source values in
                # the caller-supplied SMO cache; do not fire alerts or send notifications.
                # Notification relationships are real SQL fixtures, queried by EnumNotifications.
                $cached.LastOccurrenceDate = $dates[$index]
                $cached.LastOccurrenceDate | Should -Be $dates[$index]
                $cached.EnumNotifications($datePrefix).Rows.Count | Should -Be 1
            }
            $output = @(Get-DbaAgentOperator -SqlInstance $nativeOperatorServer -Operator $datePrefix -EnableException)
            $output.Count | Should -Be 1
            $output[0].RelatedAlerts.Count | Should -Be 3
            foreach ($alert in $dateAlerts) { $output[0].RelatedAlerts | Should -Contain $alert.Name }
            $output[0].AlertLastEmail | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
            ([datetime]$output[0].AlertLastEmail) | Should -Be $dates[1]
        } finally {
            $nativeOperatorServer.JobServer.Alerts.Refresh()
            foreach ($alert in $dateAlerts) {
                $remaining = $nativeOperatorServer.JobServer.Alerts[$alert.Name]
                if ($null -ne $remaining) { $remaining.Drop() }
            }
            if ($null -ne $dateOperator) {
                $nativeOperatorServer.JobServer.Operators.Refresh()
                $remainingOperator = $nativeOperatorServer.JobServer.Operators[$datePrefix]
                if ($null -ne $remainingOperator) { $remainingOperator.Drop() }
            }
        }
    }

    It "returns SMO operators with notification relationships, date wrappers and display aliases" {
        $nativeFixtureAlert.Refresh()
        $nativeExpectedAlertDate = $nativeFixtureAlert.LastOccurrenceDate
        $splatNativeOutput = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Operator        = $nativeOperatorNames
            EnableException = $true
        }
        $nativeOutput = @(Get-DbaAgentOperator @splatNativeOutput)
        $nativeOutput.Count | Should -Be 2
        $nativeWithNotifications = $nativeOutput | Where-Object Name -EQ $nativeOperatorNames[0]
        $nativeWithoutNotifications = $nativeOutput | Where-Object Name -EQ $nativeOperatorNames[1]
        $nativeWithNotifications | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Operator
        @($nativeWithNotifications.RelatedJobs).Count | Should -Be 2
        foreach ($nativeExpectedJob in $nativeJobNames) { $nativeWithNotifications.RelatedJobs.Name | Should -Contain $nativeExpectedJob }
        $nativeWithoutNotifications.RelatedJobs | Should -BeNullOrEmpty
        $nativeWithNotifications.RelatedAlerts.GetType().FullName | Should -BeExactly "System.Object[]"
        $nativeWithNotifications.RelatedAlerts | Should -Contain $nativeAlertName
        $nativeWithoutNotifications.RelatedAlerts.Count | Should -Be 0
        $nativeWithNotifications.LastEmail | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        $nativeWithNotifications.AlertLastEmail | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        ([datetime]$nativeWithNotifications.AlertLastEmail) | Should -Be $nativeExpectedAlertDate
        $nativeWithoutNotifications.AlertLastEmail | Should -BeNullOrEmpty
        $nativeWithNotifications.IsEnabled | Should -Be $nativeWithNotifications.Enabled
        $nativeWithNotifications.PSObject.Properties["IsEnabled"].MemberType | Should -Be "AliasProperty"
        $nativeWithNotifications.ComputerName | Should -Not -BeNullOrEmpty
        $nativeWithNotifications.InstanceName | Should -Not -BeNullOrEmpty
        $nativeWithNotifications.SqlInstance | Should -Not -BeNullOrEmpty
        $nativeDisplay = @($nativeWithNotifications.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        ($nativeDisplay -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,ID,IsEnabled,EmailAddress,LastEmail"
    }

    It "does not inherit an alert date across pipeline records without another matching alert" {
        $nativeFixtureAlert.Refresh()
        $nativeExpectedRecordDate = $nativeFixtureAlert.LastOccurrenceDate
        $splatNativeCarry = @{
            Operator        = $nativeOperatorNames[0]
            EnableException = $true
        }
        try {
            $nativeCarried = @(& {
                    $TestConfig.InstanceSingle
                    $nativeFixtureAlert.RemoveNotification($nativeOperatorNames[0])
                    $TestConfig.InstanceSingle
                } | Get-DbaAgentOperator @splatNativeCarry | ForEach-Object {
                    # Snapshot each emission before the cached SMO object is decorated again.
                    [pscustomobject]@{
                        Alerts = @($PSItem.RelatedAlerts).Count
                        Date   = $PSItem.AlertLastEmail
                    }
                })
            $nativeCarried.Count | Should -Be 2
            $nativeCarried[0].Alerts | Should -Be 1
            $nativeCarried[0].Date | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
            ([datetime]$nativeCarried[0].Date) | Should -Be $nativeExpectedRecordDate
            $nativeCarried[1].Alerts | Should -Be 0
            $nativeCarried[1].Date | Should -BeNullOrEmpty
        } finally {
            $nativeFixtureAlert.AddNotification($nativeOperatorNames[0], [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]::NotifyEmail)
        }
    }

    It "warns on a failed middle record and continues without repeating earlier output" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $splatNativeContinue = @{
            Operator        = $nativeOperatorNames[0]
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeContinued = @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle | Get-DbaAgentOperator @splatNativeContinue)
        $nativeContinued.Count | Should -Be 2
        $nativeContinued[0].Name | Should -BeExactly $nativeOperatorNames[0]
        $nativeContinued[1].Name | Should -BeExactly $nativeOperatorNames[0]
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "streams output before EnableException terminates on a failed middle record" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        $splatNativeThrow = @{
            Operator        = $nativeOperatorNames[0]
            EnableException = $true
        }
        try {
            $TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle |
                Get-DbaAgentOperator @splatNativeThrow |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeStreamed[0].Name | Should -BeExactly $nativeOperatorNames[0]
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.Exception | Should -BeOfType System.Exception
        $nativeCaught.TargetObject.GetType().FullName | Should -BeExactly "System.String"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaAgentOperator SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $loginOperatorName = "native_operator_login_$([guid]::NewGuid().ToString("N"))"
        $splatLoginConnection = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        $loginOperatorServer = Connect-DbaInstance @splatLoginConnection
        $loginOperator = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator($loginOperatorServer.JobServer, $loginOperatorName)
        $loginOperator.Enabled = $false
        $loginOperator.Create()
    }

    AfterAll {
        if ($null -ne $loginOperatorServer) {
            $loginOperatorServer.JobServer.Operators.Refresh()
            $loginOperatorCleanup = $loginOperatorServer.JobServer.Operators[$loginOperatorName]
            if ($null -ne $loginOperatorCleanup) { $loginOperatorCleanup.Drop() }
        }
    }

    It "returns the requested operator with SQL credentials" {
        $splatLoginOperator = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            Operator        = $loginOperatorName
            EnableException = $true
        }
        $loginOperatorOutput = @(Get-DbaAgentOperator @splatLoginOperator)
        $loginOperatorOutput.Count | Should -Be 1
        $loginOperatorOutput[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Operator
        $loginOperatorOutput[0].Name | Should -BeExactly $loginOperatorName
        $loginOperatorOutput[0].IsEnabled | Should -BeFalse
        $loginOperatorOutput[0].RelatedJobs | Should -BeNullOrEmpty
        $loginOperatorOutput[0].RelatedAlerts.Count | Should -Be 0
    }

    It "warns without output when SQL credentials are omitted" {
        $loginOperatorWarnings = @()
        $splatLoginOperatorDenied = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Operator        = $loginOperatorName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "loginOperatorWarnings"
        }
        # Pin public/Get-DbaAgentOperator.ps1:120-124, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        @(Get-DbaAgentOperator @splatLoginOperatorDenied).Count | Should -Be 0
        $loginOperatorWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # The pinned function catches its Connect-DbaInstance failure and invokes Stop-Function directly.
        $splatLoginOperatorThrow = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Operator        = $loginOperatorName
            EnableException = $true
        }
        # Pin public/Get-DbaAgentOperator.ps1:120-124, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        { Get-DbaAgentOperator @splatLoginOperatorThrow } | Should -Throw
    }
}

Describe "Get-DbaAgentOperator Azure SQL Database" -Tag IntegrationTests {
    It "refuses Azure SQL Database before enumerating Agent operators" -Tag NativeChecklist:azure-sqldb {
        $azure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $resuming = $false
                for ($failure = $_.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in 40613, -2 -or $failure -is [System.TimeoutException] -or $failure.Message -match 'timed out|timeout|wait operation') { $resuming = $true }
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            @(Get-DbaAgentOperator -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match 'Azure SQL Database not supported'
            { Get-DbaAgentOperator -SqlInstance $azure -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally { $azure.ConnectionContext.Disconnect() }
    }
}
