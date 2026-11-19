#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaStoredProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Find-DbaStoredProcedure" -Tag IntegrationTests {
    BeforeAll {
        $procBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        # Two databases of this run only; SMO lists databases by name, so _a is searched before _b.
        $procPrefix = "dbatoolsci_fsp_$([Guid]::NewGuid().ToString("N"))"
        $procDbA = "$($procPrefix)_a"
        $procDbB = "$($procPrefix)_b"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $procDbA, $procDbB -EnableException
        $procPlainText = @(
            "CREATE PROCEDURE dbo.fsp_plain",
            "AS",
            "SET NOCOUNT ON;",
            "SELECT 'fsp_hit_marker' AS hit;",
            "SELECT 'FSP_HIT_MARKER' AS shout;"
        ) -join "`r`n"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $procDbA -Query $procPlainText -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $procDbB -Query "CREATE PROCEDURE dbo.fsp_other AS SELECT 'fsp_hit_marker' AS hit;" -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $procDbB -Query "CREATE PROCEDURE dbo.fsp_secret WITH ENCRYPTION AS SELECT 1 AS one;" -EnableException
        $procServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $procDbA, $procDbB -Confirm:$false
    }

    It "returns the matching procedure with the source's properties, matched lines and default view" {
        $procRows = @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA -Pattern "fsp_hit_marker" -EnableException)
        $procRows.Count | Should -Be 1
        $procRow = $procRows[0]
        @($procRow.PSObject.Properties.Name) | Should -BeExactly @("ComputerName", "SqlInstance", "Database", "DatabaseId", "Schema", "Name", "Owner", "IsSystemObject", "CreateDate", "LastModified", "StoredProcedureTextFound", "StoredProcedure", "StoredProcedureFullText")
        $procRow.SqlInstance | Should -BeExactly $procServer.ServiceName
        $procRow.Database | Should -BeExactly $procDbA
        $procRow.DatabaseId | Should -Be $procServer.Databases[$procDbA].ID
        $procRow.Schema | Should -BeExactly "dbo"
        $procRow.Name | Should -BeExactly "fsp_plain"
        $procRow.IsSystemObject | Should -BeFalse
        $procRow.CreateDate | Should -BeOfType System.DateTime
        $procRow.LastModified | Should -BeOfType System.DateTime
        $procRow.StoredProcedure | Should -BeOfType Microsoft.SqlServer.Management.Smo.StoredProcedure
        $procRow.StoredProcedureFullText | Should -BeExactly $procPlainText
        $procRow.StoredProcedureTextFound | Should -BeExactly ("(LineNumber: 4) SELECT 'fsp_hit_marker' AS hit;" + [System.Environment]::NewLine + "(LineNumber: 5) SELECT 'FSP_HIT_MARKER' AS shout;")
        $procDisplay = @($procRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        $procDisplay | Should -Not -Contain "StoredProcedure"
        $procDisplay | Should -Not -Contain "StoredProcedureFullText"
        $procDisplay | Should -Contain "StoredProcedureTextFound"
        $procDisplay.Count | Should -Be 11
    }

    It "matches definitions case-insensitively and supports regular expressions" {
        @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA -Pattern "SET\s+NOCOUNT\s+ON" -EnableException).Name | Should -BeExactly @("fsp_plain")
        @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA -Pattern "no_such_text_anywhere" -EnableException).Count | Should -Be 0
    }

    It "treats the two switches set to `$false as not given" -Tag NativeChecklist:switch-false {
        $splatSwitches = @{
            SqlInstance            = $TestConfig.InstanceSingle
            Database               = $procDbA
            Pattern                = "fsp_hit_marker"
            IncludeSystemObjects   = $false
            IncludeSystemDatabases = $false
            EnableException        = $true
        }
        @(Find-DbaStoredProcedure @splatSwitches).Name | Should -BeExactly @("fsp_plain")
    }

    It "compares -Database and -ExcludeDatabase names without regard to case" {
        @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA.ToUpperInvariant() -Pattern "fsp_hit_marker" -EnableException).Name | Should -BeExactly @("fsp_plain")
        @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA -ExcludeDatabase $procDbA.ToUpperInvariant() -Pattern "fsp_hit_marker" -EnableException).Count | Should -Be 0
    }

    It "selects databases by a documented wildcard pattern" {
        $wildRows = @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database "$($procPrefix)_*" -Pattern "fsp_hit_marker" -EnableException | Sort-Object Database)
        @($wildRows.Database) | Should -BeExactly @($procDbA, $procDbB)
        @($wildRows.Name) | Should -BeExactly @("fsp_plain", "fsp_other")
    }

    It "excludes databases by a documented wildcard pattern" {
        $excludeRows = @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA, $procDbB -ExcludeDatabase "$($procPrefix)_b*" -Pattern "fsp_hit_marker" -EnableException)
        @($excludeRows.Database) | Should -BeExactly @($procDbA)
    }

    It "reports an encrypted procedure without another procedure's matched lines" {
        $encryptedErrors = @()
        $encryptedRows = @(Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA, $procDbB -Pattern "^$|fsp_hit_marker" -ErrorVariable encryptedErrors -ErrorAction SilentlyContinue)
        $encryptedErrors.Count | Should -Be 0
        @($encryptedRows.Name | Sort-Object) | Should -BeExactly @("fsp_other", "fsp_plain", "fsp_secret")
        $secretRow = @($encryptedRows | Where-Object Name -eq "fsp_secret")
        $secretRow.Count | Should -Be 1
        $secretRow[0].Database | Should -BeExactly $procDbB
        [string]$secretRow[0].StoredProcedureTextFound | Should -BeExactly ""
        $secretRow[0].StoredProcedureFullText | Should -BeOfType System.DBNull
    }

    It "stops on a pattern that is not a valid regular expression, as the -match statement does inside a try" {
        $patternCaught = $null
        try {
            $null = Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $procDbA -Pattern "fsp_[" -EnableException
        } catch {
            $patternCaught = $PSItem
        }
        $patternCaught | Should -Not -BeNullOrEmpty
        $patternCaught.FullyQualifiedErrorId | Should -BeLike "InvalidRegularExpression*"
    }

    It "searches every piped instance" -Tag NativeChecklist:pipeline-multiple {
        $pipedRows = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaStoredProcedure -Database $procDbA -Pattern "fsp_hit_marker" -EnableException)
        $pipedRows.Count | Should -Be 2
        @($pipedRows.Name | Select-Object -Unique) | Should -BeExactly @("fsp_plain")
    }

    It "warns for a failed instance and continues with the next one" -Tag NativeChecklist:multi-instance-failure {
        $procWarnings = @()
        $splatContinue = @{
            SqlInstance     = @($procBadInstance, $TestConfig.InstanceSingle)
            Database        = $procDbA
            Pattern         = "fsp_hit_marker"
            WarningVariable = "procWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $continueRows = @(Find-DbaStoredProcedure @splatContinue)
        ($procWarnings -join " ") | Should -BeLike "*Failure*"
        $continueRows.Name | Should -BeExactly @("fsp_plain")
    }

    It "keeps earlier output before -EnableException stops at a failed instance" -Tag NativeChecklist:enable-exception {
        $procStreamed = New-Object "System.Collections.Generic.List[object]"
        $procCaught = $null
        try {
            Find-DbaStoredProcedure -SqlInstance $TestConfig.InstanceSingle, $procBadInstance -Database $procDbA -Pattern "fsp_hit_marker" -EnableException |
                ForEach-Object { $procStreamed.Add($PSItem) }
        } catch {
            $procCaught = $PSItem
        }
        $procStreamed.Count | Should -Be 1
        $procCaught | Should -Not -BeNullOrEmpty
        $procCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Find-DbaStoredProcedure over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginDbName = "dbatoolsci_fsplogin_$([Guid]::NewGuid().ToString("N"))"
            $null = New-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Name $loginDbName -EnableException
            $null = Invoke-DbaQuery -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Query "CREATE PROCEDURE dbo.fsp_login AS SELECT 'fsp_login_marker' AS hit;" -EnableException
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Confirm:$false
        }

        It "works with -SqlCredential" {
            $loginRows = @(Find-DbaStoredProcedure -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Pattern "fsp_login_marker" -EnableException)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "fsp_login"
            $loginRows[0].Database | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $loginRows = @(Find-DbaStoredProcedure -SqlInstance $loginInstance -Database $loginDbName -Pattern "fsp_login_marker" -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $loginCaught = $null
            try {
                $null = Find-DbaStoredProcedure -SqlInstance $loginInstance -Database $loginDbName -Pattern "fsp_login_marker" -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Find-DbaStoredProcedure on Azure SQL Database" -Tag IntegrationTests {
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
        # Six legs share the database: a procedure and marker of this run only.
        $azureToken = [Guid]::NewGuid().ToString("N")
        $azureProc = "fsp_$azureToken"
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE PROCEDURE dbo.[$azureProc] AS SELECT 'fspmark_$azureToken' AS hit;")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureProc]') IS NOT NULL DROP PROCEDURE dbo.[$azureProc];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "finds a procedure in the database and reports the logical server as SqlInstance" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureRows = @(Find-DbaStoredProcedure -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -Pattern "fspmark_$azureToken" -EnableException)
        $azureRows.Count | Should -Be 1
        $azureRows[0].Name | Should -BeExactly $azureProc
        $azureRows[0].Schema | Should -BeExactly "dbo"
        $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $azureRows[0].StoredProcedureTextFound | Should -BeLike "(LineNumber: 1) *fspmark_$azureToken*"
        # Azure SQL Database has no SQL Server service; the instance is the logical server.
        $azureRows[0].SqlInstance | Should -Not -BeNullOrEmpty
        $azureRows[0].SqlInstance | Should -BeExactly $azureServer.SqlInstance
    }
}
