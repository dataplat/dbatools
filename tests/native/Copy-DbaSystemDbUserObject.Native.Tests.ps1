#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaSystemDbUserObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; the Destination array is covered below.
# NativeChecklist: sql-login N/A -- the pinned command has SourceSqlCredential and DestinationSqlCredential but no SqlCredential parameter.
# NativeChecklist: azure-sqldb N/A -- the command copies user objects of the master, model and msdb system databases. For Azure SQL Database only master and tempdb apply (https://learn.microsoft.com/sql/relational-databases/databases/system-databases), and creating, altering or dropping user objects such as tables, views or stored procedures in master on a logical server is not supported (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server). The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Copy-DbaSystemDbUserObject" -Tag IntegrationTests {
    BeforeAll {
        $sysSourceInstance = $TestConfig.InstanceCopy1
        $sysDestInstance = $TestConfig.InstanceCopy2
        $sysSource = Connect-DbaInstance -SqlInstance $sysSourceInstance -EnableException
        $sysDest = Connect-DbaInstance -SqlInstance $sysDestInstance -EnableException
        $sysBadInstance = "TCP:127.0.0.1,1"

        $sysSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $sysSchema = "dbatoolsci_sch_$sysSuffix"
        $sysTable = "dbatoolsci_tbl_$sysSuffix"
        $sysView = "dbatoolsci_vw_$sysSuffix"
        $sysProc = "dbatoolsci_sp_$sysSuffix"
        $sysFunction = "dbatoolsci_fn_$sysSuffix"
        $sysSpacedFunction = "dbatoolsci fn $sysSuffix"
        $sysRule = "dbatoolsci_rule_$sysSuffix"
        $sysClassicProc = "dbatoolsci_csp_$sysSuffix"
        $sysSharedProc = "dbatoolsci_shp_$sysSuffix"
        $sysSharedFunction = "dbatoolsci_shf_$sysSuffix"

        $sysCreate = @(
            "CREATE SCHEMA [$sysSchema] AUTHORIZATION [dbo]",
            "CREATE TABLE dbo.[$sysTable] (id int NOT NULL)",
            "CREATE VIEW dbo.[$sysView] AS SELECT 1 AS dbatoolsci_value",
            "CREATE PROCEDURE dbo.[$sysProc] AS SELECT 1 AS dbatoolsci_value",
            "CREATE FUNCTION dbo.[$sysFunction] () RETURNS int AS BEGIN RETURN 1 END",
            "CREATE FUNCTION dbo.[$sysSpacedFunction] () RETURNS int AS BEGIN RETURN 2 END",
            "CREATE RULE dbo.[$sysRule] AS @range >= 1000 AND @range < 20000"
        )
        $sysDrop = @(
            "IF OBJECT_ID(N'dbo.[$sysView]') IS NOT NULL DROP VIEW dbo.[$sysView]",
            "IF OBJECT_ID(N'dbo.[$sysProc]') IS NOT NULL DROP PROCEDURE dbo.[$sysProc]",
            "IF OBJECT_ID(N'dbo.[$sysClassicProc]') IS NOT NULL DROP PROCEDURE dbo.[$sysClassicProc]",
            "IF OBJECT_ID(N'dbo.[$sysFunction]') IS NOT NULL DROP FUNCTION dbo.[$sysFunction]",
            "IF OBJECT_ID(N'dbo.[$sysSpacedFunction]') IS NOT NULL DROP FUNCTION dbo.[$sysSpacedFunction]",
            "IF OBJECT_ID(N'dbo.[$sysRule]') IS NOT NULL DROP RULE dbo.[$sysRule]",
            "IF OBJECT_ID(N'dbo.[$sysTable]') IS NOT NULL DROP TABLE dbo.[$sysTable]",
            "IF OBJECT_ID(N'[$sysSchema].[$sysSharedProc]') IS NOT NULL DROP PROCEDURE [$sysSchema].[$sysSharedProc]",
            "IF OBJECT_ID(N'dbo.[$sysSharedProc]') IS NOT NULL DROP PROCEDURE dbo.[$sysSharedProc]",
            "IF OBJECT_ID(N'[$sysSchema].[$sysSharedFunction]') IS NOT NULL DROP FUNCTION [$sysSchema].[$sysSharedFunction]",
            "IF OBJECT_ID(N'dbo.[$sysSharedFunction]') IS NOT NULL DROP FUNCTION dbo.[$sysSharedFunction]",
            "IF SCHEMA_ID(N'$sysSchema') IS NOT NULL EXEC (N'DROP SCHEMA [$sysSchema]')"
        )
        foreach ($sysStatement in $sysCreate) {
            $null = Invoke-DbaQuery -SqlInstance $sysSourceInstance -Database master -Query $sysStatement -EnableException
        }

        # The copy rows of this file's objects; the copy also carries whatever else the source system databases hold.
        # The leading comma keeps a one-row result an array: Windows PowerShell 5.1 gives a lone PSCustomObject no Count.
        function Select-SysRow ($Rows) {
            , @($Rows | Where-Object { "$($PSItem.Name)" -like "*$sysSuffix*" })
        }
        function Get-SysRow ($Rows, $Name) {
            , @($Rows | Where-Object { "$($PSItem.Name)" -eq $Name })
        }
        function Test-SysObject ($Instance, $Name) {
            $sysFound = Invoke-DbaQuery -SqlInstance $Instance -Database master -Query "SELECT OBJECT_ID(@name) AS id" -SqlParameter @{ name = $Name } -EnableException
            $null -ne $sysFound.id -and $sysFound.id -isnot [DBNull]
        }
    }

    AfterAll {
        foreach ($sysCleanup in @($sysSourceInstance, $sysDestInstance)) {
            foreach ($sysStatement in $sysDrop) {
                $null = Invoke-DbaQuery -SqlInstance $sysCleanup -Database master -Query $sysStatement
            }
        }
    }

    It "honors WhatIf and changes nothing" -Tag "NativeChecklist:whatif-confirm" {
        $sysResult = Select-SysRow (Copy-DbaSystemDbUserObject -Source $sysSourceInstance -Destination $sysDestInstance -WhatIf)
        $sysResult.Count | Should -Be 0
        Test-SysObject -Instance $sysDestInstance -Name "dbo.[$sysProc]" | Should -BeFalse
        Test-SysObject -Instance $sysDestInstance -Name "dbo.[$sysTable]" | Should -BeFalse
    }

    It "copies user schemas, tables and modules from master with explicit false switches" -Tag "NativeChecklist:switch-false" {
        $splatSysCopy = @{
            Source          = $sysSourceInstance
            Destination     = $sysDestInstance
            Force           = $false
            Classic         = $false
            EnableException = $false
        }
        $sysAll = @(Copy-DbaSystemDbUserObject @splatSysCopy)
        $sysResult = Select-SysRow $sysAll
        $sysResult.Count | Should -Be 7
        $sysResult.Status | Should -Be @("Successful", "Successful", "Successful", "Successful", "Successful", "Successful", "Successful")

        $sysSchemaRow = Get-SysRow $sysAll "[$sysSchema]"
        $sysSchemaRow.Count | Should -Be 1
        $sysSchemaRow[0].Type | Should -Be "User schema in master"
        $sysSchemaRow[0].Notes | Should -Be "May have also created dependencies"
        $sysSchemaRow[0].SourceServer | Should -Be $sysSource.Name
        $sysSchemaRow[0].DestinationServer | Should -Be $sysDest.Name
        $sysSchemaRow[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"

        $sysTableRow = Get-SysRow $sysAll "[dbo].[$sysTable]"
        $sysTableRow[0].Type | Should -Be "User table in master"
        $sysTableRow[0].Notes | Should -Be "May have also created dependencies"

        (Get-SysRow $sysAll "[dbo].[$sysView]")[0].Type | Should -Be "view in master"
        (Get-SysRow $sysAll "[dbo].[$sysProc]")[0].Type | Should -Be "User stored procedure in master"
        (Get-SysRow $sysAll "[dbo].[$sysFunction]")[0].Type | Should -Be "User scalar function in master"
        (Get-SysRow $sysAll "[dbo].[$sysRule]")[0].Type | Should -Be "User rule in master"
        (Get-SysRow $sysAll "[dbo].[$sysProc]")[0].Notes | Should -BeNullOrEmpty

        foreach ($sysName in @("dbo.[$sysTable]", "dbo.[$sysView]", "dbo.[$sysProc]", "dbo.[$sysFunction]", "dbo.[$sysSpacedFunction]", "dbo.[$sysRule]")) {
            Test-SysObject -Instance $sysDestInstance -Name $sysName | Should -BeTrue -Because "$sysName was copied"
        }
        $sysDestSchema = Invoke-DbaQuery -SqlInstance $sysDestInstance -Database master -Query "SELECT SCHEMA_ID(@name) AS id" -SqlParameter @{ name = $sysSchema } -EnableException
        $sysDestSchema.id | Should -BeOfType [int]
    }

    It "skips the objects that already exist on the destination" {
        $sysResult = Select-SysRow (Copy-DbaSystemDbUserObject -Source $sysSourceInstance -Destination $sysDestInstance)
        $sysResult.Count | Should -Be 7
        $sysResult.Status | Should -Be @("Skipped", "Skipped", "Skipped", "Skipped", "Skipped", "Skipped", "Skipped")
        $sysResult.Notes | Should -Be @("Already exists on destination", "Already exists on destination", "Already exists on destination", "Already exists on destination", "Already exists on destination", "Already exists on destination", "Already exists on destination")
    }

    Context "with Force" {
        BeforeAll {
            $null = Invoke-DbaQuery -SqlInstance $sysDestInstance -Database master -Query "INSERT dbo.[$sysTable] (id) VALUES (42)" -EnableException
            $sysForceAll = @(Copy-DbaSystemDbUserObject -Source $sysSourceInstance -Destination $sysDestInstance -Force)
        }

        It "drops and recreates the objects that exist on the destination" {
            foreach ($sysName in @("[$sysSchema]", "[dbo].[$sysTable]", "[dbo].[$sysView]", "[dbo].[$sysProc]", "[dbo].[$sysFunction]", "[dbo].[$sysRule]")) {
                $sysRow = Get-SysRow $sysForceAll $sysName
                $sysRow.Count | Should -Be 1 -Because "$sysName has one row"
                $sysRow[0].Status | Should -Be "Successful" -Because "$sysName was dropped and recreated"
            }
            # The table was recreated empty from the source definition.
            $sysCount = Invoke-DbaQuery -SqlInstance $sysDestInstance -Database master -Query "SELECT COUNT(*) AS n FROM dbo.[$sysTable]" -EnableException
            $sysCount.n | Should -Be 0
        }

        It "drops and recreates a function whose name needs quoting" {
            $sysRow = Get-SysRow $sysForceAll "[dbo].[$sysSpacedFunction]"
            $sysRow.Count | Should -Be 1
            $sysRow[0].Type | Should -Be "User scalar function in master"
            $sysRow[0].Status | Should -Be "Successful"
            Test-SysObject -Instance $sysDestInstance -Name "dbo.[$sysSpacedFunction]" | Should -BeTrue
        }
    }

    It "continues the destination array after a connection failure" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $splatSysContinue = @{
            Source          = $sysSourceInstance
            Destination     = @($sysBadInstance, $sysDestInstance)
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "sysWarning"
        }
        $sysResult = Select-SysRow (Copy-DbaSystemDbUserObject @splatSysContinue)
        $sysResult.Count | Should -Be 7
        $sysResult[0].DestinationServer | Should -Be $sysDest.Name
        ($sysWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error for a failing destination when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        $sysError = $null
        try {
            $null = Copy-DbaSystemDbUserObject -Source $sysSourceInstance -Destination $sysBadInstance -EnableException
        } catch {
            $sysError = $PSItem
        }
        $sysError | Should -Not -BeNullOrEmpty
        $sysError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }

    It "warns and returns nothing when the source cannot be reached" {
        $sysResult = @(Copy-DbaSystemDbUserObject -Source $sysBadInstance -Destination $sysDestInstance -WarningAction SilentlyContinue -WarningVariable sysWarning)
        $sysResult.Count | Should -Be 0
        ($sysWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "copies with Classic and returns no output" {
        $null = Invoke-DbaQuery -SqlInstance $sysSourceInstance -Database master -Query "CREATE PROCEDURE dbo.[$sysClassicProc] AS SELECT 2 AS dbatoolsci_value" -EnableException
        $sysResult = @(Copy-DbaSystemDbUserObject -Source $sysSourceInstance -Destination $sysDestInstance -Classic)
        $sysResult.Count | Should -Be 0
        Test-SysObject -Instance $sysDestInstance -Name "dbo.[$sysClassicProc]" | Should -BeTrue
    }

    # Created after the tests above, so their row counts do not include these modules.
    Context "with modules of the same name in two schemas" {
        BeforeAll {
            $sysSharedSource = @(
                "CREATE PROCEDURE [$sysSchema].[$sysSharedProc] AS SELECT 3 AS dbatoolsci_value",
                "CREATE FUNCTION [$sysSchema].[$sysSharedFunction] () RETURNS int AS BEGIN RETURN 3 END"
            )
            $sysSharedDestination = @(
                "IF SCHEMA_ID(N'$sysSchema') IS NULL EXEC (N'CREATE SCHEMA [$sysSchema] AUTHORIZATION [dbo]')",
                "CREATE PROCEDURE dbo.[$sysSharedProc] AS SELECT 4 AS dbatoolsci_value",
                "CREATE FUNCTION dbo.[$sysSharedFunction] () RETURNS int AS BEGIN RETURN 4 END",
                "CREATE FUNCTION [$sysSchema].[$sysSharedFunction] () RETURNS int AS BEGIN RETURN 5 END"
            )
            foreach ($sysStatement in $sysSharedSource) {
                $null = Invoke-DbaQuery -SqlInstance $sysSourceInstance -Database master -Query $sysStatement -EnableException
            }
            foreach ($sysStatement in $sysSharedDestination) {
                $null = Invoke-DbaQuery -SqlInstance $sysDestInstance -Database master -Query $sysStatement -EnableException
            }
        }

        It "copies a module that exists on the destination only in another schema" {
            $sysSharedAll = @(Copy-DbaSystemDbUserObject -Source $sysSourceInstance -Destination $sysDestInstance)
            $sysSharedRow = Get-SysRow $sysSharedAll "[$sysSchema].[$sysSharedProc]"
            $sysSharedRow.Count | Should -Be 1
            $sysSharedRow[0].Status | Should -Be "Successful"
            Test-SysObject -Instance $sysDestInstance -Name "[$sysSchema].[$sysSharedProc]" | Should -BeTrue
            Test-SysObject -Instance $sysDestInstance -Name "dbo.[$sysSharedProc]" | Should -BeTrue
        }

        It "drops and recreates a function with Force without touching the same name in another schema" {
            $sysSharedForce = @(Copy-DbaSystemDbUserObject -Source $sysSourceInstance -Destination $sysDestInstance -Force)
            $sysSharedRow = Get-SysRow $sysSharedForce "[$sysSchema].[$sysSharedFunction]"
            $sysSharedRow.Count | Should -Be 1
            $sysSharedRow[0].Status | Should -Be "Successful"
            $sysSharedValues = Invoke-DbaQuery -SqlInstance $sysDestInstance -Database master -Query "SELECT dbo.[$sysSharedFunction]() AS dboValue, [$sysSchema].[$sysSharedFunction]() AS schemaValue" -EnableException
            $sysSharedValues.dboValue | Should -Be 4
            $sysSharedValues.schemaValue | Should -Be 3
        }
    }
}

Describe "Native Copy-DbaSystemDbUserObject refuses Azure SQL Database" -Tag IntegrationTests {
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
        $azureDestInstance = $TestConfig.InstanceCopy2
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            Source          = $azureServer
            Destination     = $azureDestInstance
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Copy-DbaSystemDbUserObject @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaSystemDbUserObject -Source $azureServer -Destination $azureDestInstance -EnableException -ErrorAction SilentlyContinue
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}
