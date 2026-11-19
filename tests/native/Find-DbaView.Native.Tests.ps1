#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaView",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Find-DbaView" -Tag IntegrationTests {
    BeforeAll {
        $vwBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        # Two databases and a marker of this run only; SMO lists databases by name, so _a is searched before _b.
        $vwGuid = [Guid]::NewGuid().ToString("N")
        $vwToken = "nvwmark$vwGuid"
        $vwPrefix = "nativevw_$vwGuid"
        $vwDbA = "$($vwPrefix)_a"
        $vwDbB = "$($vwPrefix)_b"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $vwDbA, $vwDbB -EnableException
        # CR LF line ends for one view, LF line ends for the other; the marker sits in a comment inside the select.
        $vwCrlfText = @("CREATE VIEW dbo.nvw_crlf", "AS", "SELECT 1 AS one", "-- $vwToken crlf", "UNION ALL SELECT 2 AS one") -join "`r`n"
        $vwLfText = @("CREATE VIEW dbo.nvw_lf", "AS", "SELECT 1 AS one", "-- $vwToken lf", "UNION ALL SELECT 2 AS one") -join "`n"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA -Query $vwCrlfText -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA -Query $vwLfText -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $vwDbB -Query "CREATE VIEW dbo.nvw_other AS SELECT '$vwToken' AS hit;" -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $vwDbB -Query "CREATE VIEW dbo.nvw_secret WITH ENCRYPTION AS SELECT 1 AS one;" -EnableException
        $vwServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA, $vwDbB -Confirm:$false
    }

    It "returns the matching views with the source's properties and default view" {
        $vwRows = @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA -Pattern $vwToken -EnableException | Sort-Object Name)
        $vwRows.Count | Should -Be 2
        @($vwRows.Name) | Should -BeExactly @("nvw_crlf", "nvw_lf")
        foreach ($vwRow in $vwRows) {
            @($vwRow.PSObject.Properties.Name) | Should -BeExactly @("ComputerName", "SqlInstance", "Database", "DatabaseId", "Schema", "Name", "Owner", "IsSystemObject", "CreateDate", "LastModified", "ViewTextFound", "View", "ViewFullText")
            $vwRow.SqlInstance | Should -BeExactly $vwServer.ServiceName
            $vwRow.Database | Should -BeExactly $vwDbA
            $vwRow.DatabaseId | Should -Be $vwServer.Databases[$vwDbA].ID
            $vwRow.Schema | Should -BeExactly "dbo"
            $vwRow.IsSystemObject | Should -BeFalse
            $vwRow.CreateDate | Should -BeOfType System.DateTime
            $vwRow.LastModified | Should -BeOfType System.DateTime
            $vwRow.View | Should -BeOfType Microsoft.SqlServer.Management.Smo.View
            $vwRow.ViewFullText | Should -BeLike "*$vwToken*"
            $vwRow.ViewTextFound | Should -BeLike "(LineNumber: *$vwToken*"
            $vwDisplay = @($vwRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            $vwDisplay | Should -Not -Contain "View"
            $vwDisplay | Should -Not -Contain "ViewFullText"
            $vwDisplay | Should -Contain "ViewTextFound"
            $vwDisplay.Count | Should -Be 11
        }
    }

    It "reports the line numbers of matched view lines" {
        $lineRows = @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA -Pattern $vwToken -EnableException)
        $lineRows.Count | Should -Be 2
        foreach ($lineRow in $lineRows) {
            # The real line numbers of the reported text, whatever its line ends.
            $lineParts = [string]$lineRow.ViewFullText -split "\r\n|\r|\n"
            $lineExpected = @(for ($lineIndex = 0; $lineIndex -lt $lineParts.Count; $lineIndex++) {
                    if ($lineParts[$lineIndex] -match $vwToken) { "(LineNumber: $($lineIndex + 1)) $($lineParts[$lineIndex].Trim())" }
                })
            $lineExpected.Count | Should -Be 1
            $lineRow.ViewTextFound | Should -BeExactly $lineExpected[0]
        }
    }

    It "finds the same views through SMO with -IncludeSystemObjects" {
        $smoRows = @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA -Pattern $vwToken -IncludeSystemObjects -EnableException | Sort-Object Name)
        @($smoRows.Name) | Should -BeExactly @("nvw_crlf", "nvw_lf")
        @($smoRows.Database | Select-Object -Unique) | Should -BeExactly @($vwDbA)
    }

    It "counts the views it evaluated and names their schema in its verbose messages" {
        $countStreams = @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA, $vwDbB -Pattern $vwToken -IncludeSystemObjects -Verbose 4>&1)
        $countMessages = @($countStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
        $countServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        foreach ($countDb in $vwDbA, $vwDbB) {
            $countLines = @($countMessages | Where-Object { $PSItem -match "Evaluated \d+ views in \[$countDb\]" })
            $countLines.Count | Should -Be 1
            [int]([regex]::Match($countLines[0], "Evaluated (\d+) views in").Groups[1].Value) | Should -Be $countServer.Databases[$countDb].Views.Count
        }
        @($countMessages | Where-Object { $PSItem -like "*Looking in View: dbo.nvw_crlf TextBody for $vwToken*" }).Count | Should -Be 1
        @($countMessages | Where-Object { $PSItem -like "*Looking in View: dbo.nvw_other TextBody for $vwToken*" }).Count | Should -Be 1
    }

    It "matches definitions case-insensitively and supports regular expressions" {
        @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbB -Pattern $vwToken.ToUpperInvariant() -EnableException).Name | Should -BeExactly @("nvw_other")
        @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbB -Pattern "SELECT\s+'nvwmark[0-9a-f]+'" -EnableException).Name | Should -BeExactly @("nvw_other")
        @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA -Pattern "no_such_text_anywhere" -EnableException).Count | Should -Be 0
    }

    It "treats the two switches set to `$false as not given" -Tag NativeChecklist:switch-false {
        $splatSwitches = @{
            SqlInstance            = $TestConfig.InstanceSingle
            Database               = $vwDbB
            Pattern                = $vwToken
            IncludeSystemObjects   = $false
            IncludeSystemDatabases = $false
            EnableException        = $true
        }
        @(Find-DbaView @splatSwitches).Name | Should -BeExactly @("nvw_other")
    }

    It "compares -Database and -ExcludeDatabase names without regard to case" {
        @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbB.ToUpperInvariant() -Pattern $vwToken -EnableException).Name | Should -BeExactly @("nvw_other")
        @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbB -ExcludeDatabase $vwDbB.ToUpperInvariant() -Pattern $vwToken -EnableException).Count | Should -Be 0
    }

    It "selects databases by a documented wildcard pattern" {
        $wildRows = @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database "$($vwPrefix)_*" -Pattern $vwToken -EnableException | Sort-Object Database, Name)
        @($wildRows.Database) | Should -BeExactly @($vwDbA, $vwDbA, $vwDbB)
        @($wildRows.Name) | Should -BeExactly @("nvw_crlf", "nvw_lf", "nvw_other")
    }

    It "reports an encrypted view without another view's matched lines" {
        $encryptedErrors = @()
        $encryptedRows = @(Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA, $vwDbB -Pattern "^$|$vwToken" -ErrorVariable encryptedErrors -ErrorAction SilentlyContinue)
        $encryptedErrors.Count | Should -Be 0
        @($encryptedRows.Name | Sort-Object) | Should -BeExactly @("nvw_crlf", "nvw_lf", "nvw_other", "nvw_secret")
        $secretRow = @($encryptedRows | Where-Object Name -eq "nvw_secret")
        $secretRow.Count | Should -Be 1
        $secretRow[0].Database | Should -BeExactly $vwDbB
        [string]$secretRow[0].ViewTextFound | Should -BeExactly ""
        $secretRow[0].ViewFullText | Should -BeNullOrEmpty
    }

    It "stops on a pattern that is not a valid regular expression, as the -match statement does inside a try" {
        $patternCaught = $null
        try {
            $null = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Database $vwDbA -Pattern "nvw_[" -EnableException
        } catch {
            $patternCaught = $PSItem
        }
        $patternCaught | Should -Not -BeNullOrEmpty
        $patternCaught.FullyQualifiedErrorId | Should -BeLike "InvalidRegularExpression*"
    }

    It "searches every piped instance" -Tag NativeChecklist:pipeline-multiple {
        $pipedRows = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaView -Database $vwDbB -Pattern $vwToken -EnableException)
        $pipedRows.Count | Should -Be 2
        @($pipedRows.Name | Select-Object -Unique) | Should -BeExactly @("nvw_other")
    }

    It "warns for a failed instance and continues with the next one" -Tag NativeChecklist:multi-instance-failure {
        $vwWarnings = @()
        $splatContinue = @{
            SqlInstance     = @($vwBadInstance, $TestConfig.InstanceSingle)
            Database        = $vwDbB
            Pattern         = $vwToken
            WarningVariable = "vwWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $continueRows = @(Find-DbaView @splatContinue)
        ($vwWarnings -join " ") | Should -BeLike "*Failure*"
        $continueRows.Name | Should -BeExactly @("nvw_other")
    }

    It "keeps earlier output before -EnableException stops at a failed instance" -Tag NativeChecklist:enable-exception {
        $vwStreamed = New-Object "System.Collections.Generic.List[object]"
        $vwCaught = $null
        try {
            Find-DbaView -SqlInstance $TestConfig.InstanceSingle, $vwBadInstance -Database $vwDbB -Pattern $vwToken -EnableException |
                ForEach-Object { $vwStreamed.Add($PSItem) }
        } catch {
            $vwCaught = $PSItem
        }
        $vwStreamed.Count | Should -Be 1
        $vwCaught | Should -Not -BeNullOrEmpty
        $vwCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Find-DbaView over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginDbName = "nativevwlogin_$([Guid]::NewGuid().ToString("N"))"
            $null = New-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Name $loginDbName -EnableException
            $null = Invoke-DbaQuery -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Query "CREATE VIEW dbo.nvw_login AS SELECT 'nvw_login_marker' AS hit;" -EnableException
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Confirm:$false
        }

        It "works with -SqlCredential" {
            $loginRows = @(Find-DbaView -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Pattern "nvw_login_marker" -EnableException)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "nvw_login"
            $loginRows[0].Database | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $loginRows = @(Find-DbaView -SqlInstance $loginInstance -Database $loginDbName -Pattern "nvw_login_marker" -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $loginCaught = $null
            try {
                $null = Find-DbaView -SqlInstance $loginInstance -Database $loginDbName -Pattern "nvw_login_marker" -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Find-DbaView on Azure SQL Database" -Tag IntegrationTests {
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
        # Six legs share the database: a view and marker of this run only.
        $azureToken = [Guid]::NewGuid().ToString("N")
        $azureView = "nvw_$azureToken"
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE VIEW dbo.[$azureView] AS SELECT 'nvwazure_$azureToken' AS hit;")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureView]') IS NOT NULL DROP VIEW dbo.[$azureView];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "finds a view in the database and reports the logical server as SqlInstance" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureRows = @(Find-DbaView -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -Pattern "nvwazure_$azureToken" -EnableException)
        $azureRows.Count | Should -Be 1
        $azureRows[0].Name | Should -BeExactly $azureView
        $azureRows[0].Schema | Should -BeExactly "dbo"
        $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $azureRows[0].ViewTextFound | Should -BeLike "(LineNumber: *) *nvwazure_$azureToken*"
        # Azure SQL Database has no SQL Server service; the instance is the logical server.
        $azureRows[0].SqlInstance | Should -Not -BeNullOrEmpty
        $azureRows[0].SqlInstance | Should -BeExactly $azureServer.SqlInstance
    }
}
