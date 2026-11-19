#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaConnectionStringBuilder",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this command only constructs an in-memory builder and does not support ShouldProcess.
# NativeChecklist: multi-instance-failure N/A -- DataSource is scalar and the command never connects; malformed pipeline records are covered separately.
# NativeChecklist: sql2005 N/A -- the command constructs an in-memory connection string builder and opens no SQL Server connection.

Describe "Native runner test hosting" {
    It "keeps the dbatools platform state accessible after the first pinned file" {
        (Get-PSCallStack).Command | Should -Contain "Invoke-ManualPester"
        $platformState = InModuleScope -ModuleName dbatools -ScriptBlock { $script:isWindows }
        $platformState | Should -BeTrue
    }

    It "provides test configuration and the compiled builder on the second invocation" {
        $TestConfig | Should -Not -BeNullOrEmpty
        (Get-Command New-DbaConnectionStringBuilder).CommandType | Should -Be "Cmdlet"
        (New-DbaConnectionStringBuilder).GetType().FullName | Should -Be "Microsoft.Data.SqlClient.SqlConnectionStringBuilder"
    }
}

Describe "Connection builder public error reporting" {
    It "warns for an invalid middle record and continues without silent ErrorVariable capture" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeBuilderWarnings = @()
        $nativeBuilderErrors = @()
        $splatBuilderContinue = @{
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "nativeBuilderWarnings"
            ErrorVariable = "nativeBuilderErrors"
        }
        $nativeBuilderRows = @("Data Source=first", "unsupported-secret-marker=value", "Data Source=last" |
            New-DbaConnectionStringBuilder @splatBuilderContinue)
        $nativeBuilderRows.Count | Should -Be 2
        $nativeBuilderRows[0].DataSource | Should -BeExactly "first"
        $nativeBuilderRows[1].DataSource | Should -BeExactly "last"
        $nativeBuilderWarnings.Count | Should -Be 1
        $nativeBuilderWarnings[0].Message | Should -BeLike "*The connection string is invalid.*"
        $nativeBuilderWarnings[0].Message | Should -Not -BeLike "*unsupported-secret-marker*"
        $nativeBuilderErrors.Count | Should -Be 0
    }

    It "rejects an invalid override without emitting a partially configured builder" {
        $invalidApplicationName = "native" + [char]0 + "invalid"
        $overrideWarnings = @()
        $overrideRows = @(New-DbaConnectionStringBuilder -ConnectionString "Data Source=original" -ApplicationName $invalidApplicationName -DataSource replacement -EnableException:$false -WarningAction SilentlyContinue -WarningVariable overrideWarnings)
        $overrideRows.Count | Should -Be 0
        $overrideWarnings.Count | Should -Be 1
        $overrideWarnings[0].Message | Should -BeLike "*The connection string overrides are invalid.*"
        { New-DbaConnectionStringBuilder -ConnectionString "Data Source=original" -ApplicationName $invalidApplicationName -EnableException } | Should -Throw
    }

    It "honors explicit WarningAction when EnableException terminates an invalid record" {
        $nativeExplicitWarnings = @()
        $nativeExplicitOutput = New-Object "System.Collections.Generic.List[object]"
        $nativeExplicitFailure = $null
        $splatBuilderExplicit = @{
            ConnectionString = "unsupported-secret-marker=value"
            EnableException = $true
            WarningAction = "Continue"
            WarningVariable = "nativeExplicitWarnings"
        }
        try {
            New-DbaConnectionStringBuilder @splatBuilderExplicit 3>&1 |
                ForEach-Object { $nativeExplicitOutput.Add($PSItem) }
        } catch { $nativeExplicitFailure = $PSItem }
        $nativeExplicitFailure | Should -Not -BeNullOrEmpty
        $nativeExplicitWarnings.Count | Should -Be 1
        $nativeExplicitOutput.Count | Should -Be 1
        $nativeExplicitOutput[0] | Should -BeOfType System.Management.Automation.WarningRecord
        $nativeExplicitOutput[0].Message | Should -Not -BeLike "*unsupported-secret-marker*"
    }

    It "retains earlier output and terminates before later records with EnableException" -Tag NativeChecklist:enable-exception {
        $nativeTerminatingOutput = New-Object "System.Collections.Generic.List[object]"
        $nativeTerminatingFailure = $null
        try {
            "Data Source=before", "unsupported-secret-marker=value", "Data Source=after" |
                New-DbaConnectionStringBuilder -EnableException |
                ForEach-Object { $nativeTerminatingOutput.Add($PSItem) }
        } catch { $nativeTerminatingFailure = $PSItem }
        $nativeTerminatingOutput.Count | Should -Be 1
        $nativeTerminatingOutput[0].DataSource | Should -BeExactly "before"
        $nativeTerminatingFailure | Should -Not -BeNullOrEmpty
    }
}

Describe "Connection builder explicit false switches" {
    It "overrides enabled settings with explicit false switches" -Tag NativeChecklist:switch-false {
        $splatFalseBuilder = @{
            ConnectionString        = "Integrated Security=True;MultipleActiveResultSets=True;Pooling=False"
            IntegratedSecurity      = $false
            MultipleActiveResultSets = $false
            NonPooledConnection     = $false
            Legacy                  = $false
            EnableException         = $true
        }
        $falseBuilder = New-DbaConnectionStringBuilder @splatFalseBuilder
        $falseBuilder.GetType().FullName | Should -Be "Microsoft.Data.SqlClient.SqlConnectionStringBuilder"
        $falseBuilder.IntegratedSecurity | Should -BeFalse
        $falseBuilder.MultipleActiveResultSets | Should -BeFalse
        $falseBuilder.Pooling | Should -BeTrue
    }
}

Describe "Connection builder SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    It "builds a working SQL login connection" {
        $splatLoginBuilder = @{
            DataSource       = $TestConfig.InstanceSqlLogin
            SqlCredential    = $TestConfig.SqlLoginCred
            InitialCatalog   = "master"
            ConnectionString = "Encrypt=True;TrustServerCertificate=True;Connect Timeout=15"
            WorkstationID    = "native-tests"
            EnableException  = $true
        }
        # No commit can run the pin: the base ships the cmdlet, and the pin predates src/ and cannot be built.
        # Verbatim refs/pins/dbatools-2026-10-22:public/New-DbaConnectionStringBuilder.ps1:133-147:
        # if ($SqlCredential -and ($Username -or $Password)) {
        #     Stop-Function -Message "You can only specify SQL Credential or Username/Password, not both." -EnableException $EnableException
        #     return
        # }
        # if ($SqlCredential) {
        #     $UserName = $SqlCredential.UserName
        #     $Password = $SqlCredential.GetNetworkCredential().Password
        # }
        #
        # foreach ($cs in $ConnectionString) {
        #     if ($Legacy) {
        #         $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $cs
        #     } else {
        #         $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $cs
        #     }
        # Verbatim same pinned file:165-172:
        # if ($UserName) {
        #     $builder["User ID"] = $UserName
        # } elseif (!$IntegratedSecurity) {
        #     $builder['Integrated Security'] = $false
        # }
        # if ($Password) {
        #     $builder['Password'] = $Password
        # }
        # Verbatim same pinned file:195-198:
        #             $builder
        #         }
        #     }
        # }
        # Open below independently checks the generated string; the pinned function returns the builder without connecting.
        $loginBuilder = New-DbaConnectionStringBuilder @splatLoginBuilder
        $loginBuilder.IntegratedSecurity | Should -BeFalse
        $loginBuilder.UserID | Should -BeExactly $TestConfig.SqlLoginCred.UserName
        $loginBuilderConnection = New-Object Microsoft.Data.SqlClient.SqlConnection($loginBuilder.ConnectionString)
        try {
            $loginBuilderConnection.Open()
            $loginBuilderCommand = $loginBuilderConnection.CreateCommand()
            try {
                $loginBuilderCommand.CommandText = "SELECT 1;"
                $loginBuilderCommand.ExecuteScalar() | Should -Be 1
            } finally { $loginBuilderCommand.Dispose() }
        } finally { $loginBuilderConnection.Dispose() }
    }

    It "still constructs an unauthenticated builder without credentials for either EnableException value" {
        # The pinned function never opens a connection; omitted credentials do not cause a command failure.
        foreach ($loginBuilderEnable in @($false, $true)) {
            $splatEmptyLoginBuilder = @{
                DataSource       = $TestConfig.InstanceSqlLogin
                InitialCatalog   = "master"
                ConnectionString = "Encrypt=True;TrustServerCertificate=True;Connect Timeout=5;Pooling=False"
                WorkstationID    = "native-tests"
                EnableException  = $loginBuilderEnable
            }
            # No commit can run the pin: the base ships the cmdlet, and the pin predates src/ and cannot be built.
            # Verbatim refs/pins/dbatools-2026-10-22:public/New-DbaConnectionStringBuilder.ps1:133-147:
            # if ($SqlCredential -and ($Username -or $Password)) {
            #     Stop-Function -Message "You can only specify SQL Credential or Username/Password, not both." -EnableException $EnableException
            #     return
            # }
            # if ($SqlCredential) {
            #     $UserName = $SqlCredential.UserName
            #     $Password = $SqlCredential.GetNetworkCredential().Password
            # }
            #
            # foreach ($cs in $ConnectionString) {
            #     if ($Legacy) {
            #         $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $cs
            #     } else {
            #         $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $cs
            #     }
            # Verbatim same pinned file:165-172:
            # if ($UserName) {
            #     $builder["User ID"] = $UserName
            # } elseif (!$IntegratedSecurity) {
            #     $builder['Integrated Security'] = $false
            # }
            # if ($Password) {
            #     $builder['Password'] = $Password
            # }
            # Verbatim same pinned file:195-198:
            #             $builder
            #         }
            #     }
            # }
            # Open below independently checks the generated string; omitted credentials still return a builder for either switch value.
            $emptyLoginBuilder = New-DbaConnectionStringBuilder @splatEmptyLoginBuilder
            $emptyLoginBuilder | Should -BeOfType Microsoft.Data.SqlClient.SqlConnectionStringBuilder
            $emptyLoginBuilder.UserID | Should -BeNullOrEmpty
            $emptyLoginBuilder.Password | Should -BeNullOrEmpty
            $emptyLoginBuilder.IntegratedSecurity | Should -BeFalse
            $emptyLoginConnection = New-Object Microsoft.Data.SqlClient.SqlConnection($emptyLoginBuilder.ConnectionString)
            try {
                { $emptyLoginConnection.Open() } | Should -Throw
                $emptyLoginConnection.State | Should -Be Closed
            } finally { $emptyLoginConnection.Dispose() }
        }
    }
}

Describe "Connection builder Azure SQL Database" -Tag IntegrationTests, NativeChecklist:azure-sqldb {
    It "builds a working Azure SQL Database connection" {
        $splatAzureBuilder = @{
            DataSource       = $TestConfig.AzureSqlDbServer
            SqlCredential    = $TestConfig.AzureSqlDbCred
            InitialCatalog   = $TestConfig.AzureSqlDbName
            ConnectionString = "Encrypt=True;TrustServerCertificate=False;Connect Timeout=15;Pooling=False"
            WorkstationID    = "native-tests"
            EnableException  = $true
        }
        $azureBuilder = New-DbaConnectionStringBuilder @splatAzureBuilder
        $azureBuilderConnection = New-Object Microsoft.Data.SqlClient.SqlConnection($azureBuilder.ConnectionString)
        try {
            for ($azureBuilderAttempt = 1; $azureBuilderAttempt -le 7; $azureBuilderAttempt++) {
                try {
                    $azureBuilderConnection.Open()
                    break
                } catch {
                    $azureBuilderRetryable = $false
                    $azureBuilderError = $PSItem.Exception
                    while ($azureBuilderError) {
                        if ($azureBuilderError.Number -in @(-2, 40613) -or $azureBuilderError -is [System.TimeoutException]) { $azureBuilderRetryable = $true }
                        $azureBuilderError = $azureBuilderError.InnerException
                    }
                    if (-not $azureBuilderRetryable -or $azureBuilderAttempt -eq 7) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureBuilderConnection.State | Should -Be Open
            $azureBuilderConnection.Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureBuilderCommand = $azureBuilderConnection.CreateCommand()
            try {
                $azureBuilderCommand.CommandText = "SELECT CONVERT(int, SERVERPROPERTY('EngineEdition'));"
                $azureBuilderCommand.ExecuteScalar() | Should -Be 5
            } finally { $azureBuilderCommand.Dispose() }
        } finally { $azureBuilderConnection.Dispose() }
    }
}
