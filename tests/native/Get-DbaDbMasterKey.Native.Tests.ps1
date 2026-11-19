#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMasterKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters, despite stale help text mentioning them.
Describe "Native database master key behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeMasterKeyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeMasterKeySuffix = [Guid]::NewGuid().ToString("N")
        $nativeMasterKeyFirst = "native_mk_a_$nativeMasterKeySuffix"
        $nativeMasterKeySecond = "native_mk_b_$nativeMasterKeySuffix"
        $nativeMasterKeyNone = "native_mk_none_$nativeMasterKeySuffix"
        $nativeMasterKeyOffline = "native_mk_off_$nativeMasterKeySuffix"
        # A real name that is also a wildcard expression matching $nativeMasterKeyFirst.
        $nativeMasterKeyBracket = "native_mk_[a]_$nativeMasterKeySuffix"
        $nativeMasterKeyCreated = @()
        $nativeMasterKeyOfflineSet = $false
        foreach ($nativeMasterKeyName in $nativeMasterKeyFirst, $nativeMasterKeySecond, $nativeMasterKeyNone, $nativeMasterKeyOffline, $nativeMasterKeyBracket) {
            $nativeMasterKeyNewDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeMasterKeyServer, $nativeMasterKeyName
            $nativeMasterKeyNewDatabase.Create()
            $nativeMasterKeyCreated += $nativeMasterKeyName
        }
        foreach ($nativeMasterKeyName in $nativeMasterKeyFirst, $nativeMasterKeySecond, $nativeMasterKeyBracket) {
            $nativeMasterKeyServer.Databases[$nativeMasterKeyName].ExecuteNonQuery("CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Native!MasterKey#2026'")
        }
        $nativeMasterKeyServer.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$nativeMasterKeyOffline] SET OFFLINE WITH ROLLBACK IMMEDIATE")
        $nativeMasterKeyOfflineSet = $true
        $nativeMasterKeyServer.Databases.Refresh()
        # The collection refresh keeps the cached Database object, whose IsAccessible still reads true
        # after the raw SET OFFLINE; re-read its properties so the offline tests see an inaccessible database.
        $nativeMasterKeyServer.Databases[$nativeMasterKeyOffline].Refresh()
        if ($nativeMasterKeyServer.Databases[$nativeMasterKeyOffline].IsAccessible) {
            throw "Fixture: SMO still reports [$nativeMasterKeyOffline] as accessible after SET OFFLINE"
        }
        $nativeMasterKeyDisplay = "ComputerName,InstanceName,SqlInstance,Database,CreateDate,DateLastModified,IsEncryptedByServer"
    }

    AfterAll {
        if ($nativeMasterKeyOfflineSet) {
            $nativeMasterKeyServer.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$nativeMasterKeyOffline] SET ONLINE")
        }
        if ($nativeMasterKeyCreated.Count -gt 0) {
            $splatRemoveNativeMasterKeyDatabase = @{
                SqlInstance     = $nativeMasterKeyServer
                Database        = $nativeMasterKeyCreated
                Confirm         = $false
                EnableException = $true
            }
            $null = Remove-DbaDatabase @splatRemoveNativeMasterKeyDatabase
        }
    }

    It "emits decorated SMO master keys with the default view on repeated reads" {
        $splatNativeMasterKeyRead = @{
            SqlInstance     = $nativeMasterKeyServer
            Database        = @($nativeMasterKeyFirst.ToUpperInvariant(), $nativeMasterKeySecond)
            EnableException = $true
        }
        foreach ($nativeMasterKeyIteration in 1, 2) {
            $nativeMasterKeyRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRead)
            $nativeMasterKeyRows.Count | Should -Be 2
            ($nativeMasterKeyRows.Database -join ",") | Should -BeExactly "$nativeMasterKeyFirst,$nativeMasterKeySecond"
            foreach ($nativeMasterKeyRow in $nativeMasterKeyRows) {
                $nativeMasterKeyRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.MasterKey
                $nativeMasterKeyRow.ComputerName | Should -BeExactly $nativeMasterKeyServer.ComputerName
                $nativeMasterKeyRow.InstanceName | Should -BeExactly $nativeMasterKeyServer.ServiceName
                $nativeMasterKeyRow.SqlInstance | Should -BeExactly $nativeMasterKeyServer.DomainInstanceName
                $nativeMasterKeyRow.IsEncryptedByServer | Should -BeTrue
                $nativeMasterKeyRow.Parent.Name | Should -BeExactly $nativeMasterKeyRow.Database
                ($nativeMasterKeyRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeMasterKeyDisplay
                @($nativeMasterKeyRow.PSObject.Properties | Where-Object Name -eq "Database").Count | Should -Be 1
            }
        }
    }

    It "lets database exclusion remove an explicitly included database" {
        $splatNativeMasterKeyExclude = @{
            SqlInstance     = $nativeMasterKeyServer
            Database        = @($nativeMasterKeyFirst, $nativeMasterKeySecond)
            ExcludeDatabase = $nativeMasterKeySecond.ToUpperInvariant()
            EnableException = $true
        }
        $nativeMasterKeyExcluded = @(Get-DbaDbMasterKey @splatNativeMasterKeyExclude)
        ($nativeMasterKeyExcluded.Database -join ",") | Should -BeExactly $nativeMasterKeyFirst
    }

    It "skips a database without a master key with a verbose message" {
        $splatNativeMasterKeyNone = @{
            SqlInstance     = $nativeMasterKeyServer
            Database        = $nativeMasterKeyNone
            EnableException = $true
            Verbose         = $true
        }
        $nativeMasterKeyNoneRecords = @(Get-DbaDbMasterKey @splatNativeMasterKeyNone 4>&1)
        @($nativeMasterKeyNoneRecords | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
        $nativeMasterKeyNoneVerbose = @($nativeMasterKeyNoneRecords | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No master key exists*" })
        $nativeMasterKeyNoneVerbose.Count | Should -Be 1
        $nativeMasterKeyNoneVerbose[0].Message | Should -BeLike "*No master key exists in the ``[$nativeMasterKeyNone``] database on $($nativeMasterKeyServer.Name)"
    }

    It "warns and continues for an offline database with either EnableException value" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        foreach ($nativeMasterKeyEnable in $false, $true) {
            $nativeMasterKeyOfflineWarnings = @()
            $splatNativeMasterKeyOffline = @{
                SqlInstance     = $nativeMasterKeyServer
                Database        = @($nativeMasterKeyFirst, $nativeMasterKeyOffline)
                EnableException = $nativeMasterKeyEnable
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeMasterKeyOfflineWarnings"
            }
            $nativeMasterKeyOfflineRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyOffline)
            ($nativeMasterKeyOfflineRows.Database -join ",") | Should -BeExactly $nativeMasterKeyFirst
            $nativeMasterKeyOfflineWarnings.Count | Should -Be 1
            "$nativeMasterKeyOfflineWarnings" | Should -BeLike "*Database ``[$nativeMasterKeyOffline``] on *is not accessible. Skipping."
        }
    }

    It "emits a key for every piped database and warns for an offline one partway" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        $nativeMasterKeyPipeWarnings = @()
        $splatNativeMasterKeyPipe = @{
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeMasterKeyPipeWarnings"
        }
        $nativeMasterKeyPiped = @(
            @($nativeMasterKeyServer.Databases[$nativeMasterKeyFirst], $nativeMasterKeyServer.Databases[$nativeMasterKeyOffline], $nativeMasterKeyServer.Databases[$nativeMasterKeyNone], $nativeMasterKeyServer.Databases[$nativeMasterKeySecond]) |
                Get-DbaDbMasterKey @splatNativeMasterKeyPipe
        )
        ($nativeMasterKeyPiped.Database -join ",") | Should -BeExactly "$nativeMasterKeyFirst,$nativeMasterKeySecond"
        $nativeMasterKeyPipeWarnings.Count | Should -Be 1
        "$nativeMasterKeyPipeWarnings" | Should -BeLike "*Database ``[$nativeMasterKeyOffline``] on *is not accessible. Skipping."
    }

    It "warns for a failed instance and continues with the remaining instances" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $nativeMasterKeySavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeMasterKeyListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeMasterKeyListener.Start()
            $nativeMasterKeyBadInstance = "127.0.0.1," + $nativeMasterKeyListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeMasterKeyFailureWarnings = @()
            $splatNativeMasterKeyFailure = @{
                SqlInstance     = @($nativeMasterKeyServer, $nativeMasterKeyBadInstance, $nativeMasterKeyServer)
                Database        = $nativeMasterKeyFirst
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeMasterKeyFailureWarnings"
            }
            $nativeMasterKeyContinued = @(Get-DbaDbMasterKey @splatNativeMasterKeyFailure)
            ($nativeMasterKeyContinued.Database -join ",") | Should -BeExactly "$nativeMasterKeyFirst,$nativeMasterKeyFirst"
            ($nativeMasterKeyFailureWarnings -join " ") | Should -BeLike "*Failure*"
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeMasterKeySavedTimeout
            $nativeMasterKeyListener.Stop()
        }
    }

    It "warns for a null element of an explicit input array and emits the rest" {
        $nativeMasterKeyNullWarnings = @()
        $splatNativeMasterKeyNull = @{
            InputObject     = @($null, $nativeMasterKeyServer.Databases[$nativeMasterKeyFirst])
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeMasterKeyNullWarnings"
        }
        $nativeMasterKeyNullRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyNull)
        ($nativeMasterKeyNullRows.Database -join ",") | Should -BeExactly $nativeMasterKeyFirst
        $nativeMasterKeyNullWarnings.Count | Should -Be 1
        "$nativeMasterKeyNullWarnings" | Should -BeLike "*Database  on  is not accessible. Skipping."
    }

    It "returns nothing without SqlInstance or InputObject" {
        $nativeMasterKeyEmptyWarnings = @()
        @(Get-DbaDbMasterKey -WarningAction SilentlyContinue -WarningVariable nativeMasterKeyEmptyWarnings).Count | Should -Be 0
        $nativeMasterKeyEmptyWarnings | Should -BeNullOrEmpty
    }

    # Gate-1 correction (wrong-data): pinned public/Get-DbaDbMasterKey.ps1 appends the -SqlInstance
    # databases to the pipeline-bound InputObject on every record, so each instance key repeated once per piped database.
    It "emits each SqlInstance key once when databases are also piped" -Tag "NativeChecklist:pipeline-multiple" {
        $splatNativeMasterKeyMixed = @{
            SqlInstance     = $nativeMasterKeyServer
            Database        = $nativeMasterKeySecond
            EnableException = $true
        }
        $nativeMasterKeyMixed = @(
            @($nativeMasterKeyServer.Databases[$nativeMasterKeyFirst], $nativeMasterKeyServer.Databases[$nativeMasterKeyNone]) |
                Get-DbaDbMasterKey @splatNativeMasterKeyMixed
        )
        ($nativeMasterKeyMixed.Database -join ",") | Should -BeExactly "$nativeMasterKeyFirst,$nativeMasterKeySecond"
    }

    # Gate-1 correction (dead-parameter): the help documents wildcards for -Database and -ExcludeDatabase,
    # but the pinned source passes them to Get-DbaDatabase, which compares names literally.
    It "accepts the documented wildcard patterns for Database and ExcludeDatabase" {
        $splatNativeMasterKeyWildcard = @{
            SqlInstance     = $nativeMasterKeyServer
            Database        = "NATIVE_MK_?_$nativeMasterKeySuffix"
            EnableException = $true
        }
        $nativeMasterKeyWildcard = @(Get-DbaDbMasterKey @splatNativeMasterKeyWildcard)
        ($nativeMasterKeyWildcard.Database -join ",") | Should -BeExactly "$nativeMasterKeyFirst,$nativeMasterKeySecond"
        $splatNativeMasterKeyWildcard.ExcludeDatabase = "*_b_$nativeMasterKeySuffix"
        $nativeMasterKeyWildcardExcluded = @(Get-DbaDbMasterKey @splatNativeMasterKeyWildcard)
        ($nativeMasterKeyWildcardExcluded.Database -join ",") | Should -BeExactly $nativeMasterKeyFirst
    }

    It "selects only the exact database when a real name is also a wildcard expression" {
        $splatNativeMasterKeyBracket = @{
            SqlInstance     = $nativeMasterKeyServer
            Database        = $nativeMasterKeyBracket
            EnableException = $true
        }
        $nativeMasterKeyBracketRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyBracket)
        ($nativeMasterKeyBracketRows.Database -join ",") | Should -BeExactly $nativeMasterKeyBracket
        $splatNativeMasterKeyBracket.Database = @($nativeMasterKeyFirst, $nativeMasterKeyBracket)
        $splatNativeMasterKeyBracket.ExcludeDatabase = $nativeMasterKeyBracket
        $nativeMasterKeyBracketExcluded = @(Get-DbaDbMasterKey @splatNativeMasterKeyBracket)
        ($nativeMasterKeyBracketExcluded.Database -join ",") | Should -BeExactly $nativeMasterKeyFirst
    }

    # The shared wildcard rule tries only values containing * or ? as patterns: brackets alone stay
    # literal (an SMO object bound to a string array becomes "[name]") and an invalid pattern matches literally.
    It "keeps bracket-only and invalid wildcard values literal" {
        $splatNativeMasterKeyLiteral = @{
            SqlInstance     = $nativeMasterKeyServer
            Database        = "NATIVE_MK_[AB]_$nativeMasterKeySuffix"
            EnableException = $true
        }
        @(Get-DbaDbMasterKey @splatNativeMasterKeyLiteral).Count | Should -Be 0
        $splatNativeMasterKeyLiteral.Database = "native_mk_[*_$nativeMasterKeySuffix"
        @(Get-DbaDbMasterKey @splatNativeMasterKeyLiteral).Count | Should -Be 0
        $splatNativeMasterKeyLiteral.Database = @($nativeMasterKeyFirst, $nativeMasterKeySecond)
        $splatNativeMasterKeyLiteral.ExcludeDatabase = @("NATIVE_MK_[AB]_$nativeMasterKeySuffix", "native_mk_[*_$nativeMasterKeySuffix")
        $nativeMasterKeyLiteralRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyLiteral)
        ($nativeMasterKeyLiteralRows.Database -join ",") | Should -BeExactly "$nativeMasterKeyFirst,$nativeMasterKeySecond"
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :20 and :24 document wildcards for both filters; pinned Copy-DbaDbCertificate.ps1:227
            # and Start-DbaDbEncryption.ps1:266, :408 pass a real $db.Name): a value equal to a real database name
            # stays literal, so a caller passing a real name containing * or ? never reaches other databases.
            function New-NativeWildcardNameDatabase {
                param($Server, [string]$Name, [string]$FileStem)
                # Names with * or ? are not valid Windows file names, so the files get explicit names.
                $dataDirectory = $Server.DefaultFile
                if (-not $dataDirectory) { $dataDirectory = $Server.MasterDBPath }
                $logDirectory = $Server.DefaultLog
                if (-not $logDirectory) { $logDirectory = $Server.MasterDBLogPath }
                $separator = "\"
                if ($dataDirectory -match "/" -and $dataDirectory -notmatch "\\") { $separator = "/" }
                $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $Server, $Name
                $fileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $database, "PRIMARY"
                $database.FileGroups.Add($fileGroup)
                $dataPath = $dataDirectory.TrimEnd("\", "/") + $separator + $FileStem + ".mdf"
                $dataFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroup, ($FileStem + "_data"), $dataPath
                $dataFile.IsPrimaryFile = $true
                $fileGroup.Files.Add($dataFile)
                $logPath = $logDirectory.TrimEnd("\", "/") + $separator + $FileStem + "_log.ldf"
                $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile -ArgumentList $database, ($FileStem + "_log"), $logPath
                $database.LogFiles.Add($logFile)
                $database.Create()
                $database
            }
            $nativeMasterKeyRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeMasterKeyRealNameNames = @("${nativeMasterKeyRealNamePrefix}_*", "${nativeMasterKeyRealNamePrefix}_?", "${nativeMasterKeyRealNamePrefix}_x")
            $nativeMasterKeyRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeMasterKeyRealNameIndex in 0, 1, 2) {
                $nativeMasterKeyRealNameName = $nativeMasterKeyRealNameNames[$nativeMasterKeyRealNameIndex]
                $nativeMasterKeyRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeMasterKeyServer -Name $nativeMasterKeyRealNameName -FileStem ("${nativeMasterKeyRealNamePrefix}_file" + $nativeMasterKeyRealNameIndex)
                $nativeMasterKeyRealNameCreated.Add($nativeMasterKeyRealNameName)
                $nativeMasterKeyRealNameDatabase.ExecuteNonQuery("CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Native!MasterKey#2026'")
            }
            $nativeMasterKeyServer.Databases.Refresh()
        }

        AfterAll {
            $nativeMasterKeyServer.Databases.Refresh()
            foreach ($nativeMasterKeyRealNameName in $nativeMasterKeyRealNameCreated) {
                if ($nativeMasterKeyServer.Databases[$nativeMasterKeyRealNameName]) {
                    $nativeMasterKeyServer.KillDatabase($nativeMasterKeyRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeMasterKeyRealNameExact = @{
                SqlInstance     = $nativeMasterKeyServer
                Database        = $nativeMasterKeyRealNameNames[0]
                EnableException = $true
            }
            $nativeMasterKeyRealNameRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRealNameExact)
            (($nativeMasterKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeMasterKeyRealNameNames[0]
            $splatNativeMasterKeyRealNameExact.Database = $nativeMasterKeyRealNameNames[1].ToUpperInvariant()
            $nativeMasterKeyRealNameRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRealNameExact)
            (($nativeMasterKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeMasterKeyRealNameNames[1]
            $splatNativeMasterKeyRealNameExact.Database = $nativeMasterKeyRealNameNames[0, 1]
            $nativeMasterKeyRealNameRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRealNameExact)
            (($nativeMasterKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeMasterKeyRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeMasterKeyRealNamePattern = @{
                SqlInstance     = $nativeMasterKeyServer
                Database        = "${nativeMasterKeyRealNamePrefix}*"
                EnableException = $true
            }
            $nativeMasterKeyRealNameRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRealNamePattern)
            (($nativeMasterKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeMasterKeyRealNameNames | Sort-Object) -join ",")
            $splatNativeMasterKeyRealNamePattern.ExcludeDatabase = $nativeMasterKeyRealNameNames[1]
            $nativeMasterKeyRealNameRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRealNamePattern)
            (($nativeMasterKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeMasterKeyRealNameNames[0, 2] | Sort-Object) -join ",")
        }

        It "excludes only a real database whose name contains * or ? when its exact name is excluded" {
            $splatNativeMasterKeyRealNameExclude = @{
                SqlInstance     = $nativeMasterKeyServer
                Database        = $nativeMasterKeyRealNameNames
                ExcludeDatabase = $nativeMasterKeyRealNameNames[1]
                EnableException = $true
            }
            $nativeMasterKeyRealNameRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRealNameExclude)
            (($nativeMasterKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeMasterKeyRealNameNames[0, 2] | Sort-Object) -join ",")
            $splatNativeMasterKeyRealNameExclude.ExcludeDatabase = $nativeMasterKeyRealNameNames[0]
            $nativeMasterKeyRealNameRows = @(Get-DbaDbMasterKey @splatNativeMasterKeyRealNameExclude)
            (($nativeMasterKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeMasterKeyRealNameNames[1, 2] | Sort-Object) -join ",")
        }
    }
}
