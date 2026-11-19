#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Find-DbaTrigger" -Tag IntegrationTests {
    BeforeAll {
        $trgBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        # Names and a marker of this run only. The trigger bodies hold the marker in a comment, so they return nothing.
        $trgGuid = [Guid]::NewGuid().ToString("N")
        $trgToken = "ntrgmark$trgGuid"
        $trgDb = "nativetrg_$trgGuid"
        $trgServerTrigger = "ntr_srv_$trgGuid"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $trgDb -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Query "CREATE TABLE dbo.ntr_table (id int NOT NULL);" -EnableException
        # CR LF line ends for the table trigger, LF line ends for the database trigger.
        $trgDmlText = @("CREATE TRIGGER dbo.ntr_dml ON dbo.ntr_table AFTER INSERT", "AS", "SET NOCOUNT ON;", "-- $trgToken object level") -join "`r`n"
        $trgDdlText = @("CREATE TRIGGER ntr_ddl ON DATABASE FOR DROP_SYNONYM", "AS", "SET NOCOUNT ON;", "-- $trgToken database level") -join "`n"
        $trgServerText = @("CREATE TRIGGER [$trgServerTrigger] ON ALL SERVER FOR CREATE_DATABASE", "AS", "SET NOCOUNT ON;", "-- $trgToken server level") -join "`r`n"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Query $trgDmlText -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Query $trgDdlText -EnableException
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $trgServerText -EnableException
        $trgServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $trgDbId = $trgServer.Databases[$trgDb].ID
    }

    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "IF EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'$trgServerTrigger') DROP TRIGGER [$trgServerTrigger] ON ALL SERVER;"
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Confirm:$false
    }

    It "returns database and object triggers with the source's properties and default view" {
        $trgRows = @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Pattern $trgToken -EnableException)
        $trgRows.Count | Should -Be 2
        @($trgRows[0].PSObject.Properties.Name) | Should -BeExactly @("ComputerName", "SqlInstance", "TriggerLevel", "Database", "DatabaseId", "Object", "Name", "IsSystemObject", "CreateDate", "LastModified", "TriggerTextFound", "Trigger", "TriggerFullText")
        $trgDdlRow = @($trgRows | Where-Object TriggerLevel -eq "Database")
        $trgDdlRow.Count | Should -Be 1
        $trgDdlRow[0].Name | Should -BeExactly "ntr_ddl"
        $trgDdlRow[0].Database | Should -BeExactly $trgDb
        $trgDdlRow[0].DatabaseId | Should -Be $trgDbId
        $trgDdlRow[0].Object.Name | Should -BeExactly $trgDb
        $trgDdlRow[0].Trigger | Should -BeOfType Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger
        $trgDmlRow = @($trgRows | Where-Object TriggerLevel -eq "Object")
        $trgDmlRow.Count | Should -Be 1
        $trgDmlRow[0].Name | Should -BeExactly "ntr_dml"
        [string]$trgDmlRow[0].Object | Should -BeExactly "[dbo].[ntr_table]"
        $trgDmlRow[0].IsSystemObject | Should -BeFalse
        $trgDmlRow[0].CreateDate | Should -BeOfType System.DateTime
        $trgDmlRow[0].LastModified | Should -BeOfType System.DateTime
        $trgDmlRow[0].Trigger | Should -BeOfType Microsoft.SqlServer.Management.Smo.Trigger
        foreach ($trgRow in $trgRows) {
            $trgRow.SqlInstance | Should -BeExactly $trgServer.ServiceName
            $trgRow.TriggerFullText | Should -BeLike "*$trgToken*"
            $trgDisplay = @($trgRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            $trgDisplay | Should -Not -Contain "Trigger"
            $trgDisplay | Should -Not -Contain "TriggerFullText"
            $trgDisplay.Count | Should -Be 11
        }
    }

    It "returns a server trigger without database properties" {
        $serverRows = @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Pattern $trgToken -TriggerLevel Server -EnableException)
        $serverRows.Count | Should -Be 1
        $serverRows[0].TriggerLevel | Should -BeExactly "Server"
        $serverRows[0].Name | Should -BeExactly $trgServerTrigger
        $serverRows[0].Database | Should -BeNullOrEmpty
        $serverRows[0].DatabaseId | Should -BeNullOrEmpty
        $serverRows[0].Object | Should -BeNullOrEmpty
        $serverRows[0].Trigger | Should -BeOfType Microsoft.SqlServer.Management.Smo.ServerDdlTrigger
        $serverRows[0].TriggerTextFound | Should -BeLike "*$trgToken server level"
    }

    It "reports the line numbers of matched trigger lines" {
        $lineRows = @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Pattern $trgToken -EnableException)
        $lineRows.Count | Should -Be 2
        foreach ($lineRow in $lineRows) {
            # The real line numbers of the reported text, whatever its line ends.
            $lineParts = [string]$lineRow.TriggerFullText -split "\r\n|\r|\n"
            $lineExpected = @(for ($lineIndex = 0; $lineIndex -lt $lineParts.Count; $lineIndex++) {
                    if ($lineParts[$lineIndex] -match $trgToken) { "(LineNumber: $($lineIndex + 1)) $($lineParts[$lineIndex].Trim())" }
                })
            $lineExpected.Count | Should -Be 1
            $lineRow.TriggerTextFound | Should -BeExactly $lineExpected[0]
        }
    }

    It "counts the triggers it evaluated in its verbose messages" {
        $dbStreams = @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Pattern $trgToken -Verbose 4>&1)
        $dbCounts = @($dbStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message.Contains("triggers in [$trgDb]") } | ForEach-Object { [int]([regex]::Match($PSItem.Message, "Evaluated (\d+) triggers in").Groups[1].Value) })
        $dbCounts.Count | Should -Be 1
        $dbCounts[0] | Should -Be 2
        $serverStreams = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaTrigger -Pattern $trgToken -TriggerLevel Server -Verbose 4>&1)
        $serverCounts = @($serverStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -match "Evaluated \d+ triggers in \[" } | ForEach-Object { [int]([regex]::Match($PSItem.Message, "Evaluated (\d+) triggers in").Groups[1].Value) })
        $serverCounts.Count | Should -Be 2
        $serverCounts[0] | Should -BeGreaterOrEqual 1
        $serverCounts[1] | Should -Be $serverCounts[0]
    }

    It "treats the two switches set to `$false as not given" -Tag NativeChecklist:switch-false {
        $splatSwitches = @{
            SqlInstance            = $TestConfig.InstanceSingle
            Database               = $trgDb
            Pattern                = $trgToken
            IncludeSystemObjects   = $false
            IncludeSystemDatabases = $false
            EnableException        = $true
        }
        @(Find-DbaTrigger @splatSwitches | Sort-Object Name).Name | Should -BeExactly @("ntr_ddl", "ntr_dml")
    }

    It "finds the same triggers through SMO with -IncludeSystemObjects" {
        $smoRows = @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Pattern $trgToken -IncludeSystemObjects -EnableException | Sort-Object Name)
        @($smoRows.Name) | Should -BeExactly @("ntr_ddl", "ntr_dml")
        @($smoRows.TriggerLevel) | Should -BeExactly @("Database", "Object")
    }

    It "limits the search to the trigger level asked for and skips the server level when -Database is given" {
        @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Pattern $trgToken -TriggerLevel Database -EnableException).Name | Should -BeExactly @("ntr_ddl")
        @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Pattern $trgToken -TriggerLevel Object -EnableException).Name | Should -BeExactly @("ntr_dml")
        @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -Pattern $trgToken -TriggerLevel Server -EnableException).Count | Should -Be 0
        @(Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle -Database $trgDb -ExcludeDatabase $trgDb.ToUpperInvariant() -Pattern $trgToken -EnableException).Count | Should -Be 0
    }

    It "stops in a caller's try at a pattern that is not a valid regular expression, with the pinned -match statement's error" {
        $trgBadPattern = "$($trgToken)_["
        # The pinned statement's own failure on this edition: if (... -match $Pattern) inside an advanced function, in a try.
        function Test-TrgMatchOracle {
            [CmdletBinding()]
            param ($Pattern)
            process {
                if ("x" -match $Pattern) {
                    "matched"
                }
            }
        }
        $trgExpected = $null
        try {
            $null = Test-TrgMatchOracle -Pattern $trgBadPattern
        } catch {
            $trgExpected = $PSItem
        }
        $trgExpected | Should -Not -BeNullOrEmpty
        $splatServerLevel = @{
            SqlInstance  = $TestConfig.InstanceSingle
            TriggerLevel = "Server"
            Pattern      = $trgBadPattern
        }
        $splatDatabaseLevel = @{
            SqlInstance  = $TestConfig.InstanceSingle
            Database     = $trgDb
            TriggerLevel = "Database"
            Pattern      = $trgBadPattern
        }
        foreach ($trgSplat in @($splatServerLevel, $splatDatabaseLevel)) {
            $trgRows = New-Object "System.Collections.Generic.List[object]"
            $trgCaught = $null
            $trgAfter = $false
            try {
                Find-DbaTrigger @trgSplat | ForEach-Object { $trgRows.Add($PSItem) }
                $trgAfter = $true
            } catch {
                $trgCaught = $PSItem
            }
            $trgAfter | Should -BeFalse -Because "the $($trgSplat.TriggerLevel) level must not go on past the fault in a caller's try"
            $trgRows.Count | Should -Be 0
            $trgCaught | Should -Not -BeNullOrEmpty
            $trgCaught.Exception.GetType().FullName | Should -BeExactly $trgExpected.Exception.GetType().FullName
            $trgCaught.Exception.Message | Should -BeExactly $trgExpected.Exception.Message
            $trgCaught.CategoryInfo.Category | Should -Be $trgExpected.CategoryInfo.Category
            $trgCaught.FullyQualifiedErrorId.Split(",")[0] | Should -BeExactly $trgExpected.FullyQualifiedErrorId.Split(",")[0]
            $trgCaught.TargetObject | Should -BeNullOrEmpty
        }
    }

    It "searches every piped instance" -Tag NativeChecklist:pipeline-multiple {
        $pipedRows = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaTrigger -Database $trgDb -Pattern $trgToken -TriggerLevel Object -EnableException)
        $pipedRows.Count | Should -Be 2
        @($pipedRows.Name | Select-Object -Unique) | Should -BeExactly @("ntr_dml")
    }

    It "warns for a failed instance and continues with the next one" -Tag NativeChecklist:multi-instance-failure {
        $trgWarnings = @()
        $splatContinue = @{
            SqlInstance     = @($trgBadInstance, $TestConfig.InstanceSingle)
            Database        = $trgDb
            Pattern         = $trgToken
            TriggerLevel    = "Object"
            WarningVariable = "trgWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $continueRows = @(Find-DbaTrigger @splatContinue)
        ($trgWarnings -join " ") | Should -BeLike "*Failure*"
        $continueRows.Name | Should -BeExactly @("ntr_dml")
    }

    It "keeps earlier output before -EnableException stops at a failed instance" -Tag NativeChecklist:enable-exception {
        $trgStreamed = New-Object "System.Collections.Generic.List[object]"
        $trgCaught = $null
        try {
            Find-DbaTrigger -SqlInstance $TestConfig.InstanceSingle, $trgBadInstance -Database $trgDb -Pattern $trgToken -TriggerLevel Object -EnableException |
                ForEach-Object { $trgStreamed.Add($PSItem) }
        } catch {
            $trgCaught = $PSItem
        }
        $trgStreamed.Count | Should -Be 1
        $trgCaught | Should -Not -BeNullOrEmpty
        $trgCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Find-DbaTrigger over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginGuid = [Guid]::NewGuid().ToString("N")
            $loginToken = "ntrglogin$loginGuid"
            $loginDbName = "nativetrglogin_$loginGuid"
            $null = New-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Name $loginDbName -EnableException
            $null = Invoke-DbaQuery -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Query "CREATE TABLE dbo.ntr_login (id int NOT NULL);" -EnableException
            $null = Invoke-DbaQuery -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Query "CREATE TRIGGER dbo.ntr_login_dml ON dbo.ntr_login AFTER INSERT AS SET NOCOUNT ON; -- $loginToken" -EnableException
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Confirm:$false
        }

        It "works with -SqlCredential" {
            $loginRows = @(Find-DbaTrigger -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Pattern $loginToken -EnableException)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "ntr_login_dml"
            $loginRows[0].Database | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $loginRows = @(Find-DbaTrigger -SqlInstance $loginInstance -Database $loginDbName -Pattern $loginToken -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $loginCaught = $null
            try {
                $null = Find-DbaTrigger -SqlInstance $loginInstance -Database $loginDbName -Pattern $loginToken -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Find-DbaTrigger on Azure SQL Database" -Tag IntegrationTests {
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
        # Six legs share the database: a table and triggers of this run only.
        $azureToken = [Guid]::NewGuid().ToString("N")
        $azureTable = "ntr_$azureToken"
        $azureDml = "ntrdml_$azureToken"
        $azureDdl = "ntrddl_$azureToken"
        $azureMark = "ntrgazure$azureToken"
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE dbo.[$azureTable] (id int NOT NULL);")
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TRIGGER dbo.[$azureDml] ON dbo.[$azureTable] AFTER INSERT AS SET NOCOUNT ON; -- $azureMark")
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TRIGGER [$azureDdl] ON DATABASE FOR DROP_SYNONYM AS SET NOCOUNT ON; -- $azureMark")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_class = 0 AND name = N'$azureDdl') DROP TRIGGER [$azureDdl] ON DATABASE;")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureTable]') IS NOT NULL DROP TABLE dbo.[$azureTable];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "finds the database and object triggers and reports the logical server as SqlInstance" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureRows = @(Find-DbaTrigger -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -Pattern $azureMark -EnableException | Sort-Object TriggerLevel)
        $azureRows.Count | Should -Be 2
        @($azureRows.TriggerLevel) | Should -BeExactly @("Database", "Object")
        $azureRows[0].Name | Should -BeExactly $azureDdl
        $azureRows[1].Name | Should -BeExactly $azureDml
        foreach ($azureRow in $azureRows) {
            $azureRow.Database | Should -BeExactly $TestConfig.AzureSqlDbName
            # Azure SQL Database has no SQL Server service; the instance is the logical server.
            $azureRow.SqlInstance | Should -Not -BeNullOrEmpty
            $azureRow.SqlInstance | Should -BeExactly $azureServer.SqlInstance
        }
    }
}
