#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPbmStore",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the policy store.
# NativeChecklist: platform windows-only -- windows-smo: the DMF PolicyStore that Add-PbmLibrary loads; off Windows the command refuses, as the pin does.

Describe "Native Get-DbaPbmStore" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        # The connect warning names the target as DbaInstanceParameter shows it, TCP:127.0.0.1,1 for this connection string.
        # A warning record's message starts with its time, "[18:35:37][Get-DbaPbmStore] ...", so the line is not anchored.
        $badLine = "\[Get-DbaPbmStore\] Failure \| Error connecting to \[[^\]]*127\.0\.0\.1,1\]: "
        $excludedView = @("SqlStoreConnection", "ConnectionContext", "Properties", "Urn", "Parent", "DomainInstanceName", "Metadata", "IdentityKey", "Name")
    }

    Context "Output" {
        It "returns the DMF store of the instance with the instance columns" {
            $store = Get-DbaPbmStore -SqlInstance $instance -EnableException
            $store.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Dmf.PolicyStore"
            $store.ComputerName | Should -Be $server.ComputerName
            $store.InstanceName | Should -Be $server.ServiceName
            $store.SqlInstance | Should -Be $server.DomainInstanceName
        }

        It "reads the instance's policy categories through the store, as msdb lists them" {
            $store = Get-DbaPbmStore -SqlInstance $instance -EnableException
            $expected = @($server.Query("SELECT name FROM msdb.dbo.syspolicy_policy_categories;") | ForEach-Object { $PSItem.name } | Sort-Object)
            @($store.PolicyCategories | ForEach-Object Name | Sort-Object) | Should -Be $expected
        }

        It "shows every property but the pin's excluded ones by default" {
            $store = Get-DbaPbmStore -SqlInstance $instance -EnableException
            $view = @($store.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            foreach ($name in "ComputerName", "InstanceName", "SqlInstance", "Policies", "Conditions") {
                $view | Should -Contain $name
            }
            foreach ($name in $excludedView) {
                $view | Should -Not -Contain $name
            }
        }
    }

    Context "Pipeline" {
        It "takes several instances from the pipeline, one store each in order" -Tag "NativeChecklist:pipeline-multiple" {
            $copyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
            $results = @($instance, $TestConfig.InstanceCopy1 | Get-DbaPbmStore -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $server.DomainInstanceName
            $results[1].SqlInstance | Should -Be $copyServer.DomainInstanceName
        }
    }

    Context "Failed instances" {
        It "warns of a failed instance and returns the others" -Tag "NativeChecklist:multi-instance-failure" {
            $failedWarnings = @()
            $splatFailed = @{
                SqlInstance     = $badInstance, $instance
                WarningVariable = "failedWarnings"
                WarningAction   = "SilentlyContinue"
                ErrorVariable   = "failedErrors"
                ErrorAction     = "SilentlyContinue"
            }
            $results = @(Get-DbaPbmStore @splatFailed)
            $results.Count | Should -Be 1
            $results[0].SqlInstance | Should -Be $server.DomainInstanceName
            # One line naming the failed server (harness-edits.md, "Script-scope preferences and the one-line connect warning", point 5).
            @($failedWarnings).Count | Should -Be 1
            "$($failedWarnings[0])" | Should -Match $badLine
            $failedErrors.Count | Should -Be 1
            $failedErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
            $failedErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "throws for a failed instance under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $enableWarnings = $null
            try {
                $null = Get-DbaPbmStore -SqlInstance $badInstance, $instance -EnableException -OutVariable collected -WarningVariable enableWarnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            @($enableWarnings).Count | Should -Be 1
            "$($enableWarnings[0])" | Should -Match $badLine
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaPbmStore*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            # The line names the server; the caught record stays the server's own message.
            $caught.Exception.Message | Should -Not -BeLike "*Error connecting to*"
            @($collected).Count | Should -Be 0
        }

        It "only warns under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $results = @(Get-DbaPbmStore -SqlInstance $badInstance -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($falseWarnings).Count | Should -Be 1
            "$($falseWarnings[0])" | Should -Match $badLine
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaPbmStore -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $results.Count | Should -Be 1
            $results[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
            $null = @($results[0].PolicyCategories).Count
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = @(Get-DbaPbmStore -SqlInstance $loginInstance -WarningVariable loginWarnings -WarningAction SilentlyContinue -ErrorVariable loginErrors -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($loginWarnings).Count | Should -Be 1
            "$($loginWarnings[0])" | Should -Match ("\[Get-DbaPbmStore\] Failure \| Error connecting to \[" + [regex]::Escape("$loginInstance") + "\]: Login failed")
            $loginErrors.Count | Should -Be 1
            $loginErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
            $loginErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "throws without the credential under -EnableException, as the pinned function does" {
            { Get-DbaPbmStore -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaPbmStore*"
        }
    }
}

Describe "Native Get-DbaPbmStore refuses Azure SQL Database" -Tag IntegrationTests {
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

    # Policy-Based Management applies to SQL Server only and keeps its store in msdb (Microsoft Learn, "syspolicy_policies":
    # Applies to SQL Server), and Azure SQL Database has no msdb (Microsoft Learn, "msdb database": SQL Server and Azure SQL
    # Managed Instance). The pin's behaviour there is measured by the item's declared red.
    It "refuses Azure SQL Database with a warning and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
            ErrorVariable   = "azureErrors"
        }
        @(Get-DbaPbmStore @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Failure*Azure SQL Database not supported*"
        $azureErrors.Count | Should -Be 1
        $azureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
        $azureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        $azureErrors[0].Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses Azure SQL Database under -EnableException by throwing that refusal" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        { Get-DbaPbmStore -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Azure SQL Database not supported*"
    }
}
