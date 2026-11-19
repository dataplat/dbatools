#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- the pinned command has no pipeline parameter; destination arrays are covered.
# NativeChecklist: azure-sqldb N/A -- linked servers aren't available in Azure SQL Database; the command refuses it as Connect-DbaInstance -AzureUnsupported does. https://learn.microsoft.com/sql/relational-databases/linked-servers/linked-servers-database-engine
# NativeChecklist: sql-login N/A -- the pin declares SourceSqlCredential and DestinationSqlCredential, but no SqlCredential parameter.

Describe "Native Copy-DbaLinkedServer" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $linkSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $linkDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $linkPrefix = "dbatoolsci_nativels_" + [guid]::NewGuid().ToString("N")
        $linkAscii = "${linkPrefix}_ascii"
        $linkUnicode = "${linkPrefix}_unicode"
        $linkQuoted = "${linkPrefix}_net'name"
        $linkAsciiUser = "nativeuser_ascii"
        $linkUnicodeUser = "nativeuser_unicode"
        $linkAsciiSecret = "NativeAscii!123"
        $linkUnicodeSecret = ([char]0x6f22).ToString() + "Native'!" + ([char]0x5b57).ToString()
        $linkBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"

        function New-NativeLinkedServer {
            param($Server, [string]$Name, [string]$RemoteUser, [string]$Password)
            $escapedName = $Name.Replace("'", "''")
            $null = $Server.Query("EXEC master.dbo.sp_addlinkedserver @server = N'$escapedName', @srvproduct = N'SQL Server';")
            if ($RemoteUser) {
                $escapedPassword = $Password.Replace("'", "''")
                $null = $Server.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$escapedName', @useself = N'False', @locallogin = NULL, @rmtuser = N'$RemoteUser', @rmtpassword = N'$escapedPassword';")
            }
        }

        function Remove-NativeLinkedServer {
            param($Server, [string]$Name)
            $escapedName = $Name.Replace("'", "''")
            $null = $Server.Query("IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'$escapedName') EXEC master.dbo.sp_dropserver @server = N'$escapedName', @droplogins = 'droplogins';")
        }

        function Get-NativeLinkedServerPassword {
            param($Server, [string]$Name, [string]$RemoteUser)
            $secretDac = $null
            $secretSet = $null
            try {
                $splatSecretDac = @{
                    SqlInstance              = $Server
                    DedicatedAdminConnection = $true
                    EnableException          = $true
                }
                $secretDac = Connect-DbaInstance @splatSecretDac
                $secretSet = [Dataplat.Dbatools.Connection.LinkedServerLoginSecrets]::Read($secretDac, $null, [Threading.CancellationToken]::None)
                $secretLogin = @($secretSet.Logins | Where-Object { $PSItem.Name -eq $Name -and $PSItem.Identity -eq $RemoteUser })
                $secretLogin.Count | Should -Be 1
                (New-Object System.Net.NetworkCredential("", $secretLogin[0].Password)).Password
            } finally {
                if ($secretSet) { $secretSet.Dispose() }
                if ($secretDac) { $secretDac.ConnectionContext.Disconnect() }
            }
        }

        function Get-NativeLinkedServerPasswordList {
            param($Server, [string]$Name)
            $secretDac = $null
            $secretSet = $null
            try {
                $splatListDac = @{
                    SqlInstance              = $Server
                    DedicatedAdminConnection = $true
                    EnableException          = $true
                }
                $secretDac = Connect-DbaInstance @splatListDac
                $secretSet = [Dataplat.Dbatools.Connection.LinkedServerLoginSecrets]::Read($secretDac, $null, [Threading.CancellationToken]::None)
                foreach ($secretLogin in @($secretSet.Logins | Where-Object { $PSItem.Name -eq $Name })) {
                    [PSCustomObject]@{
                        Identity = $secretLogin.Identity
                        Password = (New-Object System.Net.NetworkCredential("", $secretLogin.Password)).Password
                    }
                }
            } finally {
                if ($secretSet) { $secretSet.Dispose() }
                if ($secretDac) { $secretDac.ConnectionContext.Disconnect() }
            }
        }

        $linkMapped = "${linkPrefix}_mapped"
        $linkMapLogins = @("${linkPrefix}_l1", "${linkPrefix}_l2", "${linkPrefix}_l3")
        foreach ($linkLoginServer in @($linkSource, $linkDestination)) {
            foreach ($linkMapLogin in $linkMapLogins) {
                $null = $linkLoginServer.Query("CREATE LOGIN [$linkMapLogin] WITH PASSWORD = N'Native!Map#7319', CHECK_POLICY = OFF;")
            }
        }
        New-NativeLinkedServer -Server $linkSource -Name $linkMapped
        $null = $linkSource.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$linkMapped', @useself = N'False', @locallogin = N'$($linkMapLogins[0])', @rmtuser = N'App', @rmtpassword = N'NativeUpper!1';")
        $null = $linkSource.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$linkMapped', @useself = N'False', @locallogin = N'$($linkMapLogins[1])', @rmtuser = N'app', @rmtpassword = N'NativeLower!2';")
        $null = $linkSource.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$linkMapped', @useself = N'False', @locallogin = N'$($linkMapLogins[2])', @rmtuser = N'shared', @rmtpassword = N'NativeSharedL3!3';")
        $null = $linkSource.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$linkMapped', @useself = N'False', @locallogin = NULL, @rmtuser = N'shared', @rmtpassword = N'NativeSharedAll!4';")

        New-NativeLinkedServer -Server $linkSource -Name $linkAscii -RemoteUser $linkAsciiUser -Password $linkAsciiSecret
        New-NativeLinkedServer -Server $linkSource -Name $linkUnicode -RemoteUser $linkUnicodeUser -Password $linkUnicodeSecret
        New-NativeLinkedServer -Server $linkSource -Name $linkQuoted
        $null = $linkSource.Query("EXEC master.dbo.sp_setnetname @server = N'$($linkQuoted.Replace("'", "''"))', @netname = N'localhost';")
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        foreach ($linkCleanupName in @($linkAscii, $linkUnicode, $linkQuoted, $linkMapped)) {
            Remove-NativeLinkedServer -Server $linkDestination -Name $linkCleanupName
        }
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($linkCleanupServer in @($linkSource, $linkDestination)) {
            foreach ($linkFinalName in @($linkAscii, $linkUnicode, $linkQuoted, $linkMapped)) {
                Remove-NativeLinkedServer -Server $linkCleanupServer -Name $linkFinalName
            }
            foreach ($linkMapLogin in $linkMapLogins) {
                $null = $linkCleanupServer.Query("IF SUSER_ID(N'$linkMapLogin') IS NOT NULL DROP LOGIN [$linkMapLogin];")
            }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "preserves the entire Unicode password through the remote host path" {
        $linkPhysicalHost = $linkSource.ConnectionContext.ExecuteScalar("SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'));")
        $linkPhysicalHost | Should -Not -Be $env:COMPUTERNAME
        $linkRemoteBefore = [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations
        $linkLocalBefore = [Dataplat.Dbatools.Connection.HostProtectedData]::LocalOperations
        $splatUnicodeCopy = @{
            Source          = $linkSource
            Destination     = $linkDestination
            LinkedServer    = $linkUnicode
            Confirm         = $false
            EnableException = $true
        }
        $linkUnicodeOutput = @(Copy-DbaLinkedServer @splatUnicodeCopy)
        ($linkUnicodeOutput.Status | Select-Object -Unique) | Should -BeExactly "Successful"
        [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations | Should -BeGreaterThan $linkRemoteBefore
        [Dataplat.Dbatools.Connection.HostProtectedData]::LocalOperations | Should -Be $linkLocalBefore
        Get-NativeLinkedServerPassword $linkSource $linkUnicode $linkUnicodeUser | Should -BeExactly $linkUnicodeSecret
        Get-NativeLinkedServerPassword $linkDestination $linkUnicode $linkUnicodeUser | Should -BeExactly $linkUnicodeSecret
    }

    It "reports the linked server and each copied login as separate rows" {
        $splatRowsCopy = @{
            Source          = $linkSource
            Destination     = $linkDestination
            LinkedServer    = $linkAscii
            Confirm         = $false
            EnableException = $true
        }
        $linkRows = @(Copy-DbaLinkedServer @splatRowsCopy)
        $linkRows.Count | Should -Be 2
        $linkRows[0].Name | Should -BeExactly $linkAscii
        $linkRows[0].Type | Should -BeExactly "Linked Server"
        $linkRows[0].Status | Should -BeExactly "Successful"
        $linkRows[1].Name | Should -BeExactly $linkAscii
        $linkRows[1].Type | Should -BeExactly $linkAsciiUser
        $linkRows[1].Status | Should -BeExactly "Successful"
        foreach ($linkRow in $linkRows) {
            ($linkRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                Should -BeExactly "DateTime,SourceServer,DestinationServer,Name,Type,Status,Notes"
            $linkRow.PSObject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }
        Get-NativeLinkedServerPassword $linkDestination $linkAscii $linkAsciiUser | Should -BeExactly $linkAsciiSecret
    }

    It "gives each login mapping its own password when remote users differ only by case or share a name" {
        $linkSourceList = @(Get-NativeLinkedServerPasswordList $linkSource $linkMapped)
        $linkSourceList.Count | Should -Be 4
        $splatMappedCopy = @{
            Source          = $linkSource
            Destination     = $linkDestination
            LinkedServer    = $linkMapped
            Confirm         = $false
            EnableException = $true
        }
        $linkMappedRows = @(Copy-DbaLinkedServer @splatMappedCopy)
        $linkMappedRows.Count | Should -Be 5
        ($linkMappedRows.Status | Select-Object -Unique) | Should -BeExactly "Successful"
        $linkMappedList = @(Get-NativeLinkedServerPasswordList $linkDestination $linkMapped)
        $linkMappedList.Count | Should -Be 4
        $linkUpper = @($linkMappedList | Where-Object { $PSItem.Identity -ceq "App" })
        $linkUpper.Count | Should -Be 1
        $linkUpper[0].Password | Should -BeExactly "NativeUpper!1"
        $linkLower = @($linkMappedList | Where-Object { $PSItem.Identity -ceq "app" })
        $linkLower.Count | Should -Be 1
        $linkLower[0].Password | Should -BeExactly "NativeLower!2"
        $linkShared = @($linkMappedList | Where-Object { $PSItem.Identity -ceq "shared" } | ForEach-Object { $PSItem.Password } | Sort-Object)
        ($linkShared -join "|") | Should -BeExactly "NativeSharedAll!4|NativeSharedL3!3"
    }

    It "sets the network name of a linked server whose name contains a quote" {
        $splatQuotedCopy = @{
            Source          = $linkSource
            Destination     = $linkDestination
            LinkedServer    = $linkQuoted
            ExcludePassword = $true
            Confirm         = $false
            EnableException = $true
        }
        $linkQuotedOutput = @(Copy-DbaLinkedServer @splatQuotedCopy)
        $linkQuotedOutput.Count | Should -Be 1
        $linkQuotedOutput[0].Status | Should -BeExactly "Successful"
        $linkDestination.LinkedServers.Refresh()
        $linkDestination.LinkedServers[$linkQuoted].DataSource | Should -BeExactly "localhost"
    }

    It "refuses an Azure destination and continues copying to the next destination" -Tag NativeChecklist:multi-instance-failure {
        $splatLinkAzure = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $linkAzureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $linkAzureServer = Connect-DbaInstance @splatLinkAzure
                break
            } catch {
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $linkAzureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $linkAzureWarnings = @()
            $splatLinkAzureCopy = @{
                Source          = $linkSource
                Destination     = @($linkAzureServer, $linkDestination)
                LinkedServer    = $linkAscii
                ExcludePassword = $true
                EnableException = $false
                Confirm         = $false
                WarningVariable = "linkAzureWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $linkAzureResult = @(Copy-DbaLinkedServer @splatLinkAzureCopy)
            $linkAzureResult.Count | Should -Be 1
            $linkAzureResult[0].Status | Should -BeExactly "Successful"
            ($linkAzureWarnings -join " ") | Should -Match ([regex]::Escape("Azure SQL Database not supported"))
            $linkDestination.LinkedServers.Refresh()
            $linkDestination.LinkedServers[$linkAscii] | Should -Not -BeNullOrEmpty
        } finally { $linkAzureServer.ConnectionContext.Disconnect() }
    }

    It "reuses the caller DAC and leaves it open" {
        $splatCallerDac = @{
            SqlInstance              = $linkSource
            DedicatedAdminConnection = $true
            EnableException          = $true
        }
        $linkCallerDac = Connect-DbaInstance @splatCallerDac
        try {
            $linkCallerDac.ConnectionContext.Connect()
            $linkCallerConnection = $linkCallerDac.ConnectionContext.SqlConnectionObject
            $linkCallerId = $linkCallerConnection.ClientConnectionId
            $splatCallerCopy = @{
                Source          = $linkCallerDac
                Destination     = $linkDestination
                LinkedServer    = $linkAscii
                Confirm         = $false
                EnableException = $true
            }
            $linkCallerOutput = @(Copy-DbaLinkedServer @splatCallerCopy)
            ($linkCallerOutput.Status | Select-Object -Unique) | Should -BeExactly "Successful"
            $linkCallerConnection.State | Should -Be "Open"
            $linkCallerConnection.ClientConnectionId | Should -Be $linkCallerId
        } finally { $linkCallerDac.ConnectionContext.Disconnect() }
        Get-NativeLinkedServerPassword $linkDestination $linkAscii $linkAsciiUser | Should -BeExactly $linkAsciiSecret
    }

    It "skips an existing linked server and replaces it with Force" -Tag NativeChecklist:switch-false {
        New-NativeLinkedServer -Server $linkDestination -Name $linkAscii -RemoteUser $linkAsciiUser -Password "NativeOriginal!123"
        $splatLinkReplace = @{
            Source          = $linkSource
            Destination     = $linkDestination
            LinkedServer    = $linkAscii
            Force           = $false
            Confirm         = $false
            EnableException = $false
        }
        $linkSkip = @(Copy-DbaLinkedServer @splatLinkReplace)
        $linkSkip.Count | Should -Be 1
        $linkSkip[0].Status | Should -BeExactly "Skipped"
        $linkSkip[0].Notes | Should -BeExactly "Already exists on destination"
        Get-NativeLinkedServerPassword $linkDestination $linkAscii $linkAsciiUser | Should -BeExactly "NativeOriginal!123"
        $splatLinkReplace.Force = $true
        $linkReplaced = @(Copy-DbaLinkedServer @splatLinkReplace)
        ($linkReplaced.Status | Select-Object -Unique) | Should -BeExactly "Successful"
        Get-NativeLinkedServerPassword $linkDestination $linkAscii $linkAsciiUser | Should -BeExactly $linkAsciiSecret
    }

    It "excludes passwords without accessing the host and honours both name filters" -Tag NativeChecklist:switch-false {
        $linkNoHostBefore = [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations
        $linkUnusedPassword = ConvertTo-SecureString "Unused!123" -AsPlainText -Force
        $linkUnusedCredential = New-Object Management.Automation.PSCredential("invalid\native_unused", $linkUnusedPassword)
        $splatLinkFilters = @{
            Source              = $linkSource
            Destination         = $linkDestination
            LinkedServer        = @($linkAscii, $linkUnicode)
            ExcludeLinkedServer = $linkUnicode
            Credential          = $linkUnusedCredential
            ExcludePassword     = $true
            UpgradeSqlClient    = $false
            Force               = $false
            Confirm             = $false
            EnableException     = $false
        }
        $linkFiltered = @(Copy-DbaLinkedServer @splatLinkFilters)
        $linkFiltered.Count | Should -Be 1
        $linkFiltered[0].Name | Should -BeExactly $linkAscii
        $linkFiltered[0].Type | Should -BeExactly "Linked Server"
        $linkFiltered[0].Status | Should -BeExactly "Successful"
        [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations | Should -Be $linkNoHostBefore
        $linkDestination.LinkedServers.Refresh()
        $linkDestination.LinkedServers[$linkAscii] | Should -Not -BeNullOrEmpty
        $linkDestination.LinkedServers[$linkUnicode] | Should -BeNullOrEmpty
    }

    It "leaves an existing linked server unchanged under Force WhatIf" -Tag NativeChecklist:whatif-confirm {
        New-NativeLinkedServer -Server $linkDestination -Name $linkAscii -RemoteUser $linkAsciiUser -Password "NativeWhatIf!123"
        $linkWhatIfId = $linkDestination.ConnectionContext.ExecuteScalar("SELECT server_id FROM sys.servers WHERE name = N'$linkAscii';")
        $splatLinkWhatIf = @{
            Source          = $linkSource
            Destination     = $linkDestination
            LinkedServer    = $linkAscii
            Force           = $true
            WhatIf          = $true
            Confirm         = $false
            EnableException = $true
        }
        @(Copy-DbaLinkedServer @splatLinkWhatIf).Count | Should -Be 0
        $linkDestination.ConnectionContext.ExecuteScalar("SELECT server_id FROM sys.servers WHERE name = N'$linkAscii';") | Should -Be $linkWhatIfId
        Get-NativeLinkedServerPassword $linkDestination $linkAscii $linkAsciiUser | Should -BeExactly "NativeWhatIf!123"
    }

    It "continues to the next destination when EnableException is false" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $linkWarnings = @()
        $splatLinkContinue = @{
            Source          = $linkSource
            Destination     = @($linkBadInstance, $linkDestination)
            LinkedServer    = $linkAscii
            ExcludePassword = $true
            EnableException = $false
            Confirm         = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "linkWarnings"
        }
        $linkContinued = @(Copy-DbaLinkedServer @splatLinkContinue)
        $linkContinued.Count | Should -Be 1
        $linkContinued[0].Status | Should -BeExactly "Successful"
        $linkWarnings | Should -Not -BeNullOrEmpty
        $linkDestination.LinkedServers.Refresh()
        $linkDestination.LinkedServers[$linkAscii] | Should -Not -BeNullOrEmpty
    }

    It "terminates a failed source connection with EnableException" -Tag NativeChecklist:enable-exception {
        $splatLinkThrow = @{
            Source          = $linkBadInstance
            Destination     = $linkDestination
            LinkedServer    = $linkAscii
            ExcludePassword = $true
            EnableException = $true
            Confirm         = $false
        }
        { Copy-DbaLinkedServer @splatLinkThrow } | Should -Throw
    }
}
