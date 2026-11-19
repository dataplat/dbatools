#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbDetachedFileInfo",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the header of a file.
# NativeChecklist: multi-instance-failure N/A -- The pinned -SqlInstance is a single DbaInstanceParameter with no pipeline input, so a run has no second instance to go on to.
# NativeChecklist: azure-sqldb N/A -- The command reads MDF files on the file system of the instance, through xp_fileexist and DBCC CHECKPRIMARYFILE. Detaching applies to SQL Server only (https://learn.microsoft.com/sql/relational-databases/databases/detach-a-database), and in Azure SQL Database the file placement is managed by the service and file-based statements are not available (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server), so no detached file exists to read. It refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does; "Native Get-DbaDbDetachedFileInfo refuses Azure SQL Database" below proves the refusal.

Describe "Native Get-DbaDbDetachedFileInfo" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $random = Get-Random
        $versionName = $server.GetSqlServerVersionName()

        # Creates a database, keeps what the file header must report, and detaches it.
        function New-DetachedDatabase {
            param($Target, [string]$Name)
            $escaped = $Name.Replace("'", "''")
            $quoted = $Name.Replace("]", "]]")
            $null = $Target.Query("CREATE DATABASE [$quoted];")
            $files = @($Target.Query("SELECT type_desc, physical_name FROM sys.master_files WHERE database_id = DB_ID(N'$escaped') ORDER BY file_id"))
            $details = @($Target.Query("SELECT CONVERT(sysname, DATABASEPROPERTYEX(N'$escaped', 'Collation')) AS collation_name, CONVERT(int, DATABASEPROPERTYEX(N'$escaped', 'Version')) AS version_number"))[0]
            $null = $Target.Query("EXEC master.dbo.sp_detach_db @dbname = N'$escaped';")
            [PSCustomObject]@{
                Name      = $Name
                Mdf       = ($files | Where-Object type_desc -eq "ROWS").physical_name
                Ldf       = ($files | Where-Object type_desc -eq "LOG").physical_name
                Files     = @($files.physical_name)
                Collation = $details.collation_name
                Version   = $details.version_number
            }
        }

        function Remove-DetachedDatabase {
            param($Target, $Database)
            if (-not $Database) { return }
            $escaped = $Database.Name.Replace("'", "''")
            $quoted = $Database.Name.Replace("]", "]]")
            $attach = ($Database.Files | ForEach-Object { "(FILENAME = N'$($PSItem.Replace("'", "''"))')" }) -join ", "
            $null = $Target.Query("IF DB_ID(N'$escaped') IS NULL CREATE DATABASE [$quoted] ON $attach FOR ATTACH;")
            $null = $Target.Query("ALTER DATABASE [$quoted] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$quoted];")
        }

        $detached = New-DetachedDatabase -Target $server -Name "dbatoolsci_ndetach_$random"
        $folder = Split-Path -Path $detached.Mdf -Parent
        $missing = "$($detached.Mdf).nosuch"
    }

    AfterAll {
        Remove-DetachedDatabase -Target $server -Database $detached
    }

    Context "Reading a detached file" {
        BeforeAll {
            $result = Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $detached.Mdf -EnableException
            $target = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$instance
        }

        It "returns one object with the pinned properties in the pinned order" {
            @($result).Count | Should -Be 1
            $result.PSObject.TypeNames[0] | Should -Be "System.Management.Automation.PSCustomObject"
            $expected = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Version", "ExactVersion", "Collation", "DataFiles", "LogFiles")
            $result.PSObject.Properties.Name | Should -Be $expected
        }

        It "names the instance as the caller gave it" {
            $result.ComputerName | Should -Be $target.ComputerName
            $result.InstanceName | Should -Be $target.InstanceName
            $result.SqlInstance | Should -Be $instance
        }

        It "reads the database name and the versions from the file" {
            $result.Name | Should -Be $detached.Name
            $result.Version | Should -Be $versionName
            "$($result.ExactVersion)" | Should -Be "$($detached.Version)"
        }

        It "resolves the collation id of the file to the collation name" {
            $result.Collation | Should -BeExactly $detached.Collation
        }

        It "lists the data and log files of the file" {
            @($result.DataFiles).Count | Should -Be 1
            "$(@($result.DataFiles)[0])" | Should -BeLike "*$($detached.Name).mdf*"
            @($result.LogFiles).Count | Should -Be 1
            "$(@($result.LogFiles)[0])" | Should -BeLike "*$($detached.Name)_log.ldf*"
        }
    }

    Context "Several paths and failures" {
        It "reads the paths from the pipeline and from the parameter" -Tag "NativeChecklist:pipeline-multiple" {
            @($detached.Mdf, $detached.Mdf | Get-DbaDbDetachedFileInfo -SqlInstance $instance).Count | Should -Be 2
            @(Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $detached.Mdf, $detached.Mdf).Count | Should -Be 2
        }

        It "warns about a path it cannot read and goes on to the next" {
            $result = @(Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $missing, $detached.Mdf -WarningVariable pathWarning -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be $detached.Name
            $pathWarning | Should -Not -BeNullOrEmpty
        }

        It "throws for that path under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            try {
                $null = Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $missing, $detached.Mdf -EnableException
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Message | Should -BeLike "*cannot access the file*"
        }

        It "reads -EnableException:`$false as not given" -Tag "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $missing, $detached.Mdf -EnableException:$false -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
        }

        It "says which file it cannot access and which account tried" {
            $result = Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $missing -WarningVariable accessWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $expected = "$($server.Name) cannot access the file $missing. Does the file exist and does the service account ($($server.ServiceAccount)) have access to the path?"
            "$accessWarning" | Should -BeLike "*$([WildcardPattern]::Escape($expected))"
        }

        It "warns about a folder and returns nothing" {
            $result = Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $folder -WarningVariable folderWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            "$folderWarning" | Should -BeLike "*$([WildcardPattern]::Escape($folder))*"
        }

        It "stops once at a failed connection, whatever the pipeline still holds" {
            $result = "first.mdf", "second.mdf" | Get-DbaDbDetachedFileInfo -SqlInstance $TestConfig.InstanceSqlLogin -WarningVariable connectWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($connectWarning).Count | Should -Be 1
            "$connectWarning" | Should -BeLike "*Failure*"
        }
    }

    Context "-Path text reaches the instance as text" {
        It "keeps a quote in -Path inside the path" {
            $marker = "dbatoolsci_nmarker_$random"
            $injection = "$($detached.Mdf)'; SELECT 1 AS x INTO tempdb.dbo.$marker --"
            try {
                $result = Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $injection -WarningVariable quoteWarning -WarningAction SilentlyContinue
                $found = @($server.Query("SELECT COUNT(*) AS marker FROM tempdb.sys.objects WHERE name = N'$marker'"))[0].marker
                $found | Should -Be 0
                $result | Should -BeNullOrEmpty
                "$quoteWarning" | Should -BeLike "*cannot access the file*"
            } finally {
                $null = $server.Query("IF OBJECT_ID(N'tempdb.dbo.$marker') IS NOT NULL DROP TABLE tempdb.dbo.$marker;")
            }
        }
    }

    Context "Wildcards in -Path" {
        It "expands a star in the file name" {
            $result = @(Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path "$folder\dbatoolsci_ndetach_$random*.mdf")
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be $detached.Name
        }

        It "expands a question mark in the file name" {
            $result = @(Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path "$folder\dbatoolsci_ndetach_${random}?mdf")
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be $detached.Name
        }

        It "says it cannot access a pattern that matches nothing" {
            $pattern = "$folder\dbatoolsci_ndetach_$random*.nosuch"
            $result = Get-DbaDbDetachedFileInfo -SqlInstance $instance -Path $pattern -WarningVariable patternWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            "$patternWarning" | Should -BeLike "*cannot access the file $([WildcardPattern]::Escape($pattern)).*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDetached = New-DetachedDatabase -Target $loginServer -Name "dbatoolsci_ndetachlogin_$(Get-Random)"
        }

        AfterAll {
            Remove-DetachedDatabase -Target $loginServer -Database $loginDetached
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaDbDetachedFileInfo -SqlInstance $loginInstance -SqlCredential $loginCred -Path $loginDetached.Mdf -EnableException)
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be $loginDetached.Name
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbDetachedFileInfo -SqlInstance $loginInstance -Path $loginDetached.Mdf -WarningVariable loginWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $loginWarning | Should -Not -BeNullOrEmpty
        }

        It "throws a connection error without the credential under -EnableException, as the pinned function does" {
            $caught = $null
            try {
                $null = Get-DbaDbDetachedFileInfo -SqlInstance $loginInstance -Path $loginDetached.Mdf -EnableException
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Get-DbaDbDetachedFileInfo refuses Azure SQL Database" -Tag IntegrationTests {
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") {
                        $isResuming = $true
                    }
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
            Path            = "C:\dbatoolsci_nosuch.mdf"
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Get-DbaDbDetachedFileInfo @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaDbDetachedFileInfo -SqlInstance $azureServer -Path "C:\dbatoolsci_nosuch.mdf" -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $azureCaught.Exception.ToString() | Should -BeLike "*Azure SQL Database not supported*"
    }
}
