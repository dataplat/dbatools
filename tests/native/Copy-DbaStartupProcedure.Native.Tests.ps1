#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaStartupProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; the Destination array is covered below.
# NativeChecklist: sql-login N/A -- the pinned command has SourceSqlCredential and DestinationSqlCredential but no SqlCredential parameter.
# NativeChecklist: azure-sqldb N/A -- startup procedures live in the master database of SQL Server and are set with sp_procoption, which applies to SQL Server only (https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-procoption-transact-sql); Azure SQL Database runs no startup procedures. The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Copy-DbaStartupProcedure" -Tag IntegrationTests {
    BeforeAll {
        $startSourceInstance = $TestConfig.InstanceCopy1
        $startDestInstance = $TestConfig.InstanceCopy2
        $startSource = Connect-DbaInstance -SqlInstance $startSourceInstance -EnableException
        $startDest = Connect-DbaInstance -SqlInstance $startDestInstance -EnableException
        $startBadInstance = "TCP:127.0.0.1,1"

        $startSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $startPlain = "dbatoolsci_startplain_$startSuffix"
        $startQuote = "dbatoolsci_start]'q_$startSuffix"
        $startNotStartup = "dbatoolsci_startno_$startSuffix"
        $startNames = @($startPlain, $startQuote, $startNotStartup)

        function Get-StartQuoted ($Name) {
            "[dbo].[" + $Name.Replace("]", "]]") + "]"
        }
        function Get-StartFlag ($Instance, $Name) {
            $splatFlag = @{
                SqlInstance     = $Instance
                Database        = "master"
                Query           = "SELECT OBJECTPROPERTY(OBJECT_ID(N'dbo.' + QUOTENAME(@name)), 'ExecIsStartup') AS flag"
                SqlParameter    = @{ name = $Name }
                EnableException = $true
            }
            $startFlag = (Invoke-DbaQuery @splatFlag).flag
            if ($startFlag -is [DBNull]) { $null } else { $startFlag }
        }

        foreach ($startName in $startNames) {
            $startQuoted = Get-StartQuoted -Name $startName
            $null = $startSource.Databases["master"].ExecuteNonQuery("CREATE PROCEDURE $startQuoted AS SELECT 1;")
        }
        foreach ($startName in @($startPlain, $startQuote)) {
            $startLiteral = (Get-StartQuoted -Name $startName).Replace("'", "''")
            $null = $startSource.Databases["master"].ExecuteNonQuery("EXEC sp_procoption @ProcName = N'$startLiteral', @OptionName = 'startup', @OptionValue = 'on';")
        }
    }

    AfterAll {
        foreach ($startServer in @($startSource, $startDest)) {
            foreach ($startName in $startNames) {
                $startLiteral = (Get-StartQuoted -Name $startName).Replace("'", "''")
                $null = $startServer.Databases["master"].ExecuteNonQuery("IF OBJECT_ID(N'$startLiteral') IS NOT NULL DROP PROCEDURE $(Get-StartQuoted -Name $startName);")
            }
        }
    }

    It "copies a startup procedure with explicit false switches" -Tag "NativeChecklist:switch-false" {
        $splatStartCopy = @{
            Source          = $startSourceInstance
            Destination     = $startDestInstance
            Procedure       = $startPlain
            Force           = $false
            EnableException = $false
        }
        $startResult = @(Copy-DbaStartupProcedure @splatStartCopy)
        $startResult.Count | Should -Be 1
        $startResult[0].Name | Should -Be $startPlain
        $startResult[0].Schema | Should -Be "dbo"
        $startResult[0].Type | Should -Be "Startup Stored Procedure"
        $startResult[0].Status | Should -Be "Successful"
        $startResult[0].SourceServer | Should -Be $startSource.Name
        $startResult[0].DestinationServer | Should -Be $startDest.Name
        $startResult[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        Get-StartFlag -Instance $startDestInstance -Name $startPlain | Should -Be 1
    }

    It "skips a procedure that already exists on the destination" {
        $startResult = @(Copy-DbaStartupProcedure -Source $startSourceInstance -Destination $startDestInstance -Procedure $startPlain)
        $startResult.Count | Should -Be 1
        $startResult[0].Status | Should -Be "Skipped"
        $startResult[0].Notes | Should -Be "Already exists on destination"
    }

    It "honors WhatIf with Force" -Tag "NativeChecklist:whatif-confirm" {
        $startResult = @(Copy-DbaStartupProcedure -Source $startSourceInstance -Destination $startDestInstance -Procedure $startPlain, $startQuote -Force -WhatIf)
        $startResult.Count | Should -Be 0
        Get-StartFlag -Instance $startDestInstance -Name $startPlain | Should -Be 1
        Get-StartFlag -Instance $startDestInstance -Name $startQuote | Should -BeNullOrEmpty
    }

    It "continues the destination array after a connection failure" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $splatStartContinue = @{
            Source          = $startSourceInstance
            Destination     = @($startBadInstance, $startDestInstance)
            Procedure       = $startPlain
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "startWarning"
        }
        $startResult = @(Copy-DbaStartupProcedure @splatStartContinue)
        $startResult.Count | Should -Be 1
        $startResult[0].Status | Should -Be "Skipped"
        $startResult[0].DestinationServer | Should -Be $startDest.Name
        ($startWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error for a failing destination when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        $startError = $null
        try {
            $null = Copy-DbaStartupProcedure -Source $startSourceInstance -Destination $startBadInstance -Procedure $startPlain -EnableException
        } catch {
            $startError = $PSItem
        }
        $startError | Should -Not -BeNullOrEmpty
        $startError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }

    It "copies only procedures marked to run at startup" {
        $startResult = @(Copy-DbaStartupProcedure -Source $startSourceInstance -Destination $startDestInstance -Procedure $startNotStartup)
        $startResult.Count | Should -Be 0
        Get-StartFlag -Instance $startDestInstance -Name $startNotStartup | Should -BeNullOrEmpty
    }

    It "applies ExcludeProcedure after Procedure" {
        $startResult = @(Copy-DbaStartupProcedure -Source $startSourceInstance -Destination $startDestInstance -Procedure $startQuote -ExcludeProcedure $startQuote.ToUpperInvariant())
        $startResult.Count | Should -Be 0
        Get-StartFlag -Instance $startDestInstance -Name $startQuote | Should -BeNullOrEmpty
    }

    It "copies and replaces a startup procedure whose name holds a quote and a bracket" {
        $startResult = @(Copy-DbaStartupProcedure -Source $startSourceInstance -Destination $startDestInstance -Procedure $startQuote)
        $startResult.Count | Should -Be 1
        $startResult[0].Name | Should -Be $startQuote
        $startResult[0].Status | Should -Be "Successful"
        Get-StartFlag -Instance $startDestInstance -Name $startQuote | Should -Be 1

        $startForce = @(Copy-DbaStartupProcedure -Source $startSourceInstance -Destination $startDestInstance -Procedure $startQuote -Force)
        $startForce.Count | Should -Be 1
        $startForce[0].Status | Should -Be "Successful"
        Get-StartFlag -Instance $startDestInstance -Name $startQuote | Should -Be 1
    }
}

Describe "Native Copy-DbaStartupProcedure refuses Azure SQL Database" -Tag IntegrationTests {
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
        $azureProcedure = "dbatoolsci_startazure_$([guid]::NewGuid().ToString("N").Substring(0, 12))"
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            Source          = $azureServer
            Destination     = $azureDestInstance
            Procedure       = $azureProcedure
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Copy-DbaStartupProcedure @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaStartupProcedure -Source $azureServer -Destination $azureDestInstance -Procedure $azureProcedure -EnableException -ErrorAction SilentlyContinue
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}
