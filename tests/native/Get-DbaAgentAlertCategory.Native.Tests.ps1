#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentAlertCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.
# NativeChecklist: platform cross-platform -- SMO Agent categories and managed PowerShell APIs; no Windows-only API.

Describe "Get-DbaAgentAlertCategory native behavior" -Tag IntegrationTests {
    BeforeAll {
        function Set-NativeAlertCategoryFixtureErrorDetails($operation, $record) {
            $details = New-Object "System.Collections.Generic.List[string]"
            $details.Add("Fixture operation: $operation")
            $details.Add($record.Exception.ToString())
            $cause = $record.Exception
            while ($null -ne $cause) {
                if ($cause.PSObject.Properties["Number"]) {
                    $details.Add("$($cause.GetType().FullName) Number=$($cause.Number)")
                }
                if ($cause.GetType().FullName -in @("System.Data.SqlClient.SqlException", "Microsoft.Data.SqlClient.SqlException")) {
                    foreach ($sqlError in $cause.Errors) {
                        $details.Add("SqlError Number=$($sqlError.Number) State=$($sqlError.State) Class=$($sqlError.Class) Line=$($sqlError.LineNumber) Message=$($sqlError.Message)")
                    }
                }
                $cause = $cause.InnerException
            }
            # The runner records ErrorRecord.ToString(), so preserve these details in that recorded message.
            $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails -ArgumentList ($details -join [Environment]::NewLine)
        }
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativePrefix = "native_alertcategory_$([Guid]::NewGuid().ToString("N"))"
        $nativeNames = @("${nativePrefix}_a", "${nativePrefix}_b")
        $nativeDatabaseName = "${nativePrefix}_db"
        $nativeAlertName = "${nativePrefix}_alert"
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        foreach ($nativeName in $nativeNames) {
            $nativeCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.AlertCategory($nativeServer.JobServer, $nativeName)
            $nativeCategory.Create()
        }
        $nativeDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database($nativeServer, $nativeDatabaseName)
        $nativeDatabase.Create()
        $nativeAlert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert($nativeServer.JobServer, $nativeAlertName)
        $nativeAlert.CategoryName = $nativeNames[0]
        # A private database avoids colliding with existing instance-wide severity alerts.
        $nativeAlert.DatabaseName = $nativeDatabaseName
        $nativeAlert.Severity = 17
        $nativeAlert.IsEnabled = $false
        $nativeAlert.Create()
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeCleanupFailures = New-Object "System.Collections.Generic.List[string]"
        try {
            $nativeCleanup = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $nativeCleanup.JobServer.Alerts.Refresh()
            $nativeCleanupAlert = $nativeCleanup.JobServer.Alerts[$nativeAlertName]
            if ($null -ne $nativeCleanupAlert) {
                try { $nativeCleanupAlert.Drop() }
                catch { Set-NativeAlertCategoryFixtureErrorDetails "Drop alert $nativeAlertName" $_; $nativeCleanupFailures.Add($_.ToString()) }
            }
            $nativeCleanup.Databases.Refresh()
            $nativeCleanupDatabase = $nativeCleanup.Databases[$nativeDatabaseName]
            if ($null -ne $nativeCleanupDatabase) {
                try { $nativeCleanup.KillDatabase($nativeDatabaseName) }
                catch { Set-NativeAlertCategoryFixtureErrorDetails "Drop database $nativeDatabaseName" $_; $nativeCleanupFailures.Add($_.ToString()) }
            }
            $nativeCleanup.JobServer.AlertCategories.Refresh()
            foreach ($nativeCleanupCategoryName in $nativeNames) {
                $nativeCleanupCategory = $nativeCleanup.JobServer.AlertCategories[$nativeCleanupCategoryName]
                if ($null -ne $nativeCleanupCategory) {
                    try { $nativeCleanupCategory.Drop() }
                    catch { Set-NativeAlertCategoryFixtureErrorDetails "Drop category $nativeCleanupCategoryName" $_; $nativeCleanupFailures.Add($_.ToString()) }
                }
            }
            if ($nativeCleanupFailures.Count -gt 0) { throw ($nativeCleanupFailures -join [Environment]::NewLine) }
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    It "preserves exact filters, typed categories, usage counts and default display" {
        $splatNativeFilters = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = $nativeNames
            EnableException = $true
        }
        $nativeOutput = @(Get-DbaAgentAlertCategory @splatNativeFilters)
        $nativeOutput.Count | Should -Be 2
        $nativePopulated = $nativeOutput | Where-Object Name -EQ $nativeNames[0]
        $nativeEmpty = $nativeOutput | Where-Object Name -EQ $nativeNames[1]
        $nativePopulated | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.AlertCategory
        $nativePopulated.AlertCount | Should -Be 1
        $nativeEmpty.AlertCount | Should -Be 0
        $nativePopulated.ComputerName | Should -Not -BeNullOrEmpty
        $nativePopulated.InstanceName | Should -Not -BeNullOrEmpty
        $nativePopulated.SqlInstance | Should -Not -BeNullOrEmpty
        ($nativePopulated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,ID,AlertCount"
        $splatNativeFilters.Category = @($nativeNames[0].ToUpperInvariant(), $nativeNames[0])
        $nativeFiltered = @(Get-DbaAgentAlertCategory @splatNativeFilters)
        $nativeFiltered.Count | Should -Be 1
        $nativeFiltered[0].Name | Should -BeExactly $nativeNames[0]
        $nativeFiltered[0].AlertCount | Should -Be 1
        $splatNativeFilters.Category = "${nativePrefix}_*"
        @(Get-DbaAgentAlertCategory @splatNativeFilters).Count | Should -Be 0
        $splatNativeFilters.Category = @()
        @(Get-DbaAgentAlertCategory @splatNativeFilters).Count | Should -Be 0
        $splatNativeFilters.Category = $null
        @(Get-DbaAgentAlertCategory @splatNativeFilters).Count | Should -Be 0
    }

    It "stops cleanly when the consumer takes only the first category" {
        foreach ($enableErrors in @($false, $true)) {
            $earlyWarnings = @()
            $earlyErrors = @()
            $earlyOutput = @(Get-DbaAgentAlertCategory -SqlInstance @($nativeServer, $nativeBadInstance) -Category $nativeNames -EnableException:$enableErrors -WarningAction SilentlyContinue -WarningVariable earlyWarnings -ErrorVariable earlyErrors | Select-Object -First 1)
            $earlyOutput.Count | Should -Be 1
            $earlyOutput[0].Name | Should -BeExactly $nativeNames[0]
            $earlyWarnings.Count | Should -Be 0
            $earlyErrors.Count | Should -Be 0
        }
    }

    It "replaces stale decorations on the same cached SMO category" {
        $splatNativeCachedCategory = @{
            SqlInstance     = $nativeServer
            Category        = $nativeNames[0]
            EnableException = $true
        }
        $nativeCached = Get-DbaAgentAlertCategory @splatNativeCachedCategory
        $nativeExpectedInstance = @($nativeCached.ComputerName, $nativeCached.InstanceName, $nativeCached.SqlInstance)
        $nativeCached.ComputerName = "stale"
        $nativeCached.InstanceName = "stale"
        $nativeCached.SqlInstance = "stale"
        $nativeCached.AlertCount = -1
        $nativeCached | Add-Member -NotePropertyName NativeCacheMarker -NotePropertyValue "retained"

        $nativeRepeated = Get-DbaAgentAlertCategory @splatNativeCachedCategory
        [Object]::ReferenceEquals($nativeCached.PSObject.BaseObject, $nativeRepeated.PSObject.BaseObject) | Should -BeTrue
        $nativeRepeated | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.AlertCategory
        $nativeRepeated.AlertCount | Should -Be 1
        $nativeRepeated.NativeCacheMarker | Should -BeExactly "retained"
        $nativeRepeated.ComputerName | Should -BeExactly $nativeExpectedInstance[0]
        $nativeRepeated.InstanceName | Should -BeExactly $nativeExpectedInstance[1]
        $nativeRepeated.SqlInstance | Should -BeExactly $nativeExpectedInstance[2]
        ($nativeRepeated.PSObject.Properties.Name | Where-Object { $PSItem -in @("ComputerName", "InstanceName", "SqlInstance", "AlertCount") }) -join "," |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,AlertCount"
        ($nativeRepeated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,ID,AlertCount"
    }

    It "converts nested category arrays like the pinned cleanup call" {
        $splatNestedCategories = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = @($nativeNames, $nativeNames[0])
            EnableException = $true
        }
        $nativeNested = @(Get-DbaAgentAlertCategory @splatNestedCategories)
        # The inner array becomes one space-joined string; it is not flattened into more filters.
        $nativeNested.Count | Should -Be 1
        $nativeNested[0].Name | Should -BeExactly $nativeNames[0]
    }

    It "warns on a failed middle input and continues without duplicating output" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $splatNativeContinue = @{
            Category        = $nativeNames[0]
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeContinued = @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle | Get-DbaAgentAlertCategory @splatNativeContinue)
        $nativeContinued.Count | Should -Be 2
        $nativeContinued[0].Name | Should -BeExactly $nativeNames[0]
        $nativeContinued[1].Name | Should -BeExactly $nativeNames[0]
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }


    Context "category read denied after connection" {
        BeforeAll {
            $nativeDeniedName = "${nativePrefix}_denied"
            $nativeDeniedServer = $null
            $nativeUserCreated = $false
            try {
                $nativeServer.Databases["msdb"].ExecuteNonQuery("CREATE USER [$nativeDeniedName] WITHOUT LOGIN;")
                $nativeUserCreated = $true
                $nativeServer.Databases["msdb"].ExecuteNonQuery("DENY SELECT ON OBJECT::dbo.syscategories TO [$nativeDeniedName];")
            } catch {
                Set-NativeAlertCategoryFixtureErrorDetails "Create denied user $nativeDeniedName in msdb" $_
                throw
            }
            $splatDeniedConnection = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = "msdb"
                NonPooledConnection = $true
                ClientName          = $nativeDeniedName
                EnableException     = $true
            }
            $nativeDeniedServer = Connect-DbaInstance @splatDeniedConnection
            $nativeDeniedServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$nativeDeniedName';") | Out-Null

            function Invoke-CategoryOutsideTry([hashtable]$arguments, [bool]$mergeStreams = $false) {
                # Pester wraps It bodies in try. Isolate plain calls as StatementFault.Engine.Native.Tests.ps1 does.
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaAgentAlertCategory -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaAgentAlertCategory", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $outsideScript = {
                        param($servers, $categoryArguments, $merge)
                        $outsideErrors = @()
                        $outsideWarnings = @()
                        if ($merge) {
                            $servers | Get-DbaAgentAlertCategory @categoryArguments -ErrorVariable outsideErrors -WarningVariable outsideWarnings 2>&1 3>&1
                        } else {
                            $servers | Get-DbaAgentAlertCategory @categoryArguments -ErrorVariable outsideErrors -WarningVariable outsideWarnings
                        }
                    }
                    $null = $outsideShell.AddScript($outsideScript.ToString()).AddArgument(@($nativeServer, $nativeDeniedServer, $nativeServer)).AddArgument($arguments).AddArgument($mergeStreams)
                    $outsideStop = $null
                    try { $null = $outsideShell.Invoke($null, $outsideOutput) }
                    catch { $outsideStop = $PSItem }
                    [pscustomobject]@{
                        Output = @($outsideOutput)
                        Errors = @($outsideRunspace.SessionStateProxy.GetVariable("outsideErrors"))
                        Warnings = @($outsideRunspace.SessionStateProxy.GetVariable("outsideWarnings"))
                        ReportedErrors = @($outsideShell.Streams.Error)
                        Stop = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                    $outsideOutput.Dispose()
                }
            }
        }

        AfterAll {
            try {
                if ($null -ne $nativeDeniedServer) { $nativeDeniedServer.ConnectionContext.Disconnect() }
            } finally {
                if ($nativeUserCreated) {
                    try { $nativeServer.Databases["msdb"].ExecuteNonQuery("DROP USER [$nativeDeniedName];") }
                    catch { Set-NativeAlertCategoryFixtureErrorDetails "Drop denied user $nativeDeniedName from msdb" $_; throw }
                }
            }
        }

        It "handles a category read denied after a successful connection" {
            $nativeDeniedServer.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $nativeDeniedName
            # Prove the middle input connects; its failure must occur during the category read.
            $nativeVerifiedServer = Connect-DbaInstance -SqlInstance $nativeDeniedServer -EnableException
            [Object]::ReferenceEquals($nativeDeniedServer, $nativeVerifiedServer) | Should -BeTrue

            $nativeReadWarnings = @()
            $splatDeniedContinue = @{
                EnableException = $false
                WarningVariable = "nativeReadWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $nativeReadOutput = @($nativeServer, $nativeDeniedServer, $nativeServer | Get-DbaAgentAlertCategory @splatDeniedContinue)
            @($nativeReadOutput | Where-Object Name -EQ $nativeNames[0]).Count | Should -Be 2
            ($nativeReadWarnings -join " ") | Should -BeLike "*Something went wrong getting the alert category*"

            $nativeReadStreamed = New-Object "System.Collections.Generic.List[object]"
            $nativeReadCaught = $null
            try {
                $nativeServer, $nativeDeniedServer, $nativeServer |
                    Get-DbaAgentAlertCategory -EnableException |
                    ForEach-Object { $nativeReadStreamed.Add($PSItem) }
            } catch {
                $nativeReadCaught = $PSItem
            }
            @($nativeReadStreamed | Where-Object Name -EQ $nativeNames[0]).Count | Should -Be 1
            $nativeReadCaught | Should -Not -BeNullOrEmpty
            $nativeReadCaught.CategoryInfo.Category | Should -Be "NotSpecified"
            $nativeReadCaught.TargetObject.Name | Should -BeExactly $nativeReadStreamed[$nativeReadStreamed.Count - 1].Name

            # Whole-function probe: archive/conversions/fleet/Get-DbaAgentAlertCategory/evidence/errorforms-probe-20261030.txt, CASE A.
            # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentAlertCategory.ps1:88-91
            # enumerates outside the pin's try. With no enclosing try, good/denied/good
            # continues. StatementFault.Surface preserves that continuation and stops
            # when a caller try encloses the invocation, as the pin does.
            # Use the raw expression only for the exception/message/category/target;
            # the native engine owns invocation identity, not this reference expression.
            $pinnedFilterFault = $null
            try {
                $alertCategories = $nativeDeniedServer.JobServer.AlertCategories
                $alertCategories = $alertCategories | Where-Object { $_.Name -in $nativeNames }
            } catch { $pinnedFilterFault = $_ }
            $pinnedFilterFault | Should -Not -BeNullOrEmpty

            $filteredPlain = Invoke-CategoryOutsideTry @{ Category = $nativeNames[0]; EnableException = $false; ErrorAction = "Continue"; WarningAction = "Continue" } $true
            $filteredMerged = $filteredPlain.Output
            $filteredWarnings = $filteredPlain.Warnings
            $filteredMerged.Count | Should -Be 4
            $filteredWarnings.Count | Should -Be 1
            $filteredMerged[2] | Should -BeOfType System.Management.Automation.WarningRecord
            $filteredMerged[2].Message | Should -BeLike '*Something went wrong getting the alert category*'
            $filteredMerged[2].Message | Should -BeExactly $filteredWarnings[0].Message
            foreach ($index in @(0, 3)) {
                $filteredMerged[$index].Name | Should -BeExactly $nativeNames[0]
                [Object]::ReferenceEquals($filteredMerged[$index].Parent.Parent, $nativeServer) | Should -BeTrue
            }
            $filteredFault = $filteredMerged[1]
            $filteredFault | Should -BeOfType System.Management.Automation.ErrorRecord
            $filteredFault.Exception.GetType().FullName | Should -BeExactly $pinnedFilterFault.Exception.GetType().FullName
            $filteredFault.Exception.Message | Should -BeExactly $pinnedFilterFault.Exception.Message
            $filteredFault.FullyQualifiedErrorId | Should -BeExactly 'ExceptionInGetEnumerator,Dataplat.Dbatools.Commands.GetDbaAgentAlertCategoryCommand'
            $filteredFault.CategoryInfo.Category | Should -Be $pinnedFilterFault.CategoryInfo.Category
            $filteredFault.CategoryInfo.Reason | Should -BeExactly $pinnedFilterFault.CategoryInfo.Reason
            $filteredFault.CategoryInfo.TargetName | Should -BeExactly $pinnedFilterFault.CategoryInfo.TargetName
            $filteredFault.CategoryInfo.TargetType | Should -BeExactly $pinnedFilterFault.CategoryInfo.TargetType
            $filteredFault.TargetObject | Should -Be $pinnedFilterFault.TargetObject
            $filteredFault.InvocationInfo.MyCommand.Name | Should -BeExactly 'Get-DbaAgentAlertCategory'

            $hiddenPlain = Invoke-CategoryOutsideTry @{ Category = $nativeNames[0]; EnableException = $false; ErrorAction = "SilentlyContinue"; WarningAction = "SilentlyContinue" }
            $hiddenOutput = $hiddenPlain.Output
            $hiddenErrors = $hiddenPlain.Errors
            $hiddenWarnings = $hiddenPlain.Warnings
            $hiddenOutput.Count | Should -Be 2
            @($hiddenOutput | Where-Object Name -EQ $nativeNames[0]).Count | Should -Be 2
            $hiddenErrors.Count | Should -Be 2
            @($hiddenErrors | Where-Object FullyQualifiedErrorId -like 'ExceptionInGetEnumerator*').Count | Should -Be 1
            @($hiddenErrors | Where-Object FullyQualifiedErrorId -like 'dbatools_Get-DbaAgentAlertCategory*').Count | Should -Be 1
            $hiddenWarnings.Count | Should -Be 1
            $hiddenWarnings[0].Message | Should -BeLike '*Something went wrong getting the alert category*'

            foreach ($terminationMode in @('CallerTry', 'ErrorAction', 'EnableException')) {
                $splatFilteredFailure = @{
                    Category = $nativeNames[0]
                    EnableException = ($terminationMode -eq 'EnableException')
                    ErrorAction = $(if ($terminationMode -eq 'ErrorAction') { 'Stop' } else { 'Continue' })
                }
                $filteredStream = New-Object 'System.Collections.Generic.List[object]'
                $filteredCaught = $null
                $filteredStopErrors = @()
                if ($terminationMode -eq 'CallerTry') {
                    try {
                        $nativeServer, $nativeDeniedServer, $nativeServer |
                            Get-DbaAgentAlertCategory @splatFilteredFailure -ErrorVariable filteredStopErrors |
                            ForEach-Object { $filteredStream.Add($_) }
                    } catch { $filteredCaught = $_ }
                } else {
                    $filteredStopped = Invoke-CategoryOutsideTry $splatFilteredFailure
                    foreach ($filteredItem in $filteredStopped.Output) { $filteredStream.Add($filteredItem) }
                    $filteredStopErrors = $filteredStopped.Errors
                    if ($terminationMode -eq 'ErrorAction') {
                        $filteredStopped.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                        $filteredCaught = $filteredStopped.Stop.Exception.InnerException.ErrorRecord
                    } else {
                        $filteredStopped.ReportedErrors.Count | Should -Be 1
                        $filteredCaught = $filteredStopped.ReportedErrors[0]
                    }
                }
                $filteredStream.Count | Should -Be 1
                $filteredStream[0].Name | Should -BeExactly $nativeNames[0]
                $filteredCaught | Should -Not -BeNullOrEmpty
                $filteredCaught.FullyQualifiedErrorId | Should -BeExactly $filteredFault.FullyQualifiedErrorId
                $filteredCaught.Exception.GetType().FullName | Should -BeExactly $pinnedFilterFault.Exception.GetType().FullName
                $filteredCaught.Exception.Message | Should -BeExactly $filteredFault.Exception.Message
                $filteredCaught.CategoryInfo.Category | Should -Be $filteredFault.CategoryInfo.Category
                $filteredCaught.TargetObject | Should -Be $filteredFault.TargetObject
                if ($terminationMode -eq 'EnableException') {
                    $filteredStopErrors.Count | Should -Be 1
                    $filteredStopErrors[0] | Should -BeOfType System.Management.Automation.CmdletInvocationException
                    $filteredStopRecord = $filteredStopErrors[0].ErrorRecord
                    $filteredStopRecord.FullyQualifiedErrorId | Should -BeExactly $filteredCaught.FullyQualifiedErrorId
                    $filteredStopRecord.Exception.GetType().FullName | Should -BeExactly $pinnedFilterFault.Exception.GetType().FullName
                    $filteredStopRecord.Exception.Message | Should -BeExactly $pinnedFilterFault.Exception.Message
                    $filteredStopRecord.CategoryInfo.Category | Should -Be $pinnedFilterFault.CategoryInfo.Category
                    $filteredStopRecord.CategoryInfo.Reason | Should -BeExactly $pinnedFilterFault.CategoryInfo.Reason
                    $filteredStopRecord.CategoryInfo.TargetName | Should -BeExactly $pinnedFilterFault.CategoryInfo.TargetName
                    $filteredStopRecord.CategoryInfo.TargetType | Should -BeExactly $pinnedFilterFault.CategoryInfo.TargetType
                    $filteredStopRecord.TargetObject | Should -Be $pinnedFilterFault.TargetObject
                }
            }
        }
    }

    It "streams the first input before EnableException terminates the pipeline" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        $splatNativeThrow = @{
            Category        = $nativeNames[0]
            EnableException = $true
        }
        try {
            $TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle |
                Get-DbaAgentAlertCategory @splatNativeThrow |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeStreamed[0].Name | Should -BeExactly $nativeNames[0]
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaAgentAlertCategory SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $loginCategoryName = "native_alertcategory_login_$([guid]::NewGuid().ToString('N'))"
        $loginCategoryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $loginCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.AlertCategory($loginCategoryServer.JobServer, $loginCategoryName)
        $loginCategory.Create()
    }

    AfterAll {
        if ($null -ne $loginCategoryServer) {
            $loginCategoryServer.JobServer.AlertCategories.Refresh()
            $loginCategoryCleanup = $loginCategoryServer.JobServer.AlertCategories[$loginCategoryName]
            if ($null -ne $loginCategoryCleanup) { $loginCategoryCleanup.Drop() }
        }
    }

    It "returns the requested category with SQL credentials" {
        $splatLoginCategory = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            Category = $loginCategoryName
            EnableException = $true
        }
        $loginCategoryOutput = @(Get-DbaAgentAlertCategory @splatLoginCategory)
        $loginCategoryOutput.Count | Should -Be 1
        $loginCategoryOutput[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.AlertCategory
        $loginCategoryOutput[0].Name | Should -BeExactly $loginCategoryName
        $loginCategoryOutput[0].AlertCount | Should -Be 0
    }

    It "warns without output when SQL credentials are omitted" {
        $loginCategoryWarnings = @()
        $splatLoginCategoryDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            Category = $loginCategoryName
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "loginCategoryWarnings"
        }
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentAlertCategory.ps1:81-86
        # The base already ships this cmdlet; the pin predates src/ and cannot build a function baseline.
        # Excerpt route audit: archive/conversions/fleet-manager-20261024/sqllogin-cohort-20261028.txt.
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        @(Get-DbaAgentAlertCategory @splatLoginCategoryDenied).Count | Should -Be 0
        $loginCategoryWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentAlertCategory.ps1:81-86
        # The base already ships this cmdlet; the pin predates src/ and cannot build a function baseline.
        # Excerpt route audit: archive/conversions/fleet-manager-20261024/sqllogin-cohort-20261028.txt.
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        { Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSqlLogin -Category $loginCategoryName -EnableException } | Should -Throw
    }
}

Describe "Get-DbaAgentAlertCategory Azure SQL Database" -Tag IntegrationTests {
    It "refuses Azure SQL Database before enumerating Agent categories" -Tag NativeChecklist:azure-sqldb {
        $azure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $errorException = $_.Exception
                $resuming = $false
                while ($errorException) {
                    if ($errorException.Number -in 40613, -2 -or $errorException -is [System.TimeoutException] -or ($errorException -is [System.ComponentModel.Win32Exception] -and $errorException.NativeErrorCode -eq 258) -or $errorException.Message -match 'timed out|timeout|wait operation') { $resuming = $true }
                    $errorException = $errorException.InnerException
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            $azureErrors = @()
            @(Get-DbaAgentAlertCategory -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable azureErrors).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            $warnings[0].Message | Should -Match ([regex]::Escape('[Get-DbaAgentAlertCategory] Failure | Azure SQL Database not supported') + '$')
            $azureErrors.Count | Should -Be 1
            $azureRecord = $azureErrors[0]
            $azureRecord.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaAgentAlertCategory'
            $azureRecord.CategoryInfo.Category | Should -Be 'ConnectionError'
            $azureRecord.CategoryInfo.Reason | Should -BeExactly 'Exception'
            $azureRecord.TargetObject | Should -BeOfType System.String
            ('[' + $azureRecord.TargetObject + ']') | Should -BeExactly "$azure"
            $azureRecord.Exception.GetType().FullName | Should -BeExactly 'System.Exception'
            $azureRecord.Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
            $azureRecord.Exception.InnerException.Message | Should -BeExactly 'Azure SQL Database not supported'
            { Get-DbaAgentAlertCategory -SqlInstance $azure -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally { if ($azure) { $azure.ConnectionContext.Disconnect() } }
    }
}
