#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaExtendedStoredProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; destination arrays are covered below.
# NativeChecklist: sql-login N/A -- the pinned command has SourceSqlCredential and DestinationSqlCredential but no SqlCredential parameter.
# NativeChecklist: azure-sqldb N/A -- extended stored procedures exist only in the master database of SQL Server: sys.extended_procedures, sp_addextendedproc and sp_dropextendedproc apply to SQL Server only (Microsoft Learn, sys.extended_procedures and sys.sp_addextendedproc), and the command copies their DLL files to the instance's Binn directory. The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.
Describe "Native Copy-DbaExtendedStoredProcedure" -Tag IntegrationTests {
    BeforeAll {
        $nativeXpSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $nativeXpDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $nativeXpSuffix = [guid]::NewGuid().ToString("N")
        $nativeXpExists = "xp_dbatoolsci_exists_$nativeXpSuffix"
        $nativeXpPlain = "xp_dbatoolsci_plain_$nativeXpSuffix"
        $nativeXpCopy = "xp_dbatoolsci_copy_$nativeXpSuffix"
        $nativeXpQuote = "xp_dbatoolsci_quote_$nativeXpSuffix"
        $nativeXpReadOnly = "xp_dbatoolsci_readonly_$nativeXpSuffix"
        $nativeXpNames = @($nativeXpExists, $nativeXpPlain, $nativeXpCopy, $nativeXpQuote, $nativeXpReadOnly)
        # Registering an extended stored procedure records its DLL path only; nothing loads the DLL until it runs.
        $nativeXpSourceDll = @{
            $nativeXpExists = "C:\dbatoolsci\dbatoolsci_exists_$nativeXpSuffix.dll"
            $nativeXpPlain  = "C:\dbatoolsci\dbatoolsci_plain_$nativeXpSuffix.dll"
            $nativeXpCopy   = "dbatoolsci_copy_$nativeXpSuffix.dll"
            $nativeXpReadOnly = "dbatoolsci_readonly_$nativeXpSuffix.dll"
            $nativeXpQuote  = "C:\dbatoolsci\O'Brien_$nativeXpSuffix.dll"
        }
        $nativeXpOldDll = "C:\dbatoolsci\dbatoolsci_old_$nativeXpSuffix.dll"
        $nativeXpTempPath = "C:\Windows\Temp"

        function Add-NativeXp ($Server, $Name, $Dll) {
            $null = $Server.Databases["master"].ExecuteNonQuery("EXEC dbo.sp_addextendedproc @functname = N'$Name', @dllname = N'$($Dll.Replace("'", "''"))'")
        }
        function Get-NativeXpDll ($Server, $Name) {
            $Server.Databases["master"].ExecuteWithResults("SELECT dll_name FROM sys.extended_procedures WHERE name = N'$Name'").Tables[0].Rows | ForEach-Object { $PSItem.dll_name }
        }
        function Get-NativeUncPath ($Server, $Path) {
            "\\" + $Server.ComputerName + "\" + ($Path -replace ":", "$")
        }

        foreach ($nativeXpName in $nativeXpNames) {
            Add-NativeXp -Server $nativeXpSource -Name $nativeXpName -Dll $nativeXpSourceDll[$nativeXpName]
        }
        Add-NativeXp -Server $nativeXpDestination -Name $nativeXpExists -Dll $nativeXpOldDll

        # The DLL the copy test finds in the source Binn directory, and where -DestinationPath puts it. The command
        # reaches both through \\<ComputerName>\<drive>$. A failover cluster instance's ComputerName is its virtual
        # network name, which serves no administrative share ("The network name cannot be found"), so on a clustered
        # source the command cannot see the DLL and no fixture file is written there.
        $nativeXpSourceBinn = $nativeXpSource.RootDirectory + "\Binn"
        $nativeXpSourceClustered = $nativeXpSource.IsClustered
        $nativeXpSourceFile = Get-NativeUncPath -Server $nativeXpSource -Path "$nativeXpSourceBinn\$($nativeXpSourceDll[$nativeXpCopy])"
        $nativeXpDestinationFile = Get-NativeUncPath -Server $nativeXpDestination -Path "$nativeXpTempPath\$($nativeXpSourceDll[$nativeXpCopy])"
        $nativeXpBytes = [byte[]](77, 90, 1, 2, 3, 5, 8, 13)
        # The read-only test: a source DLL in the Binn directory, and an older read-only copy already at the
        # destination path, which Copy-Item -Force overwrites.
        $nativeXpReadOnlySourceFile = Get-NativeUncPath -Server $nativeXpSource -Path "$nativeXpSourceBinn\$($nativeXpSourceDll[$nativeXpReadOnly])"
        $nativeXpReadOnlyDestinationFile = Get-NativeUncPath -Server $nativeXpDestination -Path "$nativeXpTempPath\$($nativeXpSourceDll[$nativeXpReadOnly])"
        $nativeXpOldBytes = [byte[]](77, 90, 9, 9, 9)
        if (-not $nativeXpSourceClustered) {
            [System.IO.File]::WriteAllBytes($nativeXpSourceFile, $nativeXpBytes)
            [System.IO.File]::WriteAllBytes($nativeXpReadOnlySourceFile, $nativeXpBytes)
            [System.IO.File]::WriteAllBytes($nativeXpReadOnlyDestinationFile, $nativeXpOldBytes)
            [System.IO.File]::SetAttributes($nativeXpReadOnlyDestinationFile, [System.IO.FileAttributes]::ReadOnly)
        }
    }

    AfterAll {
        foreach ($nativeXpServer in @($nativeXpSource, $nativeXpDestination)) {
            foreach ($nativeXpName in $nativeXpNames) {
                $null = $nativeXpServer.Databases["master"].ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.extended_procedures WHERE name = N'$nativeXpName') EXEC dbo.sp_dropextendedproc @functname = N'$nativeXpName'")
            }
        }
        $nativeXpFiles = @($nativeXpDestinationFile)
        if (-not $nativeXpSourceClustered) { $nativeXpFiles += @($nativeXpSourceFile, $nativeXpReadOnlySourceFile, $nativeXpReadOnlyDestinationFile) }
        foreach ($nativeXpFile in $nativeXpFiles) {
            if ($nativeXpFile -and (Test-Path -LiteralPath $nativeXpFile)) {
                Remove-Item -LiteralPath $nativeXpFile -Force
            }
        }
    }

    It "continues destination arrays after a connection failure with explicit false switches" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false", "NativeChecklist:enable-exception" {
        $splatNativeXpContinue = @{
            Source           = $nativeXpSource
            Destination      = @($nativeXpDestination, "tcp:127.0.0.1,1", $nativeXpDestination)
            ExtendedProcedure = $nativeXpExists
            Force            = $false
            EnableException  = $false
            Confirm          = $false
            WarningAction    = "SilentlyContinue"
            WarningVariable  = "nativeXpWarning"
        }
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure @splatNativeXpContinue)
        $nativeXpResult.Count | Should -Be 2
        $nativeXpResult.Status | Should -Be @("Skipped", "Skipped")
        $nativeXpResult.Notes | Should -Be @("Already exists on destination", "Already exists on destination")
        ($nativeXpWarning -join " ") | Should -BeLike "*Failure*"
        Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpExists | Should -Be $nativeXpOldDll
    }

    It "throws on a destination connection failure when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        $nativeXpError = $null
        try {
            $null = Copy-DbaExtendedStoredProcedure -Source $nativeXpSource -Destination "tcp:127.0.0.1,1" -ExtendedProcedure $nativeXpExists -EnableException -Confirm:$false
        } catch {
            $nativeXpError = $PSItem
        }
        $nativeXpError | Should -Not -BeNullOrEmpty
        $nativeXpError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }

    It "honors WhatIf with Force" -Tag "NativeChecklist:whatif-confirm" {
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure -Source $nativeXpSource -Destination $nativeXpDestination -ExtendedProcedure $nativeXpExists, $nativeXpPlain -Force -WhatIf)
        $nativeXpResult.Count | Should -Be 0
        Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpExists | Should -Be $nativeXpOldDll
        Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpPlain | Should -BeNullOrEmpty
    }

    It "applies ExcludeExtendedProcedure after ExtendedProcedure" {
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure -Source $nativeXpSource -Destination $nativeXpDestination -ExtendedProcedure $nativeXpPlain -ExcludeExtendedProcedure $nativeXpPlain.ToUpperInvariant() -Confirm:$false)
        $nativeXpResult.Count | Should -Be 0
        Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpPlain | Should -BeNullOrEmpty
    }

    It "registers a procedure whose DLL is not in the source Binn directory" {
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure -Source $nativeXpSource -Destination $nativeXpDestination -ExtendedProcedure $nativeXpPlain.ToUpperInvariant() -Confirm:$false -WarningAction SilentlyContinue)
        $nativeXpResult.Count | Should -Be 1
        $nativeXpResult[0].Name | Should -BeExactly $nativeXpPlain
        $nativeXpResult[0].Schema | Should -BeExactly "dbo"
        $nativeXpResult[0].Type | Should -BeExactly "Extended Stored Procedure"
        $nativeXpResult[0].SourceServer | Should -Be $nativeXpSource.Name
        $nativeXpResult[0].DestinationServer | Should -Be $nativeXpDestination.Name
        $nativeXpResult[0].Notes | Should -Be "Source DLL not found at expected path: $nativeXpSourceBinn\dbatoolsci_plain_$nativeXpSuffix.dll"
        $nativeXpResult[0].Status | Should -Be "Successful (DLL not copied)"
        Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpPlain | Should -Be $nativeXpSourceDll[$nativeXpPlain]
    }

    It "copies the DLL from the source Binn directory to the destination path" {
        $splatNativeXpCopy = @{
            Source            = $nativeXpSource
            Destination       = $nativeXpDestination
            ExtendedProcedure = $nativeXpCopy
            DestinationPath   = $nativeXpTempPath
            Confirm           = $false
        }
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure @splatNativeXpCopy -WarningAction SilentlyContinue)
        $nativeXpResult.Count | Should -Be 1
        if ($nativeXpSourceClustered) {
            # The pinned UNC rule on a clustered source: the DLL is not seen, and the source path is registered.
            $nativeXpResult[0].Notes | Should -Be "Source DLL not found at expected path: $nativeXpSourceBinn\dbatoolsci_copy_$nativeXpSuffix.dll"
            $nativeXpResult[0].Status | Should -Be "Successful (DLL not copied)"
            Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpCopy | Should -Be $nativeXpSourceDll[$nativeXpCopy]
            Test-Path -LiteralPath $nativeXpDestinationFile | Should -BeFalse
        } else {
            $nativeXpResult[0].Notes | Should -BeNullOrEmpty
            $nativeXpResult[0].Status | Should -Be "Successful"
            Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpCopy | Should -Be "$nativeXpTempPath\dbatoolsci_copy_$nativeXpSuffix.dll"
            [System.IO.File]::ReadAllBytes($nativeXpDestinationFile) | Should -Be $nativeXpBytes
        }
    }

    # Review afec04d8a: the pinned Copy-Item -Force overwrites a read-only DLL already at the destination path.
    It "overwrites a read-only DLL at the destination path, as Copy-Item -Force does" {
        $splatNativeXpReadOnly = @{
            Source            = $nativeXpSource
            Destination       = $nativeXpDestination
            ExtendedProcedure = $nativeXpReadOnly
            DestinationPath   = $nativeXpTempPath
            Confirm           = $false
        }
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure @splatNativeXpReadOnly -WarningAction SilentlyContinue)
        $nativeXpResult.Count | Should -Be 1
        if ($nativeXpSourceClustered) {
            # The pinned UNC rule on a clustered source: the DLL is not seen, and the source path is registered.
            $nativeXpResult[0].Status | Should -Be "Successful (DLL not copied)"
            Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpReadOnly | Should -Be $nativeXpSourceDll[$nativeXpReadOnly]
        } else {
            $nativeXpResult[0].Notes | Should -BeNullOrEmpty
            $nativeXpResult[0].Status | Should -Be "Successful"
            Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpReadOnly | Should -Be "$nativeXpTempPath\dbatoolsci_readonly_$nativeXpSuffix.dll"
            [System.IO.File]::ReadAllBytes($nativeXpReadOnlyDestinationFile) | Should -Be $nativeXpBytes
        }
    }

    It "registers a DLL path holding an apostrophe as text" {
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure -Source $nativeXpSource -Destination $nativeXpDestination -ExtendedProcedure $nativeXpQuote -Confirm:$false -WarningAction SilentlyContinue)
        $nativeXpResult.Count | Should -Be 1
        $nativeXpResult[0].Notes | Should -Be "Source DLL not found at expected path: $nativeXpSourceBinn\O'Brien_$nativeXpSuffix.dll"
        $nativeXpResult[0].Status | Should -Be "Successful (DLL not copied)"
        Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpQuote | Should -Be $nativeXpSourceDll[$nativeXpQuote]
    }

    It "replaces an existing destination procedure with Force" {
        $nativeXpResult = @(Copy-DbaExtendedStoredProcedure -Source $nativeXpSource -Destination $nativeXpDestination -ExtendedProcedure $nativeXpExists -Force -WarningAction SilentlyContinue)
        $nativeXpResult.Count | Should -Be 1
        $nativeXpResult[0].Status | Should -Be "Successful (DLL not copied)"
        Get-NativeXpDll -Server $nativeXpDestination -Name $nativeXpExists | Should -Be $nativeXpSourceDll[$nativeXpExists]
    }
}

# Correction azure-unsupported: Azure SQL Database has no extended stored procedures, so the command refuses it as
# Connect-DbaInstance -AzureUnsupported does, for the source and for each destination.
Describe "Native Copy-DbaExtendedStoredProcedure refuses Azure SQL Database" -Tag IntegrationTests {
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
        $azureXpName = "xp_dbatoolsci_azure_" + [guid]::NewGuid().ToString("N")
    }

    It "warns that Azure SQL Database is not supported as the source and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureSource = @{
            Source            = $azureServer
            Destination       = $TestConfig.InstanceCopy2
            ExtendedProcedure = $azureXpName
            Confirm           = $false
            WarningVariable   = "azureWarnings"
            WarningAction     = "SilentlyContinue"
        }
        @(Copy-DbaExtendedStoredProcedure @splatAzureSource).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for an Azure SQL Database destination under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaExtendedStoredProcedure -Source $TestConfig.InstanceCopy1 -Destination $azureServer -ExtendedProcedure $azureXpName -Confirm:$false -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}
