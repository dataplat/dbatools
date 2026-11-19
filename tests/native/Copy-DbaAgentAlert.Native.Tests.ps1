#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaAgentAlert",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; destination arrays are covered below.
# NativeChecklist: platform cross-platform -- SMO Agent objects and managed SQL connections; no Windows-only API.
# NativeChecklist: sql-login N/A -- The pinned command has SourceSqlCredential and DestinationSqlCredential, but no SqlCredential parameter; the ordinary matrix preserves those source/destination forms.
Describe "Native Copy-DbaAgentAlert" -Tag IntegrationTests {
    BeforeAll {
        $nativeAlertSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $nativeAlertDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $nativeAlertSuffix = [guid]::NewGuid().ToString("N")
        $nativeAlertQuotedName = "native alert O'Reilly $nativeAlertSuffix"
        $nativeAlertJobName = "native job $nativeAlertSuffix"
        $nativeAlertAssociatedName = "native response $nativeAlertSuffix"
        $nativeAlertConflictSourceName = "native conflict source $nativeAlertSuffix"
        $nativeAlertConflictDestinationName = "native conflict destination $nativeAlertSuffix"
        $nativeAlertConflictKeyword = "conflict $nativeAlertSuffix"
        $nativeAlertMessage = "sp_add_alert 00000000-0000-0000-0000-000000000000"
        foreach ($nativeAlertServer in @($nativeAlertSource, $nativeAlertDestination)) {
            $nativeAlertJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeAlertServer.JobServer, $nativeAlertJobName
            $nativeAlertJob.IsEnabled = $false
            $nativeAlertJob.Create()
            $nativeAlertJob.ApplyToTargetServer([string]::Empty)
            $nativeAlertQuoted = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert -ArgumentList $nativeAlertServer.JobServer, $nativeAlertQuotedName
            $nativeAlertQuoted.Severity = 12
            $nativeAlertQuoted.EventDescriptionKeyword = $nativeAlertSuffix
            $nativeAlertQuoted.IsEnabled = $false
            $nativeAlertQuoted.NotificationMessage = if ($nativeAlertServer -eq $nativeAlertSource) { "source value" } else { "destination value" }
            $nativeAlertQuoted.Create()
        }
        $nativeAlertAssociated = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert -ArgumentList $nativeAlertSource.JobServer, $nativeAlertAssociatedName
        $nativeAlertAssociated.Severity = 11
        $nativeAlertAssociated.EventDescriptionKeyword = $nativeAlertSuffix
        $nativeAlertAssociated.IsEnabled = $false
        $nativeAlertAssociated.NotificationMessage = $nativeAlertMessage
        $nativeAlertAssociated.JobID = $nativeAlertSource.JobServer.Jobs[$nativeAlertJobName].JobID
        $nativeAlertAssociated.Create()
        foreach ($nativeAlertServer in @($nativeAlertSource, $nativeAlertDestination)) {
            $nativeAlertConflictName = if ($nativeAlertServer -eq $nativeAlertSource) { $nativeAlertConflictSourceName } else { $nativeAlertConflictDestinationName }
            $nativeAlertConflict = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert -ArgumentList $nativeAlertServer.JobServer, $nativeAlertConflictName
            $nativeAlertConflict.Severity = 13
            $nativeAlertConflict.EventDescriptionKeyword = $nativeAlertConflictKeyword
            $nativeAlertConflict.IsEnabled = $false
            $nativeAlertConflict.Create()
        }
    }

    AfterAll {
        foreach ($nativeAlertServer in @($nativeAlertSource, $nativeAlertDestination)) {
            $nativeAlertServer.JobServer.Alerts.Refresh()
            foreach ($nativeAlertName in @($nativeAlertQuotedName, $nativeAlertAssociatedName, $nativeAlertConflictSourceName, $nativeAlertConflictDestinationName)) {
                if ($nativeAlertServer.JobServer.Alerts.Contains($nativeAlertName)) {
                    $nativeAlertServer.JobServer.Alerts[$nativeAlertName].Drop()
                }
            }
            $nativeAlertServer.JobServer.Jobs.Refresh()
            if ($nativeAlertServer.JobServer.Jobs.Contains($nativeAlertJobName)) {
                $nativeAlertServer.JobServer.Jobs[$nativeAlertJobName].Drop()
            }
        }
    }

    It "replaces a quoted alert name without treating the name as SQL" {
        $nativeAlertResult = @(Copy-DbaAgentAlert -Source $nativeAlertSource -Destination $nativeAlertDestination -Alert $nativeAlertQuotedName -Force -Confirm:$false -EnableException)
        $nativeAlertResult.Status | Should -Be @("Successful", "Successful")
        $nativeAlertDestination.JobServer.Alerts.Refresh()
        $nativeAlertDestination.JobServer.Alerts[$nativeAlertQuotedName].NotificationMessage | Should -Be "source value"
    }

    It "associates the destination job without rewriting notification text" {
        $nativeAlertResult = @(Copy-DbaAgentAlert -Source $nativeAlertSource -Destination $nativeAlertDestination -Alert $nativeAlertAssociatedName -Confirm:$false -EnableException)
        $nativeAlertResult.Status | Should -Be @("Successful", "Successful", "Successful")
        $nativeAlertDestination.JobServer.Alerts.Refresh()
        $nativeAlertCopied = $nativeAlertDestination.JobServer.Alerts[$nativeAlertAssociatedName]
        $nativeAlertCopied.JobID | Should -Be $nativeAlertDestination.JobServer.Jobs[$nativeAlertJobName].JobID
        $nativeAlertCopied.NotificationMessage | Should -Be $nativeAlertMessage
    }

    It "reports the actual keyword in conflict notes" {
        $nativeAlertResult = @(Copy-DbaAgentAlert -Source $nativeAlertSource -Destination $nativeAlertDestination -Alert $nativeAlertConflictSourceName -Confirm:$false -EnableException)
        $nativeAlertResult.Count | Should -Be 1
        $nativeAlertResult[0].Status | Should -Be "Skipped"
        $nativeAlertResult[0].Notes | Should -Be "Alert [$nativeAlertConflictSourceName] has already been defined to use severity 13 with error text '$nativeAlertConflictKeyword'. Skipping."
        $nativeAlertDestination.JobServer.Alerts.Refresh()
        $nativeAlertDestination.JobServer.Alerts.Contains($nativeAlertConflictSourceName) | Should -BeFalse
    }

    It "refuses an Azure destination and continues to the next destination" -Tag NativeChecklist:azure-sqldb {
        $nativeAlertAzure = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $nativeAlertAzure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $_.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException] -or ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258)) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $nativeAlertAzure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $nativeAlertAzureWarning = @()
            $nativeAlertAzureErrors = @()
            $nativeAlertResult = @(Copy-DbaAgentAlert -Source $nativeAlertSource -Destination @($nativeAlertAzure, $nativeAlertDestination) -Alert $nativeAlertQuotedName -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable nativeAlertAzureWarning -ErrorVariable nativeAlertAzureErrors)
            $nativeAlertResult.Count | Should -Be 1
            $nativeAlertResult[0].Status | Should -Be "Skipped"
            $nativeAlertResult[0].Notes | Should -Be "Already exists on destination"
            $nativeAlertAzureWarning.Count | Should -Be 1
            $nativeAlertAzureWarning[0].Message | Should -Match ([regex]::Escape("[Copy-DbaAgentAlert] Failure | Azure SQL Database not supported") + '$')
            $nativeAlertAzureErrors.Count | Should -Be 1
            $nativeAlertAzureRecord = $nativeAlertAzureErrors[0]
            $nativeAlertAzureRecord.FullyQualifiedErrorId | Should -BeExactly "dbatools_Copy-DbaAgentAlert"
            $nativeAlertAzureRecord.CategoryInfo.Category | Should -Be "ConnectionError"
            $nativeAlertAzureRecord.CategoryInfo.Reason | Should -BeExactly "Exception"
            $nativeAlertAzureRecord.TargetObject | Should -BeOfType System.String
            ("[" + $nativeAlertAzureRecord.TargetObject + "]") | Should -BeExactly "$nativeAlertAzure"
            $nativeAlertAzureRecord.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $nativeAlertAzureRecord.Exception.Message | Should -BeExactly "Azure SQL Database not supported"
            $nativeAlertAzureRecord.Exception.InnerException.Message | Should -BeExactly "Azure SQL Database not supported"
        } finally {
            if ($nativeAlertAzure) { $nativeAlertAzure.ConnectionContext.Disconnect() }
        }
    }

    It "honors WhatIf with Force and defaults" -Tag "NativeChecklist:whatif-confirm" {
        $nativeAlertDestination.JobServer.Alerts.Refresh()
        $nativeAlertBeforeId = $nativeAlertDestination.JobServer.Alerts[$nativeAlertQuotedName].ID
        $nativeAlertResult = @(Copy-DbaAgentAlert -Source $nativeAlertSource -Destination $nativeAlertDestination -Alert $nativeAlertQuotedName -Force -IncludeDefaults -WhatIf -Confirm:$false)
        $nativeAlertResult.Count | Should -Be 0
        $nativeAlertDestination.JobServer.Alerts.Refresh()
        $nativeAlertDestination.JobServer.Alerts[$nativeAlertQuotedName].ID | Should -Be $nativeAlertBeforeId
    }

    It "continues destination arrays after a connection failure with explicit false switches" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false", "NativeChecklist:enable-exception" {
        $nativeAlertResult = @(Copy-DbaAgentAlert -Source $nativeAlertSource -Destination @($nativeAlertDestination, "tcp:127.0.0.1,1", $nativeAlertDestination) -Alert $nativeAlertQuotedName -Force:$false -IncludeDefaults:$false -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable nativeAlertWarning)
        $nativeAlertResult.Count | Should -Be 2
        $nativeAlertResult.Status | Should -Be @("Skipped", "Skipped")
        ($nativeAlertWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "throws on a destination connection failure when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        $nativeAlertError = $null
        try {
            $null = Copy-DbaAgentAlert -Source $nativeAlertSource -Destination "tcp:127.0.0.1,1" -Alert $nativeAlertQuotedName -EnableException -Confirm:$false
        } catch {
            $nativeAlertError = $_
        }
        $nativeAlertError | Should -Not -BeNullOrEmpty
        $nativeAlertError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }
}

Describe "Copy-DbaAgentAlert notification faults" -Tag IntegrationTests {
    BeforeAll {
        $faultSource = $null
        $faultTarget = $null
        $faultReader = $null
        $refreshReaders = New-Object "System.Collections.Generic.List[object]"
        $faultToken = "native_alert_fault_" + [guid]::NewGuid().ToString("N")
        $refreshToken = $faultToken + "_refresh"
        $faultNames = @(($faultToken + "_notified"), ($faultToken + "_plain"))
        $faultPassword = "Na!" + [guid]::NewGuid().ToString("N")
        $faultCredential = New-Object pscredential -ArgumentList $faultToken, (ConvertTo-SecureString $faultPassword -AsPlainText -Force)
        $faultSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $faultTarget = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        foreach ($faultAdmin in @($faultSource, $faultTarget)) {
            $faultOperator = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator -ArgumentList $faultAdmin.JobServer, $faultToken
            $faultOperator.Enabled = $false
            $faultOperator.EmailAddress = "native-fixture@example.invalid"
            $faultOperator.Create()
        }
        for ($faultIndex = 0; $faultIndex -lt $faultNames.Count; $faultIndex++) {
            $faultAlert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert -ArgumentList $faultSource.JobServer, $faultNames[$faultIndex]
            $faultAlert.Severity = 14 + $faultIndex
            $faultAlert.EventDescriptionKeyword = $faultToken
            $faultAlert.IsEnabled = $false
            $faultAlert.Create()
            if ($faultIndex -eq 0) { $faultAlert.AddNotification($faultToken, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]::NotifyEmail) }
        }
        $null = $faultSource.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$faultToken] WITH PASSWORD = N'$faultPassword', CHECK_POLICY = OFF; GRANT VIEW ANY DEFINITION TO [$faultToken];")
        $null = $faultSource.ConnectionContext.ExecuteNonQuery("USE msdb; CREATE USER [$faultToken] FOR LOGIN [$faultToken]; ALTER ROLE SQLAgentReaderRole ADD MEMBER [$faultToken]; ALTER ROLE db_datareader ADD MEMBER [$faultToken]; GRANT EXECUTE ON dbo.sp_help_alert TO [$faultToken]; DENY EXECUTE ON dbo.sp_help_notification TO [$faultToken];")
        $null = $faultTarget.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$refreshToken] WITH PASSWORD = N'$faultPassword', CHECK_POLICY = OFF;")
        $null = $faultTarget.ConnectionContext.ExecuteNonQuery("USE msdb; CREATE USER [$refreshToken] FOR LOGIN [$refreshToken]; DENY CONNECT TO [$refreshToken];")
        $splatFaultReader = @{
            SqlInstance = $TestConfig.InstanceCopy1
            SqlCredential = $faultCredential
            NonPooledConnection = $true
            EnableException = $true
        }
        $faultReader = Connect-DbaInstance @splatFaultReader
        $faultReader.JobServer.Alerts.Refresh()
        $faultExpected = @{}
        foreach ($faultName in $faultNames) {
            $faultReadAlert = $faultReader.JobServer.Alerts[$faultName]
            if (-not $faultReadAlert) { throw "The permission fixture cannot enumerate its source alert." }
            try { $null = $faultReadAlert.EnumNotifications() }
            catch { $faultExpected[$faultName] = $PSItem }
            if (-not $faultExpected.ContainsKey($faultName)) { throw "The permission fixture did not deny notification enumeration." }
        }
        function Assert-NotificationFaultRecord($actual, $expected, [string]$errorId = "FailedOperationException") {
            $actual.FullyQualifiedErrorId | Should -BeExactly "$errorId,Dataplat.Dbatools.Commands.CopyDbaAgentAlertCommand"
            $actual.CategoryInfo.Category | Should -Be $expected.CategoryInfo.Category
            $actual.CategoryInfo.Reason | Should -BeExactly $expected.CategoryInfo.Reason
            $actual.CategoryInfo.TargetName | Should -BeExactly $expected.CategoryInfo.TargetName
            $actual.CategoryInfo.TargetType | Should -BeExactly $expected.CategoryInfo.TargetType
            $actual.TargetObject | Should -Be $expected.TargetObject
            $actualException = $actual.Exception
            $expectedException = $expected.Exception
            while ($null -ne $expectedException) {
                $actualException | Should -Not -BeNullOrEmpty
                $actualException.GetType().FullName | Should -BeExactly $expectedException.GetType().FullName
                $actualException.Message | Should -BeExactly $expectedException.Message
                $actualException.HResult | Should -Be $expectedException.HResult
                $actualException = $actualException.InnerException
                $expectedException = $expectedException.InnerException
            }
            $actualException | Should -BeNullOrEmpty
        }
        function Invoke-NotificationOutsideTry([hashtable]$arguments, [bool]$recover = $false) {
            # Pester encloses every It in a try; use the same isolated runspace pattern as the engine check.
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Copy-DbaAgentAlert -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Copy-DbaAgentAlert", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $outsideScript = {
                    param($copyArguments, $recoverRead, $adminSource, $permissionUser)
                    $outsideErrors = @()
                    Copy-DbaAgentAlert @copyArguments -ErrorVariable outsideErrors | ForEach-Object {
                        if ($recoverRead -and $PSItem.Type -eq "Agent Alert" -and $PSItem.Status -eq "Successful") {
                            $null = $adminSource.ConnectionContext.ExecuteNonQuery("USE msdb; GRANT EXECUTE ON dbo.sp_help_notification TO [$permissionUser];")
                        }
                        $PSItem
                    }
                }
                $null = $outsideShell.AddScript($outsideScript.ToString()).AddArgument($arguments).AddArgument($recover).AddArgument($faultSource).AddArgument($faultToken)
                $outsideStop = $null
                try { $null = $outsideShell.Invoke($null, $outsideOutput) }
                catch { $outsideStop = $PSItem }
                [pscustomobject]@{
                    Output = @($outsideOutput)
                    Errors = @($outsideRunspace.SessionStateProxy.GetVariable("outsideErrors"))
                    ReportedErrors = @($outsideShell.Streams.Error)
                    Stop = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
                $outsideOutput.Dispose()
            }
        }
        function Assert-NotificationReadContinuation([int]$site) {
            $splatFaultCopy = @{
                Source = $faultReader
                Destination = @($faultTarget, $faultTarget)
                Alert = $faultNames[$site]
                Confirm = $false
                EnableException = $false
                ErrorAction = "SilentlyContinue"
            }
            $continuation = Invoke-NotificationOutsideTry $splatFaultCopy
            $continuationOutput = $continuation.Output
            $continuationErrors = $continuation.Errors
            $continuationOutput.Count | Should -Be 3
            $continuationOutput.Type | Should -Be @("Agent Alert", "Agent Alert Notification", "Agent Alert")
            $continuationOutput.Status | Should -Be @("Successful", "Failed", "Skipped")
            $continuationOutput[1].Notes | Should -BeNullOrEmpty
            $continuationOutput[1].SourceServer | Should -BeExactly $faultSource.Name
            $continuationOutput[1].DestinationServer | Should -BeExactly $faultTarget.Name
            $continuationOutput[1].Name | Should -BeExactly $faultNames[$site]
            $continuationOutput[1].DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
            $continuationOutput[1].PSObject.TypeNames | Should -Contain "dbatools.MigrationObject"
            ($continuationOutput[1].PSObject.Properties.Name -join ",") | Should -BeExactly "SourceServer,DestinationServer,Name,Type,Notes,Status,DateTime"
            ($continuationOutput[1].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "DateTime,SourceServer,DestinationServer,Name,Type,Status,Notes"
            $continuationOutput[2].Notes | Should -BeExactly "Already exists on destination"
            $continuationErrors.Count | Should -Be $(if ($site -eq 0) { 3 } else { 1 })
            foreach ($continuationError in $continuationErrors) { Assert-NotificationFaultRecord $continuationError $faultExpected[$faultNames[$site]] }
            $faultTarget.JobServer.Alerts.Refresh()
            $faultCopied = $faultTarget.JobServer.Alerts[$faultNames[$site]]
            $faultCopied | Should -Not -BeNullOrEmpty
            $faultCopied.EnumNotifications().Rows.Count | Should -Be 0
        }
    }

    AfterEach {
        $faultCleanupErrors = New-Object "System.Collections.Generic.List[string]"
        try { $null = $faultSource.ConnectionContext.ExecuteNonQuery("USE msdb; DENY EXECUTE ON dbo.sp_help_notification TO [$faultToken];") }
        catch { $faultCleanupErrors.Add($PSItem.Exception.ToString()) }
        foreach ($faultName in $faultNames) {
            try {
                $faultTarget.JobServer.Alerts.Refresh()
                if ($faultTarget.JobServer.Alerts.Contains($faultName)) { $faultTarget.JobServer.Alerts[$faultName].Drop() }
            } catch { $faultCleanupErrors.Add($PSItem.Exception.ToString()) }
        }
        if ($faultCleanupErrors.Count) { throw ($faultCleanupErrors -join [Environment]::NewLine) }
    }

    AfterAll {
        $faultFinalErrors = New-Object "System.Collections.Generic.List[string]"
        if ($faultReader) {
            try { $faultReader.ConnectionContext.Disconnect() }
            catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
        }
        foreach ($refreshReader in $refreshReaders) {
            try { $refreshReader.ConnectionContext.Disconnect() }
            catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
        }
        foreach ($faultAdmin in @($faultSource, $faultTarget)) {
            if (-not $faultAdmin) { continue }
            foreach ($faultName in $faultNames) {
                try {
                    $faultAdmin.JobServer.Alerts.Refresh()
                    if ($faultAdmin.JobServer.Alerts.Contains($faultName)) { $faultAdmin.JobServer.Alerts[$faultName].Drop() }
                } catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
            }
            try {
                $faultAdmin.JobServer.Operators.Refresh()
                if ($faultAdmin.JobServer.Operators.Contains($faultToken)) { $faultAdmin.JobServer.Operators[$faultToken].Drop() }
            } catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
        }
        if ($faultSource) {
            try { $null = $faultSource.ConnectionContext.ExecuteNonQuery("USE msdb; IF USER_ID(N'$faultToken') IS NOT NULL DROP USER [$faultToken];") }
            catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
            try { $null = $faultSource.ConnectionContext.ExecuteNonQuery("USE master; IF SUSER_ID(N'$faultToken') IS NOT NULL DROP LOGIN [$faultToken];") }
            catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
        }
        if ($faultTarget) {
            try { $null = $faultTarget.ConnectionContext.ExecuteNonQuery("USE msdb; IF USER_ID(N'$refreshToken') IS NOT NULL DROP USER [$refreshToken];") }
            catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
            try { $null = $faultTarget.ConnectionContext.ExecuteNonQuery("USE master; IF SUSER_ID(N'$refreshToken') IS NOT NULL DROP LOGIN [$refreshToken];") }
            catch { $faultFinalErrors.Add($PSItem.Exception.ToString()) }
        }
        if ($faultFinalErrors.Count) { throw ($faultFinalErrors -join [Environment]::NewLine) }
    }

    # Pin measurement: evidence/notification-stage-r2-20261104.txt; scope cfaa209f3d31cd35.
    # A failed notification read cannot truthfully report a Successful notification copy.
    It "reports Failed with Notes null when the notification read fails and Successful when it recovers" {
        $faultReader.JobServer.Alerts[$faultNames[0]].HasNotification | Should -Not -Be 0
        Assert-NotificationReadContinuation 0
        $faultReader.JobServer.Alerts[$faultNames[1]].HasNotification | Should -Be 0
        Assert-NotificationReadContinuation 1
        $faultTarget.JobServer.Alerts[$faultNames[0]].Drop()
        $splatRecoveryCopy = @{
            Source = $faultReader
            Destination = @($faultTarget, $faultTarget)
            Alert = $faultNames[0]
            Confirm = $false
            EnableException = $false
            ErrorAction = "SilentlyContinue"
        }
        # The first success is streamed before the second EnumNotifications call.
        $recovery = Invoke-NotificationOutsideTry $splatRecoveryCopy $true
        $recovery.Stop | Should -BeNullOrEmpty
        $recoveryOutput = $recovery.Output
        $recoveryErrors = $recovery.Errors
        $recoveryOutput.Status | Should -Be @("Successful", "Successful", "Skipped")
        $recoveryErrors.Count | Should -Be 1
        Assert-NotificationFaultRecord $recoveryErrors[0] $faultExpected[$faultNames[0]]
        $faultTarget.JobServer.Alerts.Refresh()
        $recoveredNotifications = $faultTarget.JobServer.Alerts[$faultNames[0]].EnumNotifications()
        $recoveredNotifications.Rows.Count | Should -Be 1
        $recoveredNotifications.Rows[0].OperatorName | Should -BeExactly $faultToken
    }

    It "stops at each notification fault under caller try, EnableException and ErrorAction Stop" {
        foreach ($stopSite in @(0, 1)) {
            foreach ($stopMode in @("CallerTry", "EnableException", "ErrorAction")) {
                $splatFaultStop = @{
                    Source = $faultReader
                    Destination = @($faultTarget, $faultTarget)
                    Alert = $faultNames[$stopSite]
                    Confirm = $false
                    EnableException = ($stopMode -eq "EnableException")
                    ErrorAction = $(if ($stopMode -eq "ErrorAction") { "Stop" } else { "Continue" })
                }
                $faultStream = New-Object "System.Collections.Generic.List[object]"
                $faultCaught = $null
                $faultStopErrors = @()
                if ($stopMode -eq "CallerTry") {
                    try {
                        Copy-DbaAgentAlert @splatFaultStop -ErrorVariable faultStopErrors | ForEach-Object { $faultStream.Add($PSItem) }
                    } catch { $faultCaught = $PSItem }
                } else {
                    $faultStopped = Invoke-NotificationOutsideTry $splatFaultStop
                    foreach ($faultOutput in $faultStopped.Output) { $faultStream.Add($faultOutput) }
                    $faultStopErrors = $faultStopped.Errors
                    if ($stopMode -eq "ErrorAction") {
                        $faultStopped.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                        $faultCaught = $faultStopped.Stop.Exception.InnerException.ErrorRecord
                    } else {
                        $faultStopped.ReportedErrors.Count | Should -Be 1
                        $faultCaught = $faultStopped.ReportedErrors[0]
                    }
                }
                $faultCaught | Should -Not -BeNullOrEmpty
                Assert-NotificationFaultRecord $faultCaught $faultExpected[$faultNames[$stopSite]]
                $faultStream.Count | Should -Be $stopSite
                if ($stopSite -eq 1) { $faultStream[0].Status | Should -BeExactly "Successful" }
                if ($stopMode -eq "EnableException") {
                    $faultStopErrors.Count | Should -Be 1
                    $faultStopErrors[0] | Should -BeOfType System.Management.Automation.CmdletInvocationException
                    Assert-NotificationFaultRecord $faultStopErrors[0].ErrorRecord $faultExpected[$faultNames[$stopSite]]
                }
                $faultTarget.JobServer.Alerts.Refresh()
                $faultTarget.JobServer.Alerts.Contains($faultNames[$stopSite]) | Should -Be ($stopSite -eq 1)
                if ($stopSite -eq 1) { $faultTarget.JobServer.Alerts[$faultNames[$stopSite]].Drop() }
            }
        }
    }

    It "continues after both refresh faults and stops under caller try or explicit stop options" {
        # Both refresh sites reached on the pin in evidence/refresh-deny-20261107.txt, both editions.
        foreach ($refreshMode in @("Plain", "CallerTry", "EnableException", "ErrorAction")) {
            $splatRefreshConnection = @{
                SqlInstance = $TestConfig.InstanceCopy2
                NonPooledConnection = $true
                ClientName = $refreshToken + $refreshMode
                EnableException = $true
            }
            $refreshReader = Connect-DbaInstance @splatRefreshConnection
            $refreshReaders.Add($refreshReader)
            $null = $refreshReader.JobServer.Alerts.Count
            $null = $refreshReader.JobServer.Jobs.Count
            $null = $refreshReader.JobServer.Operators.Count
            $null = $refreshReader.ConnectionContext.ExecuteNonQuery("EXECUTE AS LOGIN = '$refreshToken';")
            $deniedMsdb = $null
            try { $null = $refreshReader.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM msdb.dbo.sysalerts;") }
            catch { $deniedMsdb = $PSItem }
            $deniedMsdb | Should -Not -BeNullOrEmpty

            $splatRefreshCopy = @{
                Source = $faultSource
                Destination = @($refreshReader, $refreshReader)
                Alert = $faultNames[1]
                Confirm = $false
                EnableException = ($refreshMode -eq "EnableException")
                ErrorAction = $(if ($refreshMode -eq "ErrorAction") { "Stop" } else { "Continue" })
            }
            $refreshOutput = New-Object "System.Collections.Generic.List[object]"
            $refreshErrors = @()
            $refreshStopErrors = @()
            if ($refreshMode -eq "CallerTry") {
                try {
                    Copy-DbaAgentAlert @splatRefreshCopy -ErrorVariable refreshStopErrors | ForEach-Object { $refreshOutput.Add($PSItem) }
                } catch { $refreshErrors = @($PSItem) }
            } else {
                $refreshResult = Invoke-NotificationOutsideTry $splatRefreshCopy
                foreach ($refreshItem in $refreshResult.Output) { $refreshOutput.Add($refreshItem) }
                if ($refreshMode -eq "ErrorAction") {
                    $refreshResult.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    $refreshErrors = @($refreshResult.Stop.Exception.InnerException.ErrorRecord)
                } else {
                    $refreshErrors = $refreshResult.ReportedErrors
                }
                $refreshStopErrors = $refreshResult.Errors
            }

            # Compare with the underlying method records after the call, preserving the preloaded fixture beforehand.
            $refreshExpected = @()
            try { $refreshReader.JobServer.Alerts.Refresh() }
            catch { $refreshExpected += $PSItem }
            try { $refreshReader.JobServer.Jobs.Refresh() }
            catch { $refreshExpected += $PSItem }
            $refreshExpected.Count | Should -Be 2
            if ($refreshMode -eq "Plain") {
                $refreshResult.Stop | Should -BeNullOrEmpty
                $refreshErrors.Count | Should -Be 4
                $refreshOutput.Count | Should -Be 4
                @($refreshOutput | Where-Object Type -eq "Agent Alert").Count | Should -Be 2
                @($refreshOutput | Where-Object { $PSItem.Type -eq "Agent Alert" -and $PSItem.Status -eq "Failed" }).Count | Should -Be 2
                foreach ($failedAlert in @($refreshOutput | Where-Object Type -eq "Agent Alert")) {
                    $failedAlert.Notes | Should -BeNullOrEmpty
                }
                # The source notification read succeeds with zero rows on this fixture.
                @($refreshOutput | Where-Object { $PSItem.Type -eq "Agent Alert Notification" -and $PSItem.Status -eq "Successful" }).Count | Should -Be 2
                for ($refreshIndex = 0; $refreshIndex -lt $refreshErrors.Count; $refreshIndex++) {
                    Assert-NotificationFaultRecord $refreshErrors[$refreshIndex] $refreshExpected[$refreshIndex % 2] "ExecutionFailureException"
                }
            } else {
                $refreshOutput.Count | Should -Be 1
                $refreshOutput[0].Type | Should -BeExactly "Agent Alert"
                $refreshOutput[0].Status | Should -BeExactly "Failed"
                $refreshOutput[0].Notes | Should -BeNullOrEmpty
                $refreshErrors.Count | Should -Be 1
                Assert-NotificationFaultRecord $refreshErrors[0] $refreshExpected[0] "ExecutionFailureException"
                if ($refreshMode -eq "EnableException") {
                    $refreshStopErrors.Count | Should -Be 1
                    $refreshStopErrors[0] | Should -BeOfType System.Management.Automation.CmdletInvocationException
                    Assert-NotificationFaultRecord $refreshStopErrors[0].ErrorRecord $refreshExpected[0] "ExecutionFailureException"
                }
            }
            $faultTarget.JobServer.Alerts.Refresh()
            $faultTarget.JobServer.Alerts.Contains($faultNames[1]) | Should -BeFalse
            $refreshReader.ConnectionContext.Disconnect()
        }
    }
}
