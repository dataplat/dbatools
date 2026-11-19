#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbState",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativeFixtureName = "native_display_caf" + [char]0x00e9 + "_" + [Guid]::NewGuid().ToString("N")
        $nativeFixture = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeServer, $nativeFixtureName
        $nativeFixture.Create()
        $nativeNumericValue = [DateTime]::UtcNow.Ticks
        $nativeNumericName = "0" + $nativeNumericValue.ToString()
        $nativeNumericFixture = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeServer, $nativeNumericName
        $nativeNumericFixture.Create()
        $nativeParameters = @{ Database = $nativeFixtureName }
        $nativeDisplay = "Access,ComputerName,DatabaseName,InstanceName,RW,SqlInstance,Status"
    }

    AfterAll {
        try {
            if ($null -ne $nativeNumericFixture) { $nativeNumericFixture.Drop() }
        } finally {
            if ($null -ne $nativeFixture) { $nativeFixture.Drop() }
        }
    }

    It "preserves the pinned display order and independently verified values" {
        $nativeRows = @(& $CommandName -SqlInstance $TestConfig.InstanceSingle @nativeParameters -EnableException)
        $nativeRows.Count | Should -Be 1
        ($nativeRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeDisplay
        $nativeRows[0].DatabaseName | Should -BeExactly $nativeFixtureName
        $nativeRows[0].Database | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
        $nativeRows[0].Status | Should -BeExactly "ONLINE"
        $nativeRows[0].RW | Should -BeExactly "READ_WRITE"
        $nativeRows[0].Access | Should -BeExactly "MULTI_USER"
        $nativeReadback = $nativeServer.ConnectionContext.ExecuteWithResults("SELECT name FROM sys.databases WHERE name = N'" + $nativeFixtureName + "'")
        $nativeReadback.Tables[0].Rows.Count | Should -Be 1
    }

    It "documents the displayed status and hidden SMO database object in full help" {
        $details = (Get-Help $CommandName -Full | Out-String -Width 4096) -replace '\s+', ' '
        $details | Should -Match ([regex]::Escape("Status: The database availability state (ONLINE, OFFLINE, EMERGENCY, or RESTORING)"))
        $details | Should -Match ([regex]::Escape("Database: The SMO Database object for this database (hidden from default display)"))
    }

    It "preserves typed inclusion, exclusion and false filter values from the pinned Where-Object" {
        # The pin uses Where-Object Name -In/-NotIn with object[] operands, not stringified values.
        ($nativeNumericName -in @($nativeNumericValue)) | Should -BeTrue
        $included = @(Get-DbaDbState -SqlInstance $nativeServer -Database @($nativeNumericValue) -EnableException)
        $included.Count | Should -Be 1
        $included[0].DatabaseName | Should -BeExactly $nativeNumericName
        @(Get-DbaDbState -SqlInstance $nativeServer -Database $nativeNumericName -ExcludeDatabase @($nativeNumericValue) -EnableException).Count | Should -Be 0
        $falseIncluded = @(Get-DbaDbState -SqlInstance $nativeServer -Database @($false) -EnableException)
        $falseIncluded.DatabaseName | Should -Contain $nativeNumericName
        @(Get-DbaDbState -SqlInstance $nativeServer -Database $nativeNumericName -ExcludeDatabase @($false) -EnableException).Count | Should -Be 1
    }

    It "matches canonically equivalent case-insensitive database name filters" {
        $equivalent = $nativeFixtureName.Normalize([Text.NormalizationForm]::FormD).ToUpperInvariant()
        ($nativeFixtureName -in @($equivalent)) | Should -BeTrue
        $included = @(Get-DbaDbState -SqlInstance $nativeServer -Database $equivalent -EnableException)
        $included.Count | Should -Be 1
        $included[0].DatabaseName | Should -BeExactly $nativeFixtureName
        @(Get-DbaDbState -SqlInstance $nativeServer -Database $nativeFixtureName -ExcludeDatabase $equivalent -EnableException).Count | Should -Be 0
    }

    It "continues after a failed middle pipeline instance" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $nativeRows = @(
            @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle) |
                & $CommandName @nativeParameters -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeWarnings
        )
        $nativeRows.Count | Should -Be 2
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
        foreach ($nativeRow in $nativeRows) {
            ($nativeRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeDisplay
        }
    }

    It "reports a denied state query and continues without stale database rows" {
        $userName = "native_state_denied_$([guid]::NewGuid().ToString('N'))"
        $denied = $null
        $created = $false
        try {
            $nativeServer.Databases['master'].ExecuteNonQuery("CREATE USER [$userName] WITHOUT LOGIN; DENY SELECT ON OBJECT::sys.databases TO [$userName];")
            $created = $true
            $denied = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database master -NonPooledConnection -ClientName $userName -EnableException
            # Load connection identity before impersonating the private database user.
            $null = $denied.VersionMajor, $denied.Name, $denied.ServiceName, $denied.ComputerName, $denied.NetName, $denied.DomainInstanceName
            $denied.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$userName';") | Out-Null
            $denied.ConnectionContext.ExecuteScalar('SELECT USER_NAME();') | Should -BeExactly $userName
            [Object]::ReferenceEquals($denied, (Connect-DbaInstance -SqlInstance $denied -EnableException)) | Should -BeTrue
            $reference = $null
            try { $null = $denied.ConnectionContext.ExecuteWithResults('SELECT name FROM sys.databases;') }
            catch { $reference = $_ }
            $reference | Should -Not -BeNullOrEmpty
            $sqlFailure = $reference.Exception
            while ($null -ne $sqlFailure.InnerException) { $sqlFailure = $sqlFailure.InnerException }
            $sqlFailure.Number | Should -Be 229
            # Whole pinned-function case D in errorforms-probe-20261030.txt proves
            # this Query wrapper on both editions. The SQL message comes from this live denial.
            $expectedMessage = 'Exception calling "Query" with "1" argument(s): "An exception occurred while executing a Transact-SQL statement or batch.' + $sqlFailure.Message + '"'
            # Pester and fixture cleanup both enclose this test in a try. Run the ordinary calls
            # in a new runspace so the command sees the same context as an uncaught pipeline.
            $shell = [System.Management.Automation.PowerShell]::Create()
            try {
                $manifest = Join-Path (Get-Module dbatools).ModuleBase 'dbatools.psd1'
                $measure = {
                    param($manifest, $good, $denied, $database)
                    Import-Module $manifest -ErrorAction Stop
                    $warnings = @()
                    $merged = @($good, $denied, $good |
                        Get-DbaDbState -Database $database -EnableException:$false -ErrorAction Continue -WarningAction SilentlyContinue -WarningVariable warnings 2>&1)
                    $hiddenErrors = @()
                    $hidden = @($denied, $good |
                        Get-DbaDbState -Database $database -EnableException:$false -ErrorAction SilentlyContinue -ErrorVariable hiddenErrors 2>&1)
                    [pscustomobject]@{ Merged = $merged; Warnings = $warnings; Hidden = $hidden; HiddenErrors = $hiddenErrors }
                }
                $null = $shell.AddScript($measure.ToString()).AddArgument($manifest).AddArgument($nativeServer).AddArgument($denied).AddArgument($nativeFixtureName)
                $measurement = @($shell.Invoke())
                $measurement.Count | Should -Be 1
                $merged = $measurement[0].Merged
                $warnings = $measurement[0].Warnings
                $hidden = $measurement[0].Hidden
                $hiddenErrors = $measurement[0].HiddenErrors
            } finally {
                $shell.Dispose()
            }
            $merged.Count | Should -Be 3
            $warnings.Count | Should -Be 0
            foreach ($index in 0, 2) {
                $merged[$index].DatabaseName | Should -BeExactly $nativeFixtureName
                $merged[$index].Status | Should -BeExactly 'ONLINE'
                $merged[$index].RW | Should -BeExactly 'READ_WRITE'
                $merged[$index].Access | Should -BeExactly 'MULTI_USER'
                $merged[$index].Database | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
                [Object]::ReferenceEquals($merged[$index].Database.Parent, $nativeServer) | Should -BeTrue
            }
            $record = $merged[1]
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.Exception | Should -BeOfType System.Management.Automation.MethodInvocationException
            $record.Exception.Message | Should -BeExactly $expectedMessage
            $record.FullyQualifiedErrorId | Should -BeExactly 'ScriptMethodRuntimeException,Dataplat.Dbatools.Commands.GetDbaDbStateCommand'
            $record.CategoryInfo.Category | Should -Be 'NotSpecified'
            $record.TargetObject | Should -BeNullOrEmpty
            $record.InvocationInfo.MyCommand.Name | Should -BeExactly 'Get-DbaDbState'

            # A failed first input must also reach the later valid instance.
            $hidden.Count | Should -Be 1
            $hidden[0].DatabaseName | Should -BeExactly $nativeFixtureName
            $hiddenErrors.Count | Should -Be 1
            $hiddenErrors[0].Exception.Message | Should -BeExactly $expectedMessage

            # The try around Invoke below belongs to the parent runspace. The measured script
            # has no error handler, so an enclosing catch cannot mask the effect of ErrorAction.
            $measureStop = {
                param($manifest, $good, $denied, $arguments)
                Import-Module $manifest -ErrorAction Stop
                $good, $denied, $good | Get-DbaDbState @arguments
                "next statement"
            }
            foreach ($mode in 'ErrorAction', 'EnableException') {
                $splatStateStop = @{
                    Database        = $nativeFixtureName
                    EnableException = ($mode -eq 'EnableException')
                    ErrorAction     = $(if ($mode -eq 'ErrorAction') { 'Stop' } else { 'Continue' })
                }
                $stopShell = [System.Management.Automation.PowerShell]::Create()
                $stopOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                try {
                    $null = $stopShell.AddScript($measureStop.ToString()).AddArgument($manifest).AddArgument($nativeServer).AddArgument($denied).AddArgument($splatStateStop)
                    $invocationStop = $null
                    try { $null = $stopShell.Invoke($null, $stopOutput) } catch { $invocationStop = $_.Exception.InnerException }
                    if ($mode -eq 'ErrorAction') {
                        $invocationStop | Should -Not -BeNullOrEmpty
                        $stopRecord = $invocationStop.ErrorRecord
                        $stopOutput.Count | Should -Be 1
                    } else {
                        $invocationStop | Should -BeNullOrEmpty
                        $stopShell.Streams.Error.Count | Should -Be 1
                        $stopRecord = $stopShell.Streams.Error[0]
                        $stopOutput.Count | Should -Be 2
                        $stopOutput[1] | Should -BeExactly "next statement"
                    }
                    $stopOutput[0].DatabaseName | Should -BeExactly $nativeFixtureName
                    $stopRecord.FullyQualifiedErrorId | Should -BeExactly $record.FullyQualifiedErrorId
                    $stopRecord.Exception.Message | Should -BeExactly $expectedMessage
                    $stopRecord.CategoryInfo.Category | Should -Be $record.CategoryInfo.Category
                    $stopRecord.TargetObject | Should -BeNullOrEmpty
                } finally {
                    $stopShell.Dispose()
                    $stopOutput.Dispose()
                }
            }

            foreach ($mode in 'CallerTry', 'ErrorAction', 'EnableException') {
                $parameters = @{
                    Database = $nativeFixtureName
                    EnableException = ($mode -eq 'EnableException')
                    ErrorAction = $(if ($mode -eq 'ErrorAction') { 'Stop' } else { 'Continue' })
                }
                $streamed = New-Object 'System.Collections.Generic.List[object]'
                $caught = $null
                try {
                    $nativeServer, $denied, $nativeServer | Get-DbaDbState @parameters |
                        ForEach-Object { $streamed.Add($_) }
                } catch { $caught = $_ }
                $streamed.Count | Should -Be 1
                $streamed[0].DatabaseName | Should -BeExactly $nativeFixtureName
                $caught | Should -Not -BeNullOrEmpty
                $caught.FullyQualifiedErrorId | Should -BeExactly $record.FullyQualifiedErrorId
                $caught.Exception.Message | Should -BeExactly $expectedMessage
                $caught.CategoryInfo.Category | Should -Be $record.CategoryInfo.Category
                $caught.TargetObject | Should -BeNullOrEmpty
            }
        } finally {
            try {
                if ($null -ne $denied) {
                    try { $denied.ConnectionContext.ExecuteNonQuery('REVERT;') | Out-Null }
                    finally { $denied.ConnectionContext.Disconnect() }
                }
            } finally {
                if ($created) { $nativeServer.Databases['master'].ExecuteNonQuery("DROP USER [$userName];") }
            }
        }
    }

    It "preserves earlier output before EnableException terminates the pipeline" -Tag NativeChecklist:enable-exception {
        $nativeEarlierRows = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle) |
                & $CommandName @nativeParameters -EnableException |
                ForEach-Object { $nativeEarlierRows.Add($_) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeEarlierRows.Count | Should -Be 1
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaDbState SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $loginStateName = "native_state_login_$([guid]::NewGuid().ToString("N"))"
        $splatLoginConnection = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        $loginStateServer = Connect-DbaInstance @splatLoginConnection
        $loginStateDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database($loginStateServer, $loginStateName)
        $loginStateDatabase.Create()
    }

    AfterAll {
        if ($null -ne $loginStateServer) {
            $loginStateServer.Databases.Refresh()
            $loginStateCleanup = $loginStateServer.Databases[$loginStateName]
            if ($null -ne $loginStateCleanup) { $loginStateCleanup.Drop() }
        }
    }

    It "returns database state with SQL credentials" {
        $splatLoginState = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            Database        = $loginStateName
            EnableException = $true
        }
        $loginStateOutput = @(Get-DbaDbState @splatLoginState)
        $loginStateOutput.Count | Should -Be 1
        $loginStateOutput[0].DatabaseName | Should -BeExactly $loginStateName
        $loginStateOutput[0].Status | Should -BeExactly "ONLINE"
        $loginStateOutput[0].RW | Should -BeExactly "READ_WRITE"
        $loginStateOutput[0].Access | Should -BeExactly "MULTI_USER"
    }

    It "warns without output when SQL credentials are omitted" {
        $loginStateWarnings = @()
        $splatLoginStateDenied = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Database        = $loginStateName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "loginStateWarnings"
        }
        # Pin public/Get-DbaDbState.ps1:123-127, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        @(Get-DbaDbState @splatLoginStateDenied).Count | Should -Be 0
        $loginStateWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # The pinned function catches its Connect-DbaInstance failure and invokes Stop-Function directly.
        $splatLoginStateThrow = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Database        = $loginStateName
            EnableException = $true
        }
        # Pin public/Get-DbaDbState.ps1:123-127, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        { Get-DbaDbState @splatLoginStateThrow } | Should -Throw
    }
}

Describe "Get-DbaDbState Azure SQL Database" -Tag IntegrationTests, NativeChecklist:azure-sqldb {
    It "returns the current database state from Azure SQL Database" {
        $azureStateServer = $null
        $splatAzureStateConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 15
            EnableException = $true
        }
        for ($azureStateAttempt = 1; $azureStateAttempt -le 7; $azureStateAttempt++) {
            try {
                $azureStateServer = Connect-DbaInstance @splatAzureStateConnection
                break
            } catch {
                $azureStateRetryable = $false
                $azureStateError = $PSItem.Exception
                while ($azureStateError) {
                    if ($azureStateError.Number -in @(-2, 40613) -or $azureStateError -is [System.TimeoutException] -or $azureStateError.Message -match 'timed out|timeout|wait operation') { $azureStateRetryable = $true }
                    $azureStateError = $azureStateError.InnerException
                }
                if (-not $azureStateRetryable -or $azureStateAttempt -eq 7) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureStateServer | Should -Not -BeNullOrEmpty
        $azureStateServer.DatabaseEngineEdition | Should -Be SqlDatabase
        $azureStateExpected = $azureStateServer.ConnectionContext.ExecuteWithResults("SELECT state_desc, user_access_desc, is_read_only FROM sys.databases WHERE database_id = DB_ID();").Tables[0].Rows[0]
        $azureStateExpectedRw = if ($azureStateExpected.is_read_only) { "READ_ONLY" } else { "READ_WRITE" }
        try {
            # Whole pinned-module probe pinned-azure-identity-20261031.txt measured these three modes on both editions.
            # ServiceName and output InstanceName are null on Azure; the SMO InstanceName property is an empty string.
            foreach ($azureStateMode in @('Continue', 'Stop', 'EnableException')) {
                $azureStateErrors = @()
                $azureStateWarnings = @()
                $splatAzureState = @{
                    SqlInstance     = $azureStateServer
                    Database        = $TestConfig.AzureSqlDbName
                    ErrorAction     = 'Continue'
                    ErrorVariable   = 'azureStateErrors'
                    WarningVariable = 'azureStateWarnings'
                }
                if ($azureStateMode -eq 'Stop') { $splatAzureState.ErrorAction = 'Stop' }
                if ($azureStateMode -eq 'EnableException') { $splatAzureState.EnableException = $true }
                $azureStateOutput = @(Get-DbaDbState @splatAzureState)
                $azureStateErrors.Count | Should -Be 0
                $azureStateWarnings.Count | Should -Be 0
                $azureStateOutput.Count | Should -Be 1
                $azureStateOutput[0].DatabaseName | Should -BeExactly $TestConfig.AzureSqlDbName
                $azureStateOutput[0].SqlInstance | Should -BeExactly $azureStateServer.Name
                $azureStateOutput[0].ComputerName | Should -BeExactly $azureStateServer.Name
                ($null -eq $azureStateOutput[0].InstanceName) | Should -BeTrue
                $azureStateOutput[0].Status | Should -BeExactly $azureStateExpected.state_desc
                $azureStateOutput[0].Access | Should -BeExactly $azureStateExpected.user_access_desc
                $azureStateOutput[0].RW | Should -BeExactly $azureStateExpectedRw
                $azureStateOutput[0].Database | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
            }
        } finally {
            $azureStateServer.ConnectionContext.Disconnect()
        }
    }
}

