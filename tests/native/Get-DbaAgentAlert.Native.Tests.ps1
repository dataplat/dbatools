#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- Read-only retrieval; the pinned command does not support ShouldProcess.
# NativeChecklist: azure-sqldb N/A -- SQL Server Agent alerts are instance-scoped and unavailable in Azure SQL Database.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentAlert",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Get-DbaAgentAlert native behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativePrefix = "native_alert_$([Guid]::NewGuid().ToString("N"))"
        $nativeNames = @("${nativePrefix}_a", "${nativePrefix}_b")
        $nativeDatabaseName = "${nativePrefix}_db"
        $nativeOperatorName = "${nativePrefix}_operator"
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativeDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database($nativeServer, $nativeDatabaseName)
        $nativeDatabase.Create()
        $nativeOperator = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator($nativeServer.JobServer, $nativeOperatorName)
        $nativeOperator.EmailAddress = "native-test@example.invalid"
        $nativeOperator.Create()
        for ($nativeIndex = 0; $nativeIndex -lt $nativeNames.Count; $nativeIndex++) {
            $nativeAlert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert($nativeServer.JobServer, $nativeNames[$nativeIndex])
            $nativeAlert.DatabaseName = $nativeDatabaseName
            $nativeAlert.Severity = 17 + $nativeIndex
            $nativeAlert.IsEnabled = $false
            $nativeAlert.Create()
            if ($nativeIndex -eq 0) {
                $nativeAlert.AddNotification($nativeOperatorName, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]::NotifyEmail)
            }
        }
    }

    AfterAll {
        $nativeCleanup = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeCleanup.JobServer.Alerts.Refresh()
        foreach ($nativeName in $nativeNames) {
            $nativeCleanupAlert = $nativeCleanup.JobServer.Alerts[$nativeName]
            if ($null -ne $nativeCleanupAlert) { $nativeCleanupAlert.Drop() }
        }
        $nativeCleanup.JobServer.Operators.Refresh()
        $nativeCleanupOperator = $nativeCleanup.JobServer.Operators[$nativeOperatorName]
        if ($null -ne $nativeCleanupOperator) { $nativeCleanupOperator.Drop() }
        $nativeCleanup.Databases.Refresh()
        $nativeCleanupDatabase = $nativeCleanup.Databases[$nativeDatabaseName]
        if ($null -ne $nativeCleanupDatabase) { $nativeCleanupDatabase.Drop() }
    }

    It "preserves wildcard order, duplicates, exclusions, notifications and output types" {
        $splatNativeFilters = @{
            SqlInstance     = $nativeServer
            Alert           = @("${nativePrefix}_?", $nativeNames[0].ToUpperInvariant())
            EnableException = $true
        }
        $nativeOutput = @(Get-DbaAgentAlert @splatNativeFilters)
        $nativeOutput.Count | Should -Be 3
        ($nativeOutput.Name -join ",") | Should -BeExactly "$($nativeNames[0]),$($nativeNames[1]),$($nativeNames[0])"
        $nativeFirst = $nativeOutput[0]
        $nativeFirst | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Alert
        $nativeFirst.LastRaised | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        $nativeFirst.Notifications.GetType().FullName | Should -BeExactly "System.Data.DataTable"
        $nativeFirst.Notifications.Rows.Count | Should -Be 1
        $nativeOutput[1].Notifications.Rows.Count | Should -Be 0
        $nativeFirst.ComputerName | Should -Not -BeNullOrEmpty
        $nativeFirst.InstanceName | Should -Not -BeNullOrEmpty
        $nativeFirst.SqlInstance | Should -Not -BeNullOrEmpty
        ($nativeFirst.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,SqlInstance,InstanceName,Name,ID,JobName,AlertType,CategoryName,Severity,MessageId,IsEnabled,DelayBetweenResponses,LastRaised,OccurrenceCount"
        $splatNativeFilters.ExcludeAlert = "${nativePrefix}_a"
        $nativeExcluded = @(Get-DbaAgentAlert @splatNativeFilters)
        $nativeExcluded.Count | Should -Be 1
        $nativeExcluded[0].Name | Should -BeExactly $nativeNames[1]
        $splatNativeFilters.Alert = @()
        @(Get-DbaAgentAlert @splatNativeFilters).Count | Should -Be 0
        $splatNativeFilters.Alert = $null
        @(Get-DbaAgentAlert @splatNativeFilters).Count | Should -Be 0
    }

    It "warns for a failed middle instance and continues" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $splatNativeContinue = @{
            Alert           = $nativeNames[0]
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeOutput = @($nativeServer, $nativeBadInstance, $nativeServer | Get-DbaAgentAlert @splatNativeContinue)
        $nativeOutput.Count | Should -Be 2
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "streams successful input before EnableException stops at the failed instance" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            $nativeServer, $nativeBadInstance, $nativeServer |
                Get-DbaAgentAlert -Alert $nativeNames[0] -EnableException |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaAgentAlert SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $splatLoginConnection = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        $loginServer = Connect-DbaInstance @splatLoginConnection
        $loginAlertName = "native_alert_login_$([Guid]::NewGuid().ToString("N"))"
        $loginDatabaseName = "${loginAlertName}_db"
        $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database($loginServer, $loginDatabaseName)
        $loginDatabase.Create()
        $loginAlert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert($loginServer.JobServer, $loginAlertName)
        $loginAlert.DatabaseName = $loginDatabaseName
        $loginAlert.Severity = 19
        $loginAlert.IsEnabled = $false
        $loginAlert.Create()
    }

    AfterAll {
        if ($null -ne $loginServer -and $loginAlertName) {
            $loginServer.JobServer.Alerts.Refresh()
            $loginCleanupAlert = $loginServer.JobServer.Alerts[$loginAlertName]
            if ($null -ne $loginCleanupAlert) { $loginCleanupAlert.Drop() }
            $loginServer.Databases.Refresh()
            $loginCleanupDatabase = $loginServer.Databases[$loginDatabaseName]
            if ($null -ne $loginCleanupDatabase) { $loginCleanupDatabase.Drop() }
        }
    }

    It "retrieves the alert with the SQL credential" {
        $splatLoginAlert = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            Alert           = $loginAlertName
            EnableException = $true
        }
        $loginOutput = @(Get-DbaAgentAlert @splatLoginAlert)
        $loginOutput.Count | Should -Be 1
        $loginOutput[0].Name | Should -BeExactly $loginAlertName
        $loginOutput[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Alert
    }

    It "warns without returning alerts when the SQL credential is omitted" {
        $loginWarnings = @()
        $splatLoginWarning = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Alert           = $loginAlertName
            EnableException = $false
            WarningVariable = "loginWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $loginDenied = @(Get-DbaAgentAlert @splatLoginWarning)
        $loginDenied.Count | Should -Be 0
        ($loginWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "throws without the SQL credential when EnableException is set" {
        $splatLoginException = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Alert           = $loginAlertName
            EnableException = $true
        }
        { Get-DbaAgentAlert @splatLoginException } | Should -Throw
    }
}
