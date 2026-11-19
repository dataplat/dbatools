#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAvailableCollation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native available collation behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeCollationServer = $null
        $nativeCollationSecondServer = $null
        $splatNativeCollationConnection = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativeCollationServer = Connect-DbaInstance @splatNativeCollationConnection
        $nativeCollationSecondServer = Connect-DbaInstance @splatNativeCollationConnection
        if ([object]::ReferenceEquals($nativeCollationServer, $nativeCollationSecondServer)) {
            throw "The pipeline fixture requires distinct SMO Server objects"
        }
        $nativeCollationExpectedCount = $nativeCollationServer.EnumCollations().Rows.Count
        $nativeCollationDisplay = "ComputerName,InstanceName,SqlInstance,Name,CodePage,CodePageName,LocaleID,LocaleName,Description"
    }

    AfterAll {
        if ($nativeCollationSecondServer) { $nativeCollationSecondServer.ConnectionContext.Disconnect() }
        if ($nativeCollationServer) { $nativeCollationServer.ConnectionContext.Disconnect() }
    }

    It "decorates every collation row with instance notes, descriptions and the display set" {
        $nativeCollationRows = @(Get-DbaAvailableCollation -SqlInstance $nativeCollationServer -EnableException)
        $nativeCollationRows.Count | Should -Be $nativeCollationExpectedCount
        $nativeCollationRows[0] | Should -BeOfType System.Data.DataRow
        $nativeCollationLatin = @($nativeCollationRows | Where-Object Name -eq "Latin1_General_CI_AS")
        $nativeCollationLatin.Count | Should -Be 1
        $nativeCollationLatin[0].ComputerName | Should -BeExactly $nativeCollationServer.ComputerName
        $nativeCollationLatin[0].InstanceName | Should -BeExactly $nativeCollationServer.ServiceName
        $nativeCollationLatin[0].SqlInstance | Should -BeExactly $nativeCollationServer.DomainInstanceName
        $nativeCollationLatin[0].CodePageName | Should -BeExactly ([System.Text.Encoding]::GetEncoding([int]$nativeCollationLatin[0].CodePage)).EncodingName
        $nativeCollationLatin[0].LocaleName | Should -BeExactly ([System.Globalization.CultureInfo]::GetCultureInfo([int]$nativeCollationLatin[0].LocaleID)).DisplayName
        ($nativeCollationLatin[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeCollationDisplay
        # The seeded [int] cache key answers the locale Windows no longer resolves.
        $nativeCollationJapanese = @($nativeCollationRows | Where-Object { $PSItem.LocaleID -eq 66577 })
        $nativeCollationJapanese.Count | Should -BeGreaterThan 0
        @($nativeCollationJapanese | Where-Object LocaleName -cne "Japanese_Unicode").Count | Should -Be 0
        @($nativeCollationRows | Where-Object { $null -eq $PSItem.PSStandardMembers }).Count | Should -Be 0
    }

    It "leaves the code page name empty for Unicode-only collations" {
        # Code page 0 means the collation has no code page; GetEncoding(0) would name the client's default encoding.
        $nativeCollationRows = @(Get-DbaAvailableCollation -SqlInstance $nativeCollationServer -EnableException)
        $nativeCollationUnicodeOnly = @($nativeCollationRows | Where-Object { $PSItem.CodePage -eq 0 })
        $nativeCollationUnicodeOnly.Count | Should -BeGreaterThan 0
        @($nativeCollationUnicodeOnly | Where-Object { $null -ne $PSItem.CodePageName }).Count | Should -Be 0
    }

    It "emits a separately decorated table for each piped server record" -Tag "NativeChecklist:pipeline-multiple" {
        $nativeCollationPiped = @(@($nativeCollationServer, $nativeCollationSecondServer) | Get-DbaAvailableCollation -EnableException)
        $nativeCollationPiped.Count | Should -Be ($nativeCollationExpectedCount * 2)
        [object]::ReferenceEquals($nativeCollationPiped[0].Table, $nativeCollationPiped[$nativeCollationExpectedCount].Table) | Should -BeFalse
        @($nativeCollationPiped | Where-Object Name -eq "Latin1_General_CI_AS").Count | Should -Be 2
    }

    It "continues after a failed connection unless EnableException terminates after streaming earlier rows" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeCollationSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeCollationListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeCollationListener.Start()
            $nativeCollationBadInstance = "127.0.0.1," + $nativeCollationListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeCollationPreviousErrors = @($global:Error)
            $nativeCollationWarnings = @()
            $splatNativeCollationContinue = @{
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeCollationWarnings"
            }
            $nativeCollationContinued = @(@($nativeCollationServer, $nativeCollationBadInstance, $nativeCollationSecondServer) | Get-DbaAvailableCollation @splatNativeCollationContinue)
            $nativeCollationContinued.Count | Should -Be ($nativeCollationExpectedCount * 2)
            ($nativeCollationWarnings -join " ") | Should -BeLike "*Failure*"
            $nativeCollationConnectionError = $global:Error | Where-Object {
                $nativeCollationPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaAvailableCollation*"
            } | Select-Object -First 1
            $nativeCollationConnectionError | Should -Not -BeNullOrEmpty
            $nativeCollationConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
            $nativeCollationConnectionError.TargetObject.GetType().FullName | Should -BeExactly "System.String"
            $nativeCollationConnectionError.TargetObject | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativeCollationBadInstance).FullSmoName

            $nativeCollationEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeCollationCaught = $null
            $splatNativeCollationContinue.EnableException = $true
            try {
                @($nativeCollationServer, $nativeCollationBadInstance, $nativeCollationSecondServer) |
                    Get-DbaAvailableCollation @splatNativeCollationContinue |
                    ForEach-Object { $nativeCollationEarlier.Add($PSItem) }
            } catch {
                $nativeCollationCaught = $PSItem
            }
            $nativeCollationEarlier.Count | Should -Be $nativeCollationExpectedCount
            $nativeCollationCaught | Should -Not -BeNullOrEmpty
            $nativeCollationCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $nativeCollationCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaAvailableCollation*"
            $nativeCollationCaught.TargetObject | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativeCollationBadInstance).FullSmoName
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeCollationSavedTimeout
            $nativeCollationListener.Stop()
        }
    }
}

Describe "Native Get-DbaAvailableCollation on Azure SQL Database" -Tag IntegrationTests {
    It "lists the collations Azure SQL Database supports" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Read-only: nothing is created in the shared database.
        $azureRows = @(Get-DbaAvailableCollation -SqlInstance $azureServer -EnableException)
        $azureRows.Count | Should -BeGreaterThan 0
        $azureLatin = @($azureRows | Where-Object Name -eq "SQL_Latin1_General_CP1_CI_AS")
        $azureLatin.Count | Should -Be 1
        $azureLatin[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $azureLatin[0].CodePageName | Should -BeExactly ([System.Text.Encoding]::GetEncoding([int]$azureLatin[0].CodePage)).EncodingName
    }
}

Describe "Native Get-DbaAvailableCollation over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginRows = @(Get-DbaAvailableCollation -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $loginRows.Count | Should -BeGreaterThan 0
            @($loginRows | Where-Object Name -eq "Latin1_General_CI_AS").Count | Should -Be 1
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaAvailableCollation @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaAvailableCollation -SqlInstance $loginInstance -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
