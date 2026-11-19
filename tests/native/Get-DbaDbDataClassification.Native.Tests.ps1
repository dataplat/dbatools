#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbDataClassification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native data classification behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeClassServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeClassSuffix = [Guid]::NewGuid().ToString("N")
        $nativeClassDatabaseName = "native_class_" + $nativeClassSuffix
        $nativeClassGoneName = "native_class_gone_" + $nativeClassSuffix
        $nativeClassCreated = @()
        foreach ($nativeClassName in @($nativeClassDatabaseName, $nativeClassGoneName)) {
            $nativeClassNew = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeClassServer, $nativeClassName
            $nativeClassNew.Create()
            $nativeClassCreated += $nativeClassName
        }
        $nativeClassDatabase = $nativeClassServer.Databases[$nativeClassDatabaseName]
        $nativeClassLabels = @(
            @("sys_information_type_id", "native-type-id"),
            @("sys_information_type_name", "Native Contact"),
            @("sys_sensitivity_label_id", "native-label-id"),
            @("sys_sensitivity_label_name", "Native Confidential")
        )
        $nativeClassDatabase.ExecuteNonQuery("CREATE SCHEMA [native_sales];")
        $nativeClassDatabase.ExecuteNonQuery("CREATE TABLE [native_sales].[native_people] ([Id] int, [Email] nvarchar(255), [Plain] int);")
        foreach ($nativeClassLabel in $nativeClassLabels) {
            $nativeClassDatabase.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'$($nativeClassLabel[0])', @value = N'$($nativeClassLabel[1])', @level0type = N'SCHEMA', @level0name = N'native_sales', @level1type = N'TABLE', @level1name = N'native_people', @level2type = N'COLUMN', @level2name = N'Email'")
        }
        # Only the information type is set on Id, so the label columns read as DBNull.
        $nativeClassDatabase.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'sys_information_type_name', @value = N'Native Identifier', @level0type = N'SCHEMA', @level0name = N'native_sales', @level1type = N'TABLE', @level1name = N'native_people', @level2type = N'COLUMN', @level2name = N'Id'")
    }

    AfterAll {
        if ($nativeClassCreated.Count -gt 0) {
            $splatRemoveNativeClassDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $nativeClassCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeClassDatabase
        }
    }

    It "emits one record per classified column for each piped database and keeps the caller's database context" -Tag "NativeChecklist:pipeline-multiple" {
        $nativeClassPiped = Get-DbaDatabase -SqlInstance $nativeClassServer -Database $nativeClassDatabaseName -EnableException
        $nativeClassContext = $nativeClassServer.ConnectionContext.CurrentDatabase
        $nativeClassRows = @(@($nativeClassPiped, $nativeClassPiped) | Get-DbaDbDataClassification -EnableException)
        $nativeClassRows.Count | Should -Be 4
        $nativeClassServer.ConnectionContext.CurrentDatabase | Should -BeExactly $nativeClassContext
        ($nativeClassRows.Column -join ",") | Should -BeExactly "Email,Id,Email,Id"
        foreach ($nativeClassRow in $nativeClassRows) {
            $nativeClassRow | Should -BeOfType System.Management.Automation.PSCustomObject
            ($nativeClassRow.PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,Schema,Table,Column,InformationTypeId,InformationType,SensitivityLabelId,SensitivityLabel,DatabaseObject"
            $nativeClassRow.ComputerName | Should -BeExactly $nativeClassPiped.ComputerName
            $nativeClassRow.InstanceName | Should -BeExactly $nativeClassPiped.InstanceName
            $nativeClassRow.SqlInstance | Should -BeExactly $nativeClassPiped.SqlInstance
            $nativeClassRow.Database | Should -BeExactly $nativeClassDatabaseName
            $nativeClassRow.Schema | Should -BeExactly "native_sales"
            $nativeClassRow.Table | Should -BeExactly "native_people"
            $nativeClassRow.DatabaseObject | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
            $nativeClassRow.DatabaseObject.Name | Should -BeExactly $nativeClassDatabaseName
        }
        $nativeClassRows[0].InformationTypeId | Should -BeExactly "native-type-id"
        $nativeClassRows[0].InformationType | Should -BeExactly "Native Contact"
        $nativeClassRows[0].SensitivityLabelId | Should -BeExactly "native-label-id"
        $nativeClassRows[0].SensitivityLabel | Should -BeExactly "Native Confidential"
        $nativeClassRows[1].InformationType | Should -BeExactly "Native Identifier"
        $nativeClassRows[1].SensitivityLabel | Should -BeOfType System.DBNull
    }

    It "filters schema, table and column by literal case-insensitive name" {
        $splatNativeClassFilter = @{
            SqlInstance     = $nativeClassServer
            Database        = $nativeClassDatabaseName
            Schema          = "NATIVE_SALES"
            Table           = "Native_People"
            Column          = "email"
            EnableException = $true
        }
        $nativeClassFiltered = @(Get-DbaDbDataClassification @splatNativeClassFilter)
        $nativeClassFiltered.Count | Should -Be 1
        $nativeClassFiltered[0].Column | Should -BeExactly "Email"
        $splatNativeClassFilter.Column = "Plain"
        @(Get-DbaDbDataClassification @splatNativeClassFilter).Count | Should -Be 0
        $splatNativeClassFilter.Column = "E*"
        @(Get-DbaDbDataClassification @splatNativeClassFilter).Count | Should -Be 0
        $splatNativeClassFilter.Remove("Column")
        $splatNativeClassFilter.Schema = "dbo"
        @(Get-DbaDbDataClassification @splatNativeClassFilter).Count | Should -Be 0
    }

    It "warns and continues for a database that cannot be queried unless EnableException terminates" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeClassGone = Get-DbaDatabase -SqlInstance $nativeClassServer -Database $nativeClassGoneName -EnableException
        $nativeClassGood = Get-DbaDatabase -SqlInstance $nativeClassServer -Database $nativeClassDatabaseName -EnableException
        $splatNativeClassDrop = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = $nativeClassGoneName
            Confirm         = $false
            EnableException = $true
        }
        $null = Remove-DbaDatabase @splatNativeClassDrop

        $nativeClassWarnings = @()
        $splatNativeClassWarn = @{
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeClassWarnings"
        }
        $nativeClassContinued = @(@($nativeClassGone, $nativeClassGood) | Get-DbaDbDataClassification @splatNativeClassWarn)
        $nativeClassContinued.Count | Should -Be 2
        @($nativeClassContinued | Where-Object Database -ne $nativeClassDatabaseName).Count | Should -Be 0
        ($nativeClassWarnings -join " ") | Should -BeLike "*Error querying data classifications in $nativeClassGoneName on *"

        $nativeClassCaught = $null
        try {
            @($nativeClassGone, $nativeClassGood) | Get-DbaDbDataClassification -EnableException | Out-Null
        } catch {
            $nativeClassCaught = $PSItem
        }
        $nativeClassCaught | Should -Not -BeNullOrEmpty
        $nativeClassCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbDataClassification*"
        # Database.Query has no catch, so the record keeps the whole failure chain and Stop-Function's
        # default exception transform reports its first nested SqlException.
        $nativeClassCaught.Exception.InnerException | Should -BeOfType Microsoft.Data.SqlClient.SqlException
        $nativeClassCaught.Exception.InnerException.Message | Should -BeLike "*$nativeClassGoneName*"
        [string]$nativeClassCaught.TargetObject | Should -BeLike "*$nativeClassGoneName*"
    }

    Context "Piped databases together with SqlInstance" {
        BeforeAll {
            # Pinned :118-120 assigns the gathered databases over $InputObject when -SqlInstance is given, so a
            # database piped or passed to -InputObject alongside it was silently dropped from the results.
            $nativeClassSecondName = "native_class_second_" + [Guid]::NewGuid().ToString("N")
            $nativeClassSecondCreated = $false
            $nativeClassSecond = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeClassServer, $nativeClassSecondName
            $nativeClassSecond.Create()
            $nativeClassSecondCreated = $true
            $nativeClassSecond.ExecuteNonQuery("CREATE TABLE [dbo].[native_second] ([Code] int); EXEC sys.sp_addextendedproperty @name = N'sys_information_type_name', @value = N'Native Second', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'native_second', @level2type = N'COLUMN', @level2name = N'Code';")
        }

        AfterAll {
            # Drop through its own connection, not by killing sessions on the shared test connection.
            if ($nativeClassSecondCreated) {
                $splatRemoveNativeClassSecond = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Database        = $nativeClassSecondName
                    Confirm         = $false
                    EnableException = $true
                }
                $null = Remove-DbaDatabase @splatRemoveNativeClassSecond
            }
        }

        It "keeps a piped database and adds the databases gathered from SqlInstance" {
            $nativeClassPipedFirst = Get-DbaDatabase -SqlInstance $nativeClassServer -Database $nativeClassDatabaseName -EnableException
            $splatNativeClassCombined = @{
                SqlInstance     = $nativeClassServer
                Database        = $nativeClassSecondName
                EnableException = $true
            }
            $nativeClassCombinedRows = @($nativeClassPipedFirst | Get-DbaDbDataClassification @splatNativeClassCombined)
            (($nativeClassCombinedRows | ForEach-Object { $PSItem.Database + ":" + $PSItem.Column }) -join ",") | Should -BeExactly "${nativeClassDatabaseName}:Email,${nativeClassDatabaseName}:Id,${nativeClassSecondName}:Code"
            $nativeClassCombinedRows[2].InformationType | Should -BeExactly "Native Second"
            $splatNativeClassCombined.InputObject = $nativeClassPipedFirst
            $nativeClassBoundRows = @(Get-DbaDbDataClassification @splatNativeClassCombined)
            (($nativeClassBoundRows | ForEach-Object { $PSItem.Database + ":" + $PSItem.Column }) -join ",") | Should -BeExactly "${nativeClassDatabaseName}:Email,${nativeClassDatabaseName}:Id,${nativeClassSecondName}:Code"
        }
    }

    It "continues after a connection failure while gathering databases, even with EnableException" -Tag "NativeChecklist:multi-instance-failure" {
        $nativeClassSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeClassListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeClassListener.Start()
            $nativeClassFailedInstance = "127.0.0.1," + $nativeClassListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeClassFailureWarnings = @()
            $splatNativeClassFailure = @{
                SqlInstance     = @($TestConfig.InstanceSingle, $nativeClassFailedInstance, $TestConfig.InstanceSingle)
                Database        = $nativeClassDatabaseName
                Column          = "Email"
                EnableException = $true
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeClassFailureWarnings"
            }
            # Get-DbaDatabase is not given -EnableException upstream, so the failure only warns.
            $nativeClassSurvivors = @(Get-DbaDbDataClassification @splatNativeClassFailure)
            $nativeClassSurvivors.Count | Should -Be 2
            ($nativeClassSurvivors.Column -join ",") | Should -BeExactly "Email,Email"
            ($nativeClassFailureWarnings -join " ") | Should -BeLike "*Failure*"
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeClassSavedTimeout
            $nativeClassListener.Stop()
        }
    }
}

Describe "Native Get-DbaDbDataClassification on Azure SQL Database" -Tag IntegrationTests {
    It "reads a classified column in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once on the connected server.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: a unique table, dropped with its extended properties.
        $azureTableName = "native_class_azure_" + [Guid]::NewGuid().ToString("N")
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureTableName] ([Id] int, [Email] nvarchar(255));")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'sys_information_type_name', @value = N'Native Contact', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$azureTableName', @level2type = N'COLUMN', @level2name = N'Email';")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'sys_sensitivity_label_name', @value = N'Native Confidential', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$azureTableName', @level2type = N'COLUMN', @level2name = N'Email';")
            $splatAzureClassification = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                Table           = $azureTableName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbDataClassification @splatAzureClassification)
            $azureRows.Count | Should -Be 1
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].Schema | Should -BeExactly "dbo"
            $azureRows[0].Column | Should -BeExactly "Email"
            $azureRows[0].InformationType | Should -BeExactly "Native Contact"
            $azureRows[0].SensitivityLabel | Should -BeExactly "Native Confidential"
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureTableName]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureTableName];")
        }
    }
}

Describe "Native Get-DbaDbDataClassification over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_class_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_login_people] ([Id] int, [Email] nvarchar(255));")
            $loginDatabase.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name = N'sys_information_type_name', @value = N'Native Contact', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'native_login_people', @level2type = N'COLUMN', @level2name = N'Email';")
        }
        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginClassification = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbDataClassification @splatLoginClassification)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Column | Should -BeExactly "Email"
            $loginRows[0].InformationType | Should -BeExactly "Native Contact"
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested database gather, which is not given
            # -EnableException, so it warns and continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    Database        = $loginDbName
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaDbDataClassification @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
