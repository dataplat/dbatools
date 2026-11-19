#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaDbGrowthEvent",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing.
# NativeChecklist: azure-sqldb N/A -- the default trace (sys.traces, fn_trace_gettable) exists only in SQL Server and Azure SQL Managed Instance (https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-traces-transact-sql); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

BeforeAll {
    # A database with small files that grow while a table fills, so the default trace records growth events for it.
    function New-NativeGrowthDatabase {
        param($Server, [string]$Name)
        $fileStem = "dbatoolsci_growth_" + [Guid]::NewGuid().ToString("N")
        $dataPath = $Server.ConnectionContext.ExecuteScalar("SELECT CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultDataPath'))")
        $logPath = $Server.ConnectionContext.ExecuteScalar("SELECT CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultLogPath'))")
        $quotedName = "[" + $Name.Replace("]", "]]") + "]"
        $createSql = "CREATE DATABASE $quotedName ON PRIMARY (NAME = N'$($fileStem)_data', FILENAME = N'$($dataPath.Replace("'", "''"))$($fileStem).mdf', SIZE = 8MB, FILEGROWTH = 8MB) LOG ON (NAME = N'$($fileStem)_log', FILENAME = N'$($logPath.Replace("'", "''"))$($fileStem).ldf', SIZE = 8MB, FILEGROWTH = 8MB);"
        $null = $Server.ConnectionContext.ExecuteNonQuery($createSql)
        $fillSql = "USE $quotedName; CREATE TABLE dbo.growth (c char(8000) NOT NULL); INSERT dbo.growth (c) SELECT TOP (3000) 'x' FROM sys.all_objects a CROSS JOIN sys.all_objects b; USE [master];"
        $null = $Server.ConnectionContext.ExecuteNonQuery($fillSql)
        $Server.Databases.Refresh()
    }
}

Describe "Native Find-DbaDbGrowthEvent" -Tag IntegrationTests {
    BeforeAll {
        $growthServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $growthBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $growthSuffix = [Guid]::NewGuid().ToString("N")
        $growthPlain = "dbatoolsci_growplain_$growthSuffix"
        $growthQuoted = "dbatoolsci_grow'quote_$growthSuffix"
        $growthUnicode = "dbatoolsci_grow" + ([char]0x6f22).ToString() + ([char]0x5b57).ToString() + "_$growthSuffix"
        foreach ($growthName in $growthPlain, $growthQuoted, $growthUnicode) {
            New-NativeGrowthDatabase -Server $growthServer -Name $growthName
        }
        $growthDefaults = "ComputerName,InstanceName,SqlInstance,EventClass,DatabaseName,Filename,Duration,StartTime,EndTime,ChangeInSize,ApplicationName,HostName"
    }

    AfterAll {
        foreach ($growthName in $growthPlain, $growthQuoted, $growthUnicode) {
            $growthQuotedName = "[" + $growthName.Replace("]", "]]") + "]"
            $growthLiteral = $growthName.Replace("'", "''")
            $null = $growthServer.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$growthLiteral') IS NOT NULL BEGIN ALTER DATABASE $growthQuotedName SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $growthQuotedName; END")
        }
    }

    It "returns the database's growth events as rows with the pinned default view" {
        $growthRows = @(Find-DbaDbGrowthEvent -SqlInstance $TestConfig.InstanceSingle -Database $growthPlain -EventType Growth -EnableException)
        $growthRows.Count | Should -BeGreaterThan 0
        @($growthRows.DatabaseName | Select-Object -Unique) | Should -Be @($growthPlain)
        @($growthRows.DatabaseId | Select-Object -Unique) | Should -Be @($growthServer.Databases[$growthPlain].ID)
        @($growthRows | Where-Object EventClass -notin 92, 93).Count | Should -Be 0
        $growthRows[0] | Should -BeOfType System.Data.DataRow
        ($growthRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $growthDefaults
    }

    It "narrows the event classes by file type and event type" {
        $splatData = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = $growthPlain
            FileType        = "Data"
            EnableException = $true
        }
        $growthData = @(Find-DbaDbGrowthEvent @splatData)
        $growthData.Count | Should -BeGreaterThan 0
        @($growthData | Where-Object EventClass -notin 92, 94).Count | Should -Be 0
        $splatData.EventType = "Growth"
        @(Find-DbaDbGrowthEvent @splatData | Where-Object EventClass -ne 92).Count | Should -Be 0
        $splatData.Remove("FileType")
        $splatData.EventType = "Shrink"
        @(Find-DbaDbGrowthEvent @splatData | Where-Object EventClass -notin 94, 95).Count | Should -Be 0
    }

    It "reports UTC times unless -UseLocalTime is given" -Tag NativeChecklist:switch-false {
        $growthOffset = $growthServer.ConnectionContext.ExecuteScalar("SELECT DATEDIFF(MINUTE, GETDATE(), GETUTCDATE())")
        $splatTime = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = $growthPlain
            EventType       = "Growth"
            UseLocalTime    = $false
            EnableException = $true
        }
        $growthUtc = @(Find-DbaDbGrowthEvent @splatTime)
        $splatTime.UseLocalTime = $true
        $growthLocal = @(Find-DbaDbGrowthEvent @splatTime)
        $growthLocal.Count | Should -Be $growthUtc.Count
        $growthLocal[0].StartTime.AddMinutes($growthOffset) | Should -Be $growthUtc[0].StartTime
    }

    It "finds the events of a database whose name contains a quote" {
        $growthRows = @(Find-DbaDbGrowthEvent -SqlInstance $TestConfig.InstanceSingle -Database $growthQuoted -EventType Growth -EnableException)
        $growthRows.Count | Should -BeGreaterThan 0
        @($growthRows.DatabaseName | Select-Object -Unique) | Should -Be @($growthQuoted)
    }

    It "finds the events of a database whose name has characters outside the code page" {
        $growthRows = @(Find-DbaDbGrowthEvent -SqlInstance $TestConfig.InstanceSingle -Database $growthUnicode -EventType Growth -EnableException)
        $growthRows.Count | Should -BeGreaterThan 0
        @($growthRows.DatabaseName | Select-Object -Unique) | Should -Be @($growthUnicode)
    }

    It "searches every piped instance" -Tag NativeChecklist:pipeline-multiple {
        $growthRows = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaDbGrowthEvent -Database $growthPlain -EventType Growth -EnableException)
        $growthSingle = @(Find-DbaDbGrowthEvent -SqlInstance $TestConfig.InstanceSingle -Database $growthPlain -EventType Growth -EnableException)
        $growthRows.Count | Should -Be (2 * $growthSingle.Count)
    }

    It "warns for a failed instance and continues with the next one" -Tag NativeChecklist:multi-instance-failure {
        $growthWarnings = @()
        $splatContinue = @{
            SqlInstance     = @($growthBadInstance, $TestConfig.InstanceSingle)
            Database        = $growthPlain
            EventType       = "Growth"
            WarningVariable = "growthWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $growthRows = @(Find-DbaDbGrowthEvent @splatContinue)
        ($growthWarnings -join " ") | Should -BeLike "*Failure*"
        $growthRows.Count | Should -BeGreaterThan 0
    }

    It "keeps earlier output before -EnableException stops at a failed instance" -Tag NativeChecklist:enable-exception {
        $growthStreamed = New-Object "System.Collections.Generic.List[object]"
        $growthCaught = $null
        try {
            Find-DbaDbGrowthEvent -SqlInstance $TestConfig.InstanceSingle, $growthBadInstance -Database $growthPlain -EventType Growth -EnableException |
                ForEach-Object { $growthStreamed.Add($PSItem) }
        } catch {
            $growthCaught = $PSItem
        }
        $growthStreamed.Count | Should -BeGreaterThan 0
        $growthCaught | Should -Not -BeNullOrEmpty
        $growthCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Find-DbaDbGrowthEvent over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginWarnings = @()
            $splatLogin = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = "master"
                Verbose         = $true
                EnableException = $true
                WarningVariable = "loginWarnings"
            }
            $loginStreams = @(Find-DbaDbGrowthEvent @splatLogin 4>&1)
            @($loginStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Executing query against 'master' on*" }).Count | Should -Be 1
            $loginWarnings.Count | Should -Be 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $loginRows = @(Find-DbaDbGrowthEvent -SqlInstance $loginInstance -Database master -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $loginCaught = $null
            try {
                $null = Find-DbaDbGrowthEvent -SqlInstance $loginInstance -Database master -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Find-DbaDbGrowthEvent refuses Azure SQL Database" -Tag IntegrationTests {
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
        @(Find-DbaDbGrowthEvent @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Find-DbaDbGrowthEvent -SqlInstance $azureServer -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $azureCaught.Exception.ToString() | Should -BeLike "*Azure SQL Database not supported*"
    }
}
