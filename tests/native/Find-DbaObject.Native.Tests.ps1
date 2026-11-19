#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Find-DbaObject" -Tag IntegrationTests {
    BeforeAll {
        $objectBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $objectDbName = "dbatoolsci_findobj_$([Guid]::NewGuid().ToString("N"))"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $objectDbName -EnableException
        $objectSetup = @(
            "CREATE TABLE dbo.fdo_widget (id int NOT NULL, fdo_widgetcode int NULL);",
            "CREATE VIEW dbo.fdo_widgetview AS SELECT id FROM dbo.fdo_widget;",
            "CREATE PROCEDURE dbo.fdo_widgetproc AS SELECT 1 AS one;",
            "CREATE FUNCTION dbo.fdo_widgetscalar() RETURNS int AS BEGIN RETURN 1; END;",
            "CREATE FUNCTION dbo.fdo_widgetinline() RETURNS TABLE AS RETURN SELECT 1 AS fdo_inlinecol;",
            "CREATE FUNCTION dbo.fdo_widgetmulti() RETURNS @result TABLE (x int) AS BEGIN RETURN; END;",
            "CREATE SYNONYM dbo.fdo_widgetsyn FOR dbo.fdo_widget;",
            "CREATE TRIGGER dbo.fdo_widgettrg ON dbo.fdo_widget AFTER INSERT AS SET NOCOUNT ON;",
            "CREATE TRIGGER fdo_widgetddl ON DATABASE FOR CREATE_TABLE AS SET NOCOUNT ON;"
        )
        foreach ($objectStatement in $objectSetup) {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName -Query $objectStatement -EnableException
        }
        $objectServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName -Confirm:$false
    }

    It "returns every object type the help lists, with the source's properties in order" {
        $objectRows = @(Find-DbaObject -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName -Pattern "^fdo_widget" -EnableException)
        $objectRows.Count | Should -Be 9
        @($objectRows[0].PSObject.Properties.Name) | Should -BeExactly @("ComputerName", "SqlInstance", "Database", "Schema", "Name", "ObjectType", "MatchType", "ColumnName", "CreateDate", "LastModified")
        @($objectRows.Name | Sort-Object) | Should -BeExactly @("fdo_widget", "fdo_widgetddl", "fdo_widgetinline", "fdo_widgetmulti", "fdo_widgetproc", "fdo_widgetscalar", "fdo_widgetsyn", "fdo_widgettrg", "fdo_widgetview")
        @($objectRows.ObjectType | Sort-Object -Unique) | Should -BeExactly @("SQL_INLINE_TABLE_VALUED_FUNCTION", "SQL_SCALAR_FUNCTION", "SQL_STORED_PROCEDURE", "SQL_TABLE_VALUED_FUNCTION", "SQL_TRIGGER", "SYNONYM", "USER_TABLE", "VIEW")
        foreach ($objectRow in $objectRows) {
            $objectRow.SqlInstance | Should -BeExactly $objectServer.ServiceName
            $objectRow.Database | Should -BeExactly $objectDbName
            $objectRow.MatchType | Should -BeExactly "ObjectName"
            $objectRow.ColumnName | Should -BeNullOrEmpty
            $objectRow.CreateDate | Should -BeOfType System.DateTime
            $objectRow.LastModified | Should -BeOfType System.DateTime
        }
        $objectDdl = @($objectRows | Where-Object Name -eq "fdo_widgetddl")
        [string]::IsNullOrEmpty([string]$objectDdl[0].Schema) | Should -BeTrue
        @($objectRows | Where-Object Name -ne "fdo_widgetddl" | ForEach-Object { [string]$PSItem.Schema } | Sort-Object -Unique) | Should -BeExactly @("dbo")
    }

    It "limits the search to the object types asked for" {
        $splatTypes = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = $objectDbName
            Pattern         = "^fdo_widget"
            EnableException = $true
        }
        @(Find-DbaObject @splatTypes -ObjectType TableValuedFunction | Sort-Object Name).Name | Should -BeExactly @("fdo_widgetinline", "fdo_widgetmulti")
        @(Find-DbaObject @splatTypes -ObjectType Trigger | Sort-Object Name).Name | Should -BeExactly @("fdo_widgetddl", "fdo_widgettrg")
        @(Find-DbaObject @splatTypes -ObjectType Table, View | Sort-Object Name).Name | Should -BeExactly @("fdo_widget", "fdo_widgetview")
        @(Find-DbaObject @splatTypes -ObjectType synonym).Name | Should -BeExactly @("fdo_widgetsyn")
        @(Find-DbaObject @splatTypes -ObjectType StoredProcedure, ScalarFunction | Sort-Object Name).Name | Should -BeExactly @("fdo_widgetproc", "fdo_widgetscalar")
    }

    It "matches names case-insensitively, as -match does" {
        @(Find-DbaObject -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName -Pattern "^FDO_WIDGETPROC$" -EnableException).Name | Should -BeExactly @("fdo_widgetproc")
    }

    It "finds column names of tables and table-valued functions with -IncludeColumns" {
        $columnRows = @(Find-DbaObject -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName -Pattern "^fdo_(widgetcode|inlinecol)$" -IncludeColumns -EnableException | Sort-Object ColumnName)
        $columnRows.Count | Should -Be 2
        @($columnRows.MatchType | Sort-Object -Unique) | Should -BeExactly @("ColumnName")
        $columnRows[0].ColumnName | Should -BeExactly "fdo_inlinecol"
        $columnRows[0].Name | Should -BeExactly "fdo_widgetinline"
        $columnRows[0].ObjectType | Should -BeExactly "SQL_INLINE_TABLE_VALUED_FUNCTION"
        $columnRows[1].ColumnName | Should -BeExactly "fdo_widgetcode"
        $columnRows[1].Name | Should -BeExactly "fdo_widget"
        $columnRows[1].Schema | Should -BeExactly "dbo"
        $columnRows[1].ObjectType | Should -BeExactly "USER_TABLE"
    }

    It "treats the three switches set to `$false as not given" -Tag NativeChecklist:switch-false {
        $splatSwitches = @{
            SqlInstance            = $TestConfig.InstanceSingle
            Database               = $objectDbName
            Pattern                = "^fdo_widgetcode$"
            IncludeColumns         = $false
            IncludeSystemObjects   = $false
            IncludeSystemDatabases = $false
            EnableException        = $true
        }
        @(Find-DbaObject @splatSwitches).Count | Should -Be 0
        $splatSwitches.IncludeColumns = $true
        @(Find-DbaObject @splatSwitches).ColumnName | Should -BeExactly @("fdo_widgetcode")
    }

    It "searches system databases and system objects only when asked" {
        $splatSystem = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = "master"
            Pattern         = "^spt_values$"
            EnableException = $true
        }
        @(Find-DbaObject @splatSystem -IncludeSystemObjects).Count | Should -Be 0
        @(Find-DbaObject @splatSystem -IncludeSystemDatabases).Count | Should -Be 0
        $systemRows = @(Find-DbaObject @splatSystem -IncludeSystemDatabases -IncludeSystemObjects)
        $systemRows.Count | Should -Be 1
        $systemRows[0].Database | Should -BeExactly "master"
        $systemRows[0].Name | Should -BeExactly "spt_values"
    }

    It "compares -Database and -ExcludeDatabase names without regard to case" {
        @(Find-DbaObject -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName.ToUpperInvariant() -Pattern "^fdo_widgetproc$" -EnableException).Name | Should -BeExactly @("fdo_widgetproc")
        @(Find-DbaObject -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName -ExcludeDatabase $objectDbName.ToUpperInvariant() -Pattern "^fdo_widget" -EnableException).Count | Should -Be 0
    }

    It "stops on a pattern that is not a valid regular expression, as the -match statement does inside a try" {
        $patternCaught = $null
        try {
            $null = Find-DbaObject -SqlInstance $TestConfig.InstanceSingle -Database $objectDbName -Pattern "fdo_[" -EnableException
        } catch {
            $patternCaught = $PSItem
        }
        $patternCaught | Should -Not -BeNullOrEmpty
        $patternCaught.FullyQualifiedErrorId | Should -BeLike "InvalidRegularExpression*"
    }

    It "searches every piped instance" -Tag NativeChecklist:pipeline-multiple {
        $pipedRows = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaObject -Database $objectDbName -Pattern "^fdo_widgetproc$" -EnableException)
        $pipedRows.Count | Should -Be 2
        @($pipedRows.Name | Select-Object -Unique) | Should -BeExactly @("fdo_widgetproc")
    }

    It "warns for a failed instance and continues with the next one" -Tag NativeChecklist:multi-instance-failure {
        $objectWarnings = @()
        $splatContinue = @{
            SqlInstance     = @($objectBadInstance, $TestConfig.InstanceSingle)
            Database        = $objectDbName
            Pattern         = "^fdo_widgetproc$"
            WarningVariable = "objectWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $continueRows = @(Find-DbaObject @splatContinue)
        ($objectWarnings -join " ") | Should -BeLike "*Failure*"
        $continueRows.Name | Should -BeExactly @("fdo_widgetproc")
    }

    It "keeps earlier output before -EnableException stops at a failed instance" -Tag NativeChecklist:enable-exception {
        $objectStreamed = New-Object "System.Collections.Generic.List[object]"
        $objectCaught = $null
        try {
            Find-DbaObject -SqlInstance $TestConfig.InstanceSingle, $objectBadInstance -Database $objectDbName -Pattern "^fdo_widgetproc$" -EnableException |
                ForEach-Object { $objectStreamed.Add($PSItem) }
        } catch {
            $objectCaught = $PSItem
        }
        $objectStreamed.Count | Should -Be 1
        $objectCaught | Should -Not -BeNullOrEmpty
        $objectCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Find-DbaObject over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $splatLogin = @{
                SqlInstance            = $loginInstance
                SqlCredential          = $loginCred
                Database               = "master"
                Pattern                = "^spt_values$"
                IncludeSystemDatabases = $true
                IncludeSystemObjects   = $true
                EnableException        = $true
            }
            $loginRows = @(Find-DbaObject @splatLogin)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "spt_values"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $loginRows = @(Find-DbaObject -SqlInstance $loginInstance -Database master -Pattern "^spt_values$" -IncludeSystemDatabases -IncludeSystemObjects -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $loginCaught = $null
            try {
                $null = Find-DbaObject -SqlInstance $loginInstance -Database master -Pattern "^spt_values$" -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Find-DbaObject on Azure SQL Database" -Tag IntegrationTests {
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
        # Six legs share the database: a table and column of this run only.
        $azureToken = [Guid]::NewGuid().ToString("N")
        $azureTable = "fdo_$azureToken"
        $azureColumn = "fdocol_$azureToken"
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE dbo.[$azureTable] (id int NOT NULL, [$azureColumn] int NULL);")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureTable]') IS NOT NULL DROP TABLE dbo.[$azureTable];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "finds the table and its column in the database" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureRows = @(Find-DbaObject -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -Pattern $azureToken -ObjectType Table -IncludeColumns -EnableException)
        $azureRows.Count | Should -Be 2
        $azureObject = @($azureRows | Where-Object MatchType -eq "ObjectName")
        $azureObject.Count | Should -Be 1
        $azureObject[0].Name | Should -BeExactly $azureTable
        $azureObject[0].Schema | Should -BeExactly "dbo"
        $azureObject[0].ObjectType | Should -BeExactly "USER_TABLE"
        $azureObject[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        # Azure SQL Database has no SQL Server service; the instance is the logical server.
        $azureObject[0].SqlInstance | Should -Not -BeNullOrEmpty
        $azureObject[0].SqlInstance | Should -BeExactly $azureServer.SqlInstance
        $azureColumnRow = @($azureRows | Where-Object MatchType -eq "ColumnName")
        $azureColumnRow.Count | Should -Be 1
        $azureColumnRow[0].ColumnName | Should -BeExactly $azureColumn
        $azureColumnRow[0].Name | Should -BeExactly $azureTable
    }
}
