#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- the pinned command has no pipeline parameter; destination arrays are covered.
# NativeChecklist: azure-sqldb N/A -- server-scoped credentials are unavailable on Azure SQL Database; refuse with AzureUnsupported. https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#t-sql-syntax-not-supported-in-azure-sql-database
# NativeChecklist: sql-login N/A -- the pin declares SourceSqlCredential and DestinationSqlCredential, but no SqlCredential parameter.

Describe "Native Copy-DbaCredential" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $credentialSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $credentialDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $credentialPrefix = "native_credential_" + [guid]::NewGuid().ToString("N")
        $credentialNames = @("${credentialPrefix}_ascii", "${credentialPrefix}_unicode ]'", "${credentialPrefix}_second")
        $credentialSecrets = @("NativeAscii!123", ([char]0x6f22).ToString() + "Native'!" + ([char]0x5b57).ToString(), "NativeSecond!123")
        $credentialIdentities = @("sa", "sa", "native_second_identity")
        $credentialBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        for ($credentialIndex = 0; $credentialIndex -lt $credentialNames.Count; $credentialIndex++) {
            $credentialFixture = New-Object Microsoft.SqlServer.Management.Smo.Credential($credentialSource, $credentialNames[$credentialIndex])
            $credentialFixture.Create($credentialIdentities[$credentialIndex], $credentialSecrets[$credentialIndex])
        }
        function Get-NativeCredentialSecret {
            param($Server, [string]$Name)
            $secretDac = $null
            $secretSet = $null
            try {
                $splatSecretDac = @{
                    SqlInstance              = $Server
                    DedicatedAdminConnection = $true
                    EnableException          = $true
                }
                $secretDac = Connect-DbaInstance @splatSecretDac
                $secretSet = [Dataplat.Dbatools.Connection.SqlCredentialSecrets]::Read($secretDac, $null, [Threading.CancellationToken]::None)
                $secretCredential = New-Object System.Net.NetworkCredential("", $secretSet.GetSecret($Name))
                $secretCredential.Password
            } finally {
                if ($secretSet) { $secretSet.Dispose() }
                if ($secretDac) { $secretDac.ConnectionContext.Disconnect() }
            }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        $credentialDestination.Credentials.Refresh()
        foreach ($credentialCleanupName in $credentialNames) {
            $credentialCleanup = $credentialDestination.Credentials[$credentialCleanupName]
            if ($credentialCleanup) { $credentialCleanup.Drop() }
        }
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($credentialCleanupServer in @($credentialSource, $credentialDestination)) {
            $credentialCleanupServer.Credentials.Refresh()
            foreach ($credentialFinalName in $credentialNames) {
                $credentialFinal = $credentialCleanupServer.Credentials[$credentialFinalName]
                if ($credentialFinal) { $credentialFinal.Drop() }
            }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "preserves the entire Unicode secret through the remote host path" {
        $credentialPhysicalHost = $credentialSource.ConnectionContext.ExecuteScalar("SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'));")
        $credentialPhysicalHost | Should -Not -Be $env:COMPUTERNAME
        $credentialRemoteBefore = [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations
        $credentialLocalBefore = [Dataplat.Dbatools.Connection.HostProtectedData]::LocalOperations
        $splatUnicodeCopy = @{
            Source          = $credentialSource
            Destination     = $credentialDestination
            Name            = $credentialNames[1]
            Confirm         = $false
            EnableException = $true
        }
        $credentialUnicodeOutput = @(Copy-DbaCredential @splatUnicodeCopy)
        $credentialUnicodeOutput.Count | Should -Be 1
        $credentialUnicodeOutput[0].Status | Should -Be "Successful"
        [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations | Should -BeGreaterThan $credentialRemoteBefore
        [Dataplat.Dbatools.Connection.HostProtectedData]::LocalOperations | Should -Be $credentialLocalBefore
        Get-NativeCredentialSecret $credentialDestination $credentialNames[1] | Should -BeExactly $credentialSecrets[1]
        $credentialDestination.Credentials.Refresh()
        $credentialDestination.Credentials[$credentialNames[1]].Identity | Should -BeExactly "sa"
        ($credentialUnicodeOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "DateTime,SourceServer,DestinationServer,Name,Type,Status,Notes"
        $credentialUnicodeOutput[0].PSObject.TypeNames | Should -Contain "dbatools.MigrationObject"
    }

    It "treats provider-name SQL syntax as data" {
        # This is the production provider lookup against the real catalog; no EKM DLL is
        # needed to prove that an unregistered name cannot inject a fabricated enabled row.
        $credentialProviderName = "${credentialPrefix}' UNION ALL SELECT CAST(1 AS bit)--"
        [Dataplat.Dbatools.Connection.SqlCredentialSecrets]::HasEnabledProvider($credentialDestination, $credentialProviderName) | Should -BeFalse
    }

    It "uses local DPAPI when the protected data belongs to this host" {
        Add-Type -AssemblyName System.Security
        $credentialLocalPlain = [byte[]](11, 22, 33, 44, 55, 66)
        $credentialLocalEntropy = [byte[]](1, 2, 3, 4)
        $credentialLocalEncrypted = [Security.Cryptography.ProtectedData]::Protect($credentialLocalPlain, $credentialLocalEntropy, [Security.Cryptography.DataProtectionScope]::LocalMachine)
        $credentialLocalCount = [Dataplat.Dbatools.Connection.HostProtectedData]::LocalOperations
        $credentialRemoteCount = [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations
        $credentialLocalResult = $null
        try {
            $credentialLocalResult = [Dataplat.Dbatools.Connection.HostProtectedData]::Unprotect($env:COMPUTERNAME, $credentialLocalEncrypted, $credentialLocalEntropy, $null, [Threading.CancellationToken]::None)
            [Convert]::ToBase64String($credentialLocalResult) | Should -BeExactly ([Convert]::ToBase64String($credentialLocalPlain))
            [Dataplat.Dbatools.Connection.HostProtectedData]::LocalOperations | Should -Be ($credentialLocalCount + 1)
            [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations | Should -Be $credentialRemoteCount
        } finally {
            if ($credentialLocalResult) { [array]::Clear($credentialLocalResult, 0, $credentialLocalResult.Length) }
            [array]::Clear($credentialLocalPlain, 0, $credentialLocalPlain.Length)
            [array]::Clear($credentialLocalEncrypted, 0, $credentialLocalEncrypted.Length)
        }
    }

    It "reuses the caller DAC and leaves it open" {
        $splatCallerDac = @{
            SqlInstance              = $credentialSource
            DedicatedAdminConnection = $true
            EnableException          = $true
        }
        $credentialCallerDac = Connect-DbaInstance @splatCallerDac
        try {
            $credentialCallerDac.ConnectionContext.Connect()
            $credentialCallerConnection = $credentialCallerDac.ConnectionContext.SqlConnectionObject
            $credentialCallerId = $credentialCallerConnection.ClientConnectionId
            $splatCallerCopy = @{
                Source          = $credentialCallerDac
                Destination     = $credentialDestination
                Name            = $credentialNames[0]
                Confirm         = $false
                EnableException = $true
            }
            $credentialCallerOutput = @(Copy-DbaCredential @splatCallerCopy)
            $credentialCallerOutput[0].Status | Should -Be "Successful"
            $credentialCallerConnection.State | Should -Be "Open"
            $credentialCallerConnection.ClientConnectionId | Should -Be $credentialCallerId
        } finally { $credentialCallerDac.ConnectionContext.Disconnect() }
        Get-NativeCredentialSecret $credentialDestination $credentialNames[0] | Should -BeExactly $credentialSecrets[0]
    }

    It "preserves skipped credentials and replaces them with Force" -Tag NativeChecklist:switch-false {
        $credentialExisting = New-Object Microsoft.SqlServer.Management.Smo.Credential($credentialDestination, $credentialNames[0])
        $credentialExisting.Create("old_identity", "NativeOriginal!123")
        $splatCredentialReplace = @{
            Source          = $credentialSource
            Destination     = $credentialDestination
            Name            = $credentialNames[0]
            Force           = $false
            Confirm         = $false
            EnableException = $false
        }
        $credentialSkip = @(Copy-DbaCredential @splatCredentialReplace)
        $credentialSkip[0].Status | Should -Be "Skipping"
        $credentialSkip[0].Notes | Should -Be "Already exists on destination"
        Get-NativeCredentialSecret $credentialDestination $credentialNames[0] | Should -BeExactly "NativeOriginal!123"
        $splatCredentialReplace.Force = $true
        $credentialReplaced = @(Copy-DbaCredential @splatCredentialReplace)
        $credentialReplaced[0].Status | Should -Be "Successful"
        Get-NativeCredentialSecret $credentialDestination $credentialNames[0] | Should -BeExactly $credentialSecrets[0]
    }

    It "excludes passwords without accessing the host and preserves exact filters" -Tag NativeChecklist:switch-false {
        $credentialNoHostBefore = [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations
        $credentialUnusedPassword = ConvertTo-SecureString "Unused!123" -AsPlainText -Force
        $credentialUnused = New-Object Management.Automation.PSCredential("invalid\\native_unused", $credentialUnusedPassword)
        $splatCredentialFilters = @{
            Source          = $credentialSource
            Destination     = $credentialDestination
            Name            = $credentialNames
            ExcludeName     = $credentialNames[1]
            Identity        = @("sa", "native_second_identity")
            ExcludeIdentity = "native_second_identity"
            Credential      = $credentialUnused
            ExcludePassword = $true
            Force           = $false
            Confirm         = $false
            EnableException = $false
        }
        $credentialFiltered = @(Copy-DbaCredential @splatCredentialFilters)
        $credentialFiltered.Count | Should -Be 1
        $credentialFiltered[0].Name | Should -BeExactly $credentialNames[0]
        $credentialFiltered[0].Status | Should -Be "Successful"
        [Dataplat.Dbatools.Connection.HostProtectedData]::RemoteOperations | Should -Be $credentialNoHostBefore
        $credentialDestination.Credentials.Refresh()
        foreach ($credentialExcluded in $credentialNames[1..2]) {
            $credentialDestination.Credentials[$credentialExcluded] | Should -BeNullOrEmpty
        }
    }

    It "leaves an existing credential unchanged under Force WhatIf" -Tag NativeChecklist:whatif-confirm {
        $credentialWhatIfExisting = New-Object Microsoft.SqlServer.Management.Smo.Credential($credentialDestination, $credentialNames[0])
        $credentialWhatIfExisting.Create("old_identity", "NativeWhatIf!123")
        $credentialWhatIfId = $credentialWhatIfExisting.ID
        $splatCredentialWhatIf = @{
            Source          = $credentialSource
            Destination     = $credentialDestination
            Name            = $credentialNames[0]
            Force           = $true
            WhatIf          = $true
            Confirm         = $false
            EnableException = $true
        }
        @(Copy-DbaCredential @splatCredentialWhatIf).Count | Should -Be 0
        $credentialDestination.Credentials.Refresh()
        $credentialDestination.Credentials[$credentialNames[0]].ID | Should -Be $credentialWhatIfId
        $credentialDestination.Credentials[$credentialNames[0]].Identity | Should -BeExactly "old_identity"
        Get-NativeCredentialSecret $credentialDestination $credentialNames[0] | Should -BeExactly "NativeWhatIf!123"
    }

    It "continues to the next destination when EnableException is false" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $credentialWarnings = @()
        $splatCredentialContinue = @{
            Source          = $credentialSource
            Destination     = @($credentialBadInstance, $credentialDestination)
            Name            = $credentialNames[0]
            ExcludePassword = $true
            EnableException = $false
            Confirm         = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "credentialWarnings"
        }
        $credentialContinued = @(Copy-DbaCredential @splatCredentialContinue)
        $credentialContinued.Count | Should -Be 1
        $credentialContinued[0].Status | Should -Be "Successful"
        $credentialWarnings | Should -Not -BeNullOrEmpty
        $credentialDestination.Credentials.Refresh()
        $credentialDestination.Credentials[$credentialNames[0]].Identity | Should -BeExactly "sa"
    }

    It "refuses an Azure destination and continues copying to the next destination" -Tag NativeChecklist:multi-instance-failure {
        $splatCredentialAzure = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $credentialAzureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $credentialAzureServer = Connect-DbaInstance @splatCredentialAzure
                break
            } catch {
                $azureError = $_.Exception
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
            $credentialAzureServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $credentialAzureWarnings = @()
            $splatCredentialAzureCopy = @{
                Source = $credentialSource
                Destination = @($credentialAzureServer, $credentialDestination)
                Name = $credentialNames[0]
                ExcludePassword = $true
                EnableException = $false
                Confirm = $false
                WarningVariable = 'credentialAzureWarnings'
                WarningAction = 'SilentlyContinue'
            }
            $credentialAzureResult = @(Copy-DbaCredential @splatCredentialAzureCopy)
            $credentialAzureResult.Count | Should -Be 1
            $credentialAzureResult[0].Status | Should -Be 'Successful'
            ($credentialAzureWarnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            $credentialDestination.Credentials.Refresh()
            $credentialDestination.Credentials[$credentialNames[0]].Identity | Should -BeExactly 'sa'
        } finally { $credentialAzureServer.ConnectionContext.Disconnect() }
    }

    It "terminates a failed source connection with EnableException" -Tag NativeChecklist:enable-exception {
        $splatCredentialThrow = @{
            Source          = $credentialBadInstance
            Destination     = $credentialDestination
            Name            = $credentialNames[0]
            ExcludePassword = $true
            EnableException = $true
            Confirm         = $false
        }
        { Copy-DbaCredential @splatCredentialThrow } | Should -Throw
    }
}
