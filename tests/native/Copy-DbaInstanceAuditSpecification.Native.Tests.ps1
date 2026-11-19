#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaInstanceAuditSpecification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter takes pipeline input; several destinations are covered by the multi-instance tests.
# NativeChecklist: azure-sqldb N/A -- server audit specifications exist only in SQL Server and Azure SQL Managed Instance (https://learn.microsoft.com/sql/t-sql/statements/create-server-audit-specification-transact-sql); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Copy-DbaInstanceAuditSpecification" -Tag IntegrationTests {
    BeforeAll {
        $nativeSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $nativeDest = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $nativeBadInstance = "TCP:127.0.0.1,1"
        $nativeSuffix = [Guid]::NewGuid().ToString("N")
        # Audit A exists on both instances, audit B only on the source. The audits are never enabled.
        $nativeAuditA = "native_auditspec_a_$nativeSuffix"
        $nativeAuditB = "native_auditspec_b_$nativeSuffix"
        $nativeSpecA = "native_auditspec_sa_$nativeSuffix"
        $nativeSpecB = "native_auditspec_sb_$nativeSuffix"
        foreach ($nativeServer in @($nativeSource, $nativeDest)) {
            $null = $nativeServer.Query("CREATE SERVER AUDIT [$nativeAuditA] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")
        }
        $null = $nativeSource.Query("CREATE SERVER AUDIT [$nativeAuditB] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")
        $null = $nativeSource.Query("CREATE SERVER AUDIT SPECIFICATION [$nativeSpecA] FOR SERVER AUDIT [$nativeAuditA] ADD (FAILED_LOGIN_GROUP)")
        $null = $nativeSource.Query("CREATE SERVER AUDIT SPECIFICATION [$nativeSpecB] FOR SERVER AUDIT [$nativeAuditB] ADD (FAILED_LOGIN_GROUP)")

        $nativeDestSpecExists = {
            param($Name)
            $nativeDest.ServerAuditSpecifications.Refresh()
            $null -ne $nativeDest.ServerAuditSpecifications[$Name]
        }
    }

    AfterAll {
        $nativeCleanup = @"
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'$nativeSpecA') DROP SERVER AUDIT SPECIFICATION [$nativeSpecA];
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'$nativeSpecB') DROP SERVER AUDIT SPECIFICATION [$nativeSpecB];
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$nativeAuditA') DROP SERVER AUDIT [$nativeAuditA];
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$nativeAuditB') DROP SERVER AUDIT [$nativeAuditB];
"@
        foreach ($nativeServer in @($nativeSource, $nativeDest)) {
            if ($nativeServer) {
                $null = $nativeServer.Query($nativeCleanup)
            }
        }
    }

    It "copies only the named specification, matched case-insensitively, as a MigrationObject" {
        $splatCopy = @{
            Source             = $TestConfig.InstanceCopy1
            Destination        = $TestConfig.InstanceCopy2
            AuditSpecification = $nativeSpecA.ToUpperInvariant()
            EnableException    = $true
        }
        $result = @(Copy-DbaInstanceAuditSpecification @splatCopy)
        $result.Count | Should -Be 1
        $result[0].Name | Should -BeExactly $nativeSpecA
        $result[0].Type | Should -BeExactly "Server Audit Specification"
        $result[0].Status | Should -BeExactly "Successful"
        $result[0].Notes | Should -BeNullOrEmpty
        $result[0].SourceServer | Should -Be $nativeSource.Name
        $result[0].DestinationServer | Should -Be $nativeDest.Name
        $result[0].DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        $result[0].PSObject.TypeNames[0] | Should -BeExactly "dbatools.MigrationObject"
        ($result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "DateTime,SourceServer,DestinationServer,Name,Type,Status,Notes"
        ($result[0].PSObject.Properties.Name -join ",") | Should -BeExactly "SourceServer,DestinationServer,Type,Name,Status,Notes,DateTime"
        & $nativeDestSpecExists $nativeSpecA | Should -Be $true
        $nativeDest.ServerAuditSpecifications[$nativeSpecA].AuditName | Should -BeExactly $nativeAuditA
    }

    It "skips with a warning a specification whose audit is missing on the destination" {
        $nativeWarnings = @()
        $splatMissing = @{
            Source             = $TestConfig.InstanceCopy1
            Destination        = $TestConfig.InstanceCopy2
            AuditSpecification = $nativeSpecB
            WarningVariable    = "nativeWarnings"
            WarningAction      = "SilentlyContinue"
        }
        $result = @(Copy-DbaInstanceAuditSpecification @splatMissing)
        $result.Count | Should -Be 1
        $result[0].Status | Should -BeExactly "Skipped"
        $result[0].Notes | Should -BeLike "Audit $nativeAuditB does not exist on *. Skipping $nativeSpecB."
        ($nativeWarnings -join " ") | Should -BeLike "*Audit $nativeAuditB does not exist on*"
        & $nativeDestSpecExists $nativeSpecB | Should -Be $false
    }

    It "excludes a specification and skips one that already exists without -Force" -Tag "NativeChecklist:switch-false" {
        $splatExisting = @{
            Source                    = $TestConfig.InstanceCopy1
            Destination               = $TestConfig.InstanceCopy2
            AuditSpecification        = @($nativeSpecA, $nativeSpecB)
            ExcludeAuditSpecification = $nativeSpecB
            Force                     = $false
            EnableException           = $true
        }
        $result = @(Copy-DbaInstanceAuditSpecification @splatExisting)
        $result.Count | Should -Be 1
        $result[0].Name | Should -BeExactly $nativeSpecA
        $result[0].Status | Should -BeExactly "Skipped"
        $result[0].Notes | Should -BeExactly "Already exists on destination"
    }

    It "drops and recreates an existing specification with -Force" {
        $splatForce = @{
            Source             = $TestConfig.InstanceCopy1
            Destination        = $TestConfig.InstanceCopy2
            AuditSpecification = $nativeSpecA
            Force              = $true
            EnableException    = $true
        }
        $result = @(Copy-DbaInstanceAuditSpecification @splatForce)
        $result.Count | Should -Be 1
        $result[0].Status | Should -BeExactly "Successful"
        $nativeDest.ServerAuditSpecifications.Refresh()
        $nativeDest.ServerAuditSpecifications[$nativeSpecA] | Should -Not -BeNullOrEmpty
    }

    It "changes nothing and returns nothing under -WhatIf, and copies with -Confirm:`$false" -Tag "NativeChecklist:whatif-confirm" {
        $null = $nativeDest.Query("DROP SERVER AUDIT SPECIFICATION [$nativeSpecA]")
        $splatWhatIf = @{
            Source             = $TestConfig.InstanceCopy1
            Destination        = $TestConfig.InstanceCopy2
            AuditSpecification = $nativeSpecA
            WhatIf             = $true
            EnableException    = $true
        }
        @(Copy-DbaInstanceAuditSpecification @splatWhatIf).Count | Should -Be 0
        & $nativeDestSpecExists $nativeSpecA | Should -Be $false

        $splatConfirm = @{
            Source             = $TestConfig.InstanceCopy1
            Destination        = $TestConfig.InstanceCopy2
            AuditSpecification = $nativeSpecA
            Confirm            = $false
            EnableException    = $true
        }
        $result = @(Copy-DbaInstanceAuditSpecification @splatConfirm)
        $result[0].Status | Should -BeExactly "Successful"
        & $nativeDestSpecExists $nativeSpecA | Should -Be $true
    }

    It "warns for a failed destination and continues with the next one" -Tag "NativeChecklist:multi-instance-failure" {
        $nativeWarnings = @()
        $splatContinue = @{
            Source             = $TestConfig.InstanceCopy1
            Destination        = @($nativeBadInstance, $TestConfig.InstanceCopy2)
            AuditSpecification = $nativeSpecA
            EnableException    = $false
            WarningVariable    = "nativeWarnings"
            WarningAction      = "SilentlyContinue"
        }
        $result = @(Copy-DbaInstanceAuditSpecification @splatContinue)
        $result.Count | Should -Be 1
        $result[0].Status | Should -BeExactly "Skipped"
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "keeps earlier output before -EnableException stops at a failed destination, and stops at a failed source" -Tag "NativeChecklist:enable-exception" {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            Copy-DbaInstanceAuditSpecification -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2, $nativeBadInstance -AuditSpecification $nativeSpecA -EnableException |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"

        $nativeWarnings = @()
        $splatBadSource = @{
            Source          = $nativeBadInstance
            Destination     = $TestConfig.InstanceCopy2
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Copy-DbaInstanceAuditSpecification @splatBadSource).Count | Should -Be 0
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
        $nativeSourceCaught = $null
        try {
            $null = Copy-DbaInstanceAuditSpecification -Source $nativeBadInstance -Destination $TestConfig.InstanceCopy2 -EnableException
        } catch {
            $nativeSourceCaught = $PSItem
        }
        $nativeSourceCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Copy-DbaInstanceAuditSpecification refuses Azure SQL Database" -Tag IntegrationTests {
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
    }

    It "warns that Azure SQL Database is not supported as the source and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            Source          = $azureServer
            Destination     = $TestConfig.InstanceCopy2
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Copy-DbaInstanceAuditSpecification @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for an Azure SQL Database destination under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaInstanceAuditSpecification -Source $TestConfig.InstanceCopy1 -Destination $azureServer -AuditSpecification "native_auditspec_none" -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Copy-DbaInstanceAuditSpecification over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared. The audit is never enabled.
            $loginSuffix = [Guid]::NewGuid().ToString("N")
            $loginAudit = "native_auditspec_login_$loginSuffix"
            $loginSpec = "native_auditspec_loginspec_$loginSuffix"
            $null = $loginServer.Query("CREATE SERVER AUDIT [$loginAudit] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")
            $null = $loginServer.Query("CREATE SERVER AUDIT SPECIFICATION [$loginSpec] FOR SERVER AUDIT [$loginAudit] ADD (FAILED_LOGIN_GROUP)")
        }
        AfterAll {
            if ($loginServer) {
                $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'$loginSpec') DROP SERVER AUDIT SPECIFICATION [$loginSpec]; IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$loginAudit') DROP SERVER AUDIT [$loginAudit];")
            }
        }

        # Source and destination are the same shared instance, so the specification exists and nothing changes there.
        It "works with the source and destination credentials" {
            $splatLogin = @{
                Source                   = $loginInstance
                SourceSqlCredential      = $loginCred
                Destination              = $loginInstance
                DestinationSqlCredential = $loginCred
                AuditSpecification       = $loginSpec
                EnableException          = $true
            }
            $loginRows = @(Copy-DbaInstanceAuditSpecification @splatLogin)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly $loginSpec
            $loginRows[0].Status | Should -BeExactly "Skipped"
            $loginRows[0].Notes | Should -BeExactly "Already exists on destination"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                Source             = $loginInstance
                Destination        = $loginInstance
                AuditSpecification = $loginSpec
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "loginWarnings"
            }
            @(Copy-DbaInstanceAuditSpecification @splatLoginNoCredential).Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Copy-DbaInstanceAuditSpecification -Source $loginInstance -Destination $loginInstance -AuditSpecification $loginSpec -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
