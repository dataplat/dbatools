#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Set-DbaResourceGovernor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- ALTER RESOURCE GOVERNOR applies to SQL Server and Azure SQL Managed Instance only, not Azure SQL Database (https://learn.microsoft.com/sql/t-sql/statements/alter-resource-governor-transact-sql); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Set-DbaResourceGovernor" -Tag IntegrationTests {
    BeforeAll {
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeMaster = $nativeServer.Databases["master"]
        $nativeGovernor = $nativeServer.ResourceGovernor
        $nativeGovernor.Refresh()
        $nativeOriginalEnabled = [bool]$nativeGovernor.Enabled
        $nativeOriginalClassifier = [string]$nativeGovernor.ClassifierFunction
        $nativeBadInstance = "TCP:127.0.0.1,1"

        $nativePrefix = "native_rg_" + [Guid]::NewGuid().ToString("N")
        $nativeFunction = "${nativePrefix}_fn"
        # A name with a closing bracket: the classifier reaches ALTER RESOURCE GOVERNOR only as SMO's quoted name.
        $nativeBracketFunction = "${nativePrefix}_b]r"
        $nativeCreated = New-Object System.Collections.Generic.List[string]
        foreach ($nativeName in @($nativeFunction, $nativeBracketFunction)) {
            $nativeQuoted = "[dbo].[" + $nativeName.Replace("]", "]]") + "]"
            $nativeMaster.ExecuteNonQuery("CREATE FUNCTION $nativeQuoted() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'default'; END;")
            $nativeCreated.Add($nativeName)
        }

        # The stored configuration, read from the server rather than from the command's output.
        $nativeReadConfig = {
            $nativeQuery = "SELECT OBJECT_SCHEMA_NAME(classifier_function_id, 1) AS SchemaName, OBJECT_NAME(classifier_function_id, 1) AS FunctionName, classifier_function_id AS FunctionId, is_enabled AS IsEnabled FROM sys.resource_governor_configuration;"
            $nativeServer.ConnectionContext.ExecuteWithResults($nativeQuery).Tables[0].Rows[0]
        }
        $null = Set-DbaResourceGovernor -SqlInstance $nativeServer -Disabled -ClassifierFunction "NULL" -EnableException
    }

    AfterAll {
        if ($nativeServer) {
            $nativeRestore = if ($nativeOriginalClassifier) { $nativeOriginalClassifier } else { "NULL" }
            $nativeServer.ConnectionContext.ExecuteNonQuery("ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = $nativeRestore);")
            if ($nativeOriginalEnabled) {
                $nativeServer.ConnectionContext.ExecuteNonQuery("ALTER RESOURCE GOVERNOR RECONFIGURE;")
            } else {
                $nativeServer.ConnectionContext.ExecuteNonQuery("ALTER RESOURCE GOVERNOR DISABLE;")
            }
            foreach ($nativeName in $nativeCreated) {
                $nativeQuoted = "[dbo].[" + $nativeName.Replace("]", "]]") + "]"
                $nativeLiteral = $nativeQuoted.Replace("'", "''")
                $nativeMaster.ExecuteNonQuery("IF OBJECT_ID(N'$nativeLiteral') IS NOT NULL DROP FUNCTION $nativeQuoted;")
            }
        }
    }

    It "sets a classifier function found case-insensitively in master and returns the decorated governor" {
        $result = @(Set-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -ClassifierFunction $nativeFunction.ToUpperInvariant() -EnableException)
        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourceGovernor
        $result[0].ClassifierFunction | Should -BeExactly "[dbo].[$nativeFunction]"
        $result[0].ComputerName | Should -Not -BeNullOrEmpty
        $result[0].InstanceName | Should -Not -BeNullOrEmpty
        $result[0].SqlInstance | Should -Not -BeNullOrEmpty
        ($result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,ClassifierFunction,Enabled,MaxOutstandingIOPerVolume,ReconfigurePending,ResourcePools,ExternalResourcePools"
        $config = & $nativeReadConfig
        $config.SchemaName | Should -BeExactly "dbo"
        $config.FunctionName | Should -BeExactly $nativeFunction
    }

    It "sets a classifier function whose name holds a closing bracket" {
        $result = @(Set-DbaResourceGovernor -SqlInstance $nativeServer -ClassifierFunction $nativeBracketFunction -EnableException)
        $result.Count | Should -Be 1
        $config = & $nativeReadConfig
        $config.FunctionName | Should -BeExactly $nativeBracketFunction
    }

    It "clears the classifier function for NULL written in any case" {
        $null = Set-DbaResourceGovernor -SqlInstance $nativeServer -ClassifierFunction $nativeFunction -EnableException
        $result = @(Set-DbaResourceGovernor -SqlInstance $nativeServer -ClassifierFunction "null" -EnableException)
        $result.Count | Should -Be 1
        $result[0].ClassifierFunction | Should -Be ""
        (& $nativeReadConfig).FunctionId | Should -Be 0
    }

    It "keeps a pattern-like name literal: warns that it does not exist, changes nothing and returns nothing" {
        $null = Set-DbaResourceGovernor -SqlInstance $nativeServer -Disabled -EnableException
        $nativeWarnings = @()
        $splatMissing = @{
            SqlInstance        = $nativeServer
            ClassifierFunction = "${nativePrefix}_*"
            Enabled            = $true
            WarningVariable    = "nativeWarnings"
            WarningAction      = "SilentlyContinue"
        }
        @(Set-DbaResourceGovernor @splatMissing).Count | Should -Be 0
        ($nativeWarnings -join " ") | Should -BeLike "*Classifier function '${nativePrefix}_``*' does not exist.*"
        $config = & $nativeReadConfig
        $config.IsEnabled | Should -Be $false
        $config.FunctionId | Should -Be 0
    }

    It "throws ObjectNotFound for a missing classifier function under -EnableException" {
        $nativeCaught = $null
        try {
            $null = Set-DbaResourceGovernor -SqlInstance $nativeServer -ClassifierFunction "${nativePrefix}_missing" -EnableException
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ObjectNotFound"
        (& $nativeReadConfig).FunctionId | Should -Be 0
    }

    It "prefers -Enabled over -Disabled and honours switches passed as false" -Tag "NativeChecklist:switch-false" {
        $result = @(Set-DbaResourceGovernor -SqlInstance $nativeServer -Enabled -Disabled -EnableException)
        $result[0].Enabled | Should -Be $true
        (& $nativeReadConfig).IsEnabled | Should -Be $true

        $result = @(Set-DbaResourceGovernor -SqlInstance $nativeServer -Enabled:$false -Disabled:$false -EnableException)
        $result.Count | Should -Be 1
        (& $nativeReadConfig).IsEnabled | Should -Be $true

        $result = @(Set-DbaResourceGovernor -SqlInstance $nativeServer -Enabled:$false -Disabled -EnableException)
        $result[0].Enabled | Should -Be $false
        (& $nativeReadConfig).IsEnabled | Should -Be $false
    }

    It "changes nothing under -WhatIf, still returns the governor, and applies with -Confirm:`$false" -Tag "NativeChecklist:whatif-confirm" {
        $null = Set-DbaResourceGovernor -SqlInstance $nativeServer -Disabled -ClassifierFunction "NULL" -EnableException
        $nativeWarnings = @()
        $splatWhatIf = @{
            SqlInstance        = $nativeServer
            Enabled            = $true
            ClassifierFunction = "${nativePrefix}_missing"
            WhatIf             = $true
            WarningVariable    = "nativeWarnings"
            EnableException    = $true
        }
        $result = @(Set-DbaResourceGovernor @splatWhatIf)
        $result.Count | Should -Be 1
        $result[0].Enabled | Should -Be $false
        $nativeWarnings.Count | Should -Be 0
        $config = & $nativeReadConfig
        $config.IsEnabled | Should -Be $false
        $config.FunctionId | Should -Be 0

        $result = @(Set-DbaResourceGovernor -SqlInstance $nativeServer -Enabled -ClassifierFunction $nativeFunction -Confirm:$false -EnableException)
        $result[0].Enabled | Should -Be $true
        $config = & $nativeReadConfig
        $config.IsEnabled | Should -Be $true
        $config.FunctionName | Should -BeExactly $nativeFunction
        $null = Set-DbaResourceGovernor -SqlInstance $nativeServer -Disabled -ClassifierFunction "NULL" -EnableException
    }

    It "warns for a failed middle instance and continues with the others" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure" {
        $nativeWarnings = @()
        $splatContinue = @{
            WhatIf          = $true
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $result = @($nativeServer, $nativeBadInstance, $TestConfig.InstanceSingle | Set-DbaResourceGovernor @splatContinue)
        $result.Count | Should -Be 2
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "streams earlier output before -EnableException stops at the failed instance" -Tag "NativeChecklist:enable-exception" {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            $nativeServer, $nativeBadInstance, $nativeServer |
                Set-DbaResourceGovernor -WhatIf -EnableException |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Set-DbaResourceGovernor refuses Azure SQL Database" -Tag IntegrationTests {
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            Enabled         = $true
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Set-DbaResourceGovernor @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Set-DbaResourceGovernor -SqlInstance $azureServer -Enabled -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Set-DbaResourceGovernor over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        # The instance is shared by every leg and run, so these calls use -WhatIf and change nothing there.
        It "works with -SqlCredential" {
            $loginRows = @(Set-DbaResourceGovernor -SqlInstance $loginInstance -SqlCredential $loginCred -Enabled -WhatIf -EnableException)
            $loginRows.Count | Should -Be 1
            $loginRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourceGovernor
            $loginRows[0].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Enabled         = $true
                WhatIf          = $true
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            @(Set-DbaResourceGovernor @splatLoginNoCredential).Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Set-DbaResourceGovernor -SqlInstance $loginInstance -Enabled -WhatIf -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
