#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaDbDisabledIndex",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Find-DbaDbDisabledIndex" -Tag IntegrationTests {
    BeforeAll {
        $indexBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $indexSuffix = [Guid]::NewGuid().ToString("N")
        $indexDbName = "dbatoolsci_disidx_$indexSuffix"
        $indexServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $null = $indexServer.Query("CREATE DATABASE [$indexDbName]")
        $indexSetup = "CREATE TABLE dbo.disidx_table (id int NOT NULL, txt nvarchar(20)); CREATE INDEX ix_disidx ON dbo.disidx_table (txt); ALTER INDEX ix_disidx ON dbo.disidx_table DISABLE;"
        $null = $indexServer.Query($indexSetup, $indexDbName)
        # A second database whose real name ends in *, so the documented wildcard rule can be checked against a real
        # name. Windows file names cannot hold *, so its files are named explicitly.
        $indexStarDbName = "$indexDbName*"
        $indexPaths = $indexServer.Query("SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(260)) AS DataPath, CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS nvarchar(260)) AS LogPath, CAST(SERVERPROPERTY('PathSeparator') AS nvarchar(1)) AS Separator")
        $indexStarData = $indexPaths.DataPath.TrimEnd("\", "/") + $indexPaths.Separator + "dbatoolsci_disidx_$($indexSuffix)_star.mdf"
        $indexStarLog = $indexPaths.LogPath.TrimEnd("\", "/") + $indexPaths.Separator + "dbatoolsci_disidx_$($indexSuffix)_star_log.ldf"
        $null = $indexServer.Query("CREATE DATABASE [$indexStarDbName] ON (NAME = N'disidx_star', FILENAME = N'$indexStarData') LOG ON (NAME = N'disidx_star_log', FILENAME = N'$indexStarLog')")
        $null = $indexServer.Query($indexSetup, $indexStarDbName)
        $indexServer.Databases.Refresh()
        $indexDbId = $indexServer.Databases[$indexDbName].ID
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $indexDbName -Confirm:$false
        $null = $indexServer.Query("IF DB_ID(N'$indexStarDbName') IS NOT NULL BEGIN ALTER DATABASE [$indexStarDbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$indexStarDbName]; END", "master")
    }

    It "selects databases by a documented wildcard pattern" {
        $indexPrefixRows = @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_disidx_$($indexSuffix.Substring(0, 16))*" -EnableException)
        @($indexPrefixRows.DatabaseName | Sort-Object) | Should -BeExactly @($indexDbName, $indexStarDbName)
        $indexOneRows = @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database ($indexDbName.Substring(0, $indexDbName.Length - 1) + "?").ToUpperInvariant() -EnableException)
        @($indexOneRows.DatabaseName) | Should -BeExactly @($indexDbName)
    }

    It "selects a real database whose name contains * alone by its exact name" {
        $indexStarRows = @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database $indexStarDbName -EnableException)
        @($indexStarRows.DatabaseName) | Should -BeExactly @($indexStarDbName)
    }

    It "keeps bracket-only and invalid wildcard values literal" {
        @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database "[$indexDbName]" -EnableException).Count | Should -Be 0
        @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_disidx_[*" -EnableException).Count | Should -Be 0
    }

    It "returns the disabled index as the query's data row" {
        $indexRows = @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database $indexDbName -EnableException)
        $indexRows.Count | Should -Be 1
        $indexRows[0] | Should -BeOfType System.Data.DataRow
        $indexRows[0].DatabaseName | Should -BeExactly $indexDbName
        $indexRows[0].DatabaseId | Should -Be $indexDbId
        $indexRows[0].SchemaName | Should -BeExactly "dbo"
        $indexRows[0].TableName | Should -BeExactly "disidx_table"
        $indexRows[0].IndexName | Should -BeExactly "ix_disidx"
        $indexRows[0].TypeDesc | Should -BeExactly "NONCLUSTERED"
    }

    It "changes nothing and returns nothing under -WhatIf, and searches with -Confirm:`$false" -Tag NativeChecklist:whatif-confirm {
        @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database $indexDbName -WhatIf).Count | Should -Be 0
        @(Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database $indexDbName -Confirm:$false).IndexName | Should -BeExactly @("ix_disidx")
    }

    It "accepts the unused -NoClobber and -Append switches either way" -Tag NativeChecklist:switch-false {
        $splatSwitches = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = $indexDbName
            NoClobber       = $false
            Append          = $false
            EnableException = $true
        }
        @(Find-DbaDbDisabledIndex @splatSwitches).IndexName | Should -BeExactly @("ix_disidx")
        $splatSwitches.NoClobber = $true
        $splatSwitches.Append = $true
        @(Find-DbaDbDisabledIndex @splatSwitches).IndexName | Should -BeExactly @("ix_disidx")
    }

    It "skips an excluded database" {
        $splatExclude = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = $indexDbName
            ExcludeDatabase = $indexDbName.ToUpperInvariant()
            EnableException = $true
        }
        @(Find-DbaDbDisabledIndex @splatExclude).Count | Should -Be 0
    }

    It "searches every piped instance" -Tag NativeChecklist:pipeline-multiple {
        $indexRows = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaDbDisabledIndex -Database $indexDbName -EnableException)
        $indexRows.Count | Should -Be 2
        @($indexRows.IndexName | Select-Object -Unique) | Should -Be @("ix_disidx")
    }

    It "warns for a failed instance and continues with the next one" -Tag NativeChecklist:multi-instance-failure {
        $indexWarnings = @()
        $splatContinue = @{
            SqlInstance     = @($indexBadInstance, $TestConfig.InstanceSingle)
            Database        = $indexDbName
            WarningVariable = "indexWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $indexRows = @(Find-DbaDbDisabledIndex @splatContinue)
        ($indexWarnings -join " ") | Should -BeLike "*Failure*"
        $indexRows.IndexName | Should -BeExactly @("ix_disidx")
    }

    It "keeps earlier output before -EnableException stops at a failed instance" -Tag NativeChecklist:enable-exception {
        $indexStreamed = New-Object "System.Collections.Generic.List[object]"
        $indexCaught = $null
        try {
            Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle, $indexBadInstance -Database $indexDbName -EnableException |
                ForEach-Object { $indexStreamed.Add($PSItem) }
        } catch {
            $indexCaught = $PSItem
        }
        $indexStreamed.Count | Should -Be 1
        $indexCaught | Should -Not -BeNullOrEmpty
        $indexCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Find-DbaDbDisabledIndex over SQL authentication" -Tag IntegrationTests {
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
            $loginStreams = @(Find-DbaDbDisabledIndex @splatLogin 4>&1)
            @($loginStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Getting indexes from database 'master'.*" }).Count | Should -Be 1
            $loginWarnings.Count | Should -Be 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $loginRows = @(Find-DbaDbDisabledIndex -SqlInstance $loginInstance -Database master -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $loginCaught = $null
            try {
                $null = Find-DbaDbDisabledIndex -SqlInstance $loginInstance -Database master -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Find-DbaDbDisabledIndex on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once.
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
        # Six legs share the database: a table of this run only.
        $azureTable = "disidx_" + [Guid]::NewGuid().ToString("N")
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE dbo.[$azureTable] (id int NOT NULL, txt nvarchar(20)); CREATE INDEX [ix_$azureTable] ON dbo.[$azureTable] (txt); ALTER INDEX [ix_$azureTable] ON dbo.[$azureTable] DISABLE;")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureTable]') IS NOT NULL DROP TABLE dbo.[$azureTable];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "finds the disabled index in the database" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureRows = @(Find-DbaDbDisabledIndex -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $azureMine = @($azureRows | Where-Object TableName -eq $azureTable)
        $azureMine.Count | Should -Be 1
        $azureMine[0].IndexName | Should -BeExactly "ix_$azureTable"
        $azureMine[0].DatabaseName | Should -BeExactly $TestConfig.AzureSqlDbName
    }
}
