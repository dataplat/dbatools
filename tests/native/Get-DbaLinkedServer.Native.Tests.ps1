#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command declares [CmdletBinding()] without SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaLinkedServer" -Tag IntegrationTests {
    BeforeAll {
        $lsServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        # Unique per leg and run (lane-safe); AfterAll drops what this file creates.
        $lsTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $lsMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $lsSelf = "dbatoolsci_ls_${lsTag}_self"
        $lsMapped = "dbatoolsci_ls_${lsTag}_mapped"
        $lsBare = "dbatoolsci_ls_${lsTag}_bare"
        $lsNetName = "dbatoolsci_net_${lsTag}"
        $lsLogin = "dbatoolsci_ls_${lsTag}_login"
        $lsRemoteUser = "dbatoolsci_remote_${lsTag}"
        $lsNames = @($lsSelf, $lsMapped, $lsBare)
        $lsDisplay = "ComputerName,InstanceName,SqlInstance,Name,RemoteServer,ProductName,Impersonate,RemoteUser,Publisher,Distributor,DateLastModified"

        # A linked server with the default self mapping (one login, impersonating); one with the self mapping and a mapped
        # login (two logins) under another network name; one with no login at all.
        $loginPassword = "Ls-" + [guid]::NewGuid().ToString("N")
        $null = $lsServer.Query("CREATE LOGIN [$lsLogin] WITH PASSWORD = N'$loginPassword', CHECK_POLICY = OFF;")
        foreach ($name in $lsNames) {
            $null = $lsServer.Query("EXEC master.dbo.sp_addlinkedserver @server = N'$name', @srvproduct = N'SQL Server';")
        }
        $null = $lsServer.Query("EXEC master.dbo.sp_setnetname @server = N'$lsMapped', @netname = N'$lsNetName';")
        $null = $lsServer.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$lsMapped', @useself = N'False', @locallogin = N'$lsLogin', @rmtuser = N'$lsRemoteUser', @rmtpassword = N'Remote-$lsTag';")
        $null = $lsServer.Query("EXEC master.dbo.sp_droplinkedsrvlogin @rmtsrvname = N'$lsBare', @locallogin = NULL;")

        # Independent read on the test's own connection: the linked servers and their logins in the catalog.
        function Get-NativeLinkedCatalog {
            param($Server)
            @($Server.Query("SELECT s.name, s.data_source, s.product FROM sys.servers AS s WHERE s.is_linked = 1;"))
        }
        function Get-NativeLinkedLogin {
            param($Server, [string]$Name)
            @($Server.Query("SELECT l.uses_self_credential, l.remote_name FROM sys.linked_logins AS l INNER JOIN sys.servers AS s ON s.server_id = l.server_id WHERE s.name = N'$Name';"))
        }

        function Assert-NativeLinkedShape {
            param($Row, $Server)
            $Row.PSObject.BaseObject | Should -BeOfType [Microsoft.SqlServer.Management.Smo.LinkedServer]
            ($Row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $lsDisplay
            $Row.ComputerName | Should -BeExactly $Server.ComputerName
            $Row.InstanceName | Should -BeExactly $Server.ServiceName
            $Row.SqlInstance | Should -BeExactly $Server.DomainInstanceName
            $Row.RemoteServer | Should -BeExactly $Row.DataSource
            $Row.Publisher | Should -Be $Row.DistPublisher
            $Row.PSObject.Properties["RemoteServer"].MemberType | Should -Be "AliasProperty"
            $Row.PSObject.Properties["Publisher"].MemberType | Should -Be "AliasProperty"
        }
    }

    AfterAll {
        foreach ($name in $lsNames) {
            $null = $lsServer.Query("IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'$name') EXEC master.dbo.sp_dropserver @server = N'$name', @droplogins = 'droplogins';")
        }
        $null = $lsServer.Query("IF SUSER_ID(N'$lsLogin') IS NOT NULL DROP LOGIN [$lsLogin];")
    }

    Context "Results" {
        It "returns every linked server of the catalog as the SMO object, decorated as the pin decorates it" {
            $catalog = Get-NativeLinkedCatalog $lsServer
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -ErrorVariable lsErrors)
            $catalogAfter = Get-NativeLinkedCatalog $lsServer
            $lsErrors | Should -BeNullOrEmpty
            # Another lane may add or drop its own linked servers meanwhile: every name in both reads comes back, and nothing
            # outside them does.
            $resultNames = @($results.Name)
            @($catalog.name | Where-Object { $PSItem -in $catalogAfter.name -and $PSItem -notin $resultNames }) | Should -BeNullOrEmpty
            @($resultNames | Where-Object { $PSItem -notin $catalog.name -and $PSItem -notin $catalogAfter.name }) | Should -BeNullOrEmpty
            foreach ($name in $lsNames) {
                @($results | Where-Object Name -eq $name).Count | Should -Be 1
            }
            foreach ($result in $results) {
                Assert-NativeLinkedShape -Row $result -Server $lsServer
            }
        }

        It "gives the remote server from the data source and the product from the catalog" {
            $catalog = Get-NativeLinkedCatalog $lsServer
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lsSelf, $lsMapped)
            $mapped = @($results | Where-Object Name -eq $lsMapped)
            $self = @($results | Where-Object Name -eq $lsSelf)
            $mapped.Count | Should -Be 1
            $self.Count | Should -Be 1
            $mapped[0].RemoteServer | Should -BeExactly $lsNetName
            $mapped[0].RemoteServer | Should -BeExactly ($catalog | Where-Object name -eq $lsMapped).data_source
            $self[0].RemoteServer | Should -BeExactly $lsSelf
            $self[0].ProductName | Should -BeExactly ($catalog | Where-Object name -eq $lsSelf).product
        }

        It "gives one login's Impersonate and RemoteUser as values, two logins' as arrays, and none for no login" {
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lsNames)
            $self = @($results | Where-Object Name -eq $lsSelf)[0]
            $mapped = @($results | Where-Object Name -eq $lsMapped)[0]
            $bare = @($results | Where-Object Name -eq $lsBare)[0]

            @(Get-NativeLinkedLogin $lsServer $lsSelf).Count | Should -Be 1
            $self.Impersonate | Should -BeOfType [bool]
            $self.Impersonate | Should -BeTrue

            $mappedLogins = Get-NativeLinkedLogin $lsServer $lsMapped
            $mappedLogins.Count | Should -Be 2
            , $mapped.Impersonate | Should -BeOfType [object[]]
            @($mapped.Impersonate | Sort-Object) | Should -Be @($false, $true)
            , $mapped.RemoteUser | Should -BeOfType [object[]]
            $mapped.RemoteUser.Count | Should -Be 2
            $mapped.RemoteUser | Should -Contain $lsRemoteUser

            @(Get-NativeLinkedLogin $lsServer $lsBare).Count | Should -Be 0
            $null -eq $bare.Impersonate | Should -BeTrue
            $null -eq $bare.RemoteUser | Should -BeTrue
        }

        It "decorates a linked server again when the same server object is read twice" {
            $first = @(Get-DbaLinkedServer -SqlInstance $lsServer -LinkedServer $lsSelf -ErrorVariable firstErrors)
            $second = @(Get-DbaLinkedServer -SqlInstance $lsServer -LinkedServer $lsSelf -ErrorVariable secondErrors)
            $firstErrors | Should -BeNullOrEmpty
            $secondErrors | Should -BeNullOrEmpty
            $first.Count | Should -Be 1
            $second.Count | Should -Be 1
            Assert-NativeLinkedShape -Row $second[0] -Server $lsServer
            @($second[0].PSObject.Properties.Name | Where-Object { $PSItem -eq "Impersonate" }).Count | Should -Be 1
        }
    }

    Context "Filters" {
        It "selects -LinkedServer names exactly, ignoring case" {
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lsSelf.ToUpperInvariant())
            @($results.Name) | Should -Be @($lsSelf)
        }

        It "compares -LinkedServer as -in does, with no wildcard" {
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer "dbatoolsci_ls_${lsTag}_*")
            $results.Count | Should -Be 0
        }

        It "leaves out -ExcludeLinkedServer names" {
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -ExcludeLinkedServer $lsSelf, $lsMapped.ToUpperInvariant())
            @($results | Where-Object Name -in $lsSelf, $lsMapped) | Should -BeNullOrEmpty
            @($results | Where-Object Name -eq $lsBare).Count | Should -Be 1
        }

        It "applies -LinkedServer and -ExcludeLinkedServer together" {
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer $lsNames -ExcludeLinkedServer $lsBare)
            @($results.Name | Sort-Object) | Should -Be @(@($lsSelf, $lsMapped) | Sort-Object)
        }

        It "reads every linked server for a -LinkedServer value that is false, as the pinned if does" {
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer "")
            foreach ($name in $lsNames) {
                @($results | Where-Object Name -eq $name).Count | Should -Be 1
            }
        }
    }

    Context "Instances" {
        It "reads each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $warnings = @()
            $results = @(@($TestConfig.InstanceSingle, $lsMissing, $TestConfig.InstanceSingle) | Get-DbaLinkedServer -LinkedServer $lsSelf -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            @($results.Name) | Should -Be @($lsSelf, $lsSelf)
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaLinkedServer] Failure | Error connecting to [$lsMissing]: "))
        }

        It "reads several named instances" {
            $results = @(Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle -LinkedServer $lsMapped)
            @($results.Name) | Should -Be @($lsMapped, $lsMapped)
        }

        It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            try {
                $null = Get-DbaLinkedServer -SqlInstance $lsMissing, $TestConfig.InstanceSingle -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Every leg shares this instance at once, so this context creates nothing: it reads the linked servers as they are
            # and compares them with the catalog, read on the test's own SQL-login connection before and after.
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $loginCatalog = Get-NativeLinkedCatalog $loginServer
            $result = @(Get-DbaLinkedServer -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException -ErrorVariable loginErrors)
            $loginCatalogAfter = Get-NativeLinkedCatalog $loginServer
            $loginErrors | Should -BeNullOrEmpty
            $resultNames = @($result.Name)
            @($loginCatalog.name | Where-Object { $PSItem -in $loginCatalogAfter.name -and $PSItem -notin $resultNames }) | Should -BeNullOrEmpty
            @($resultNames | Where-Object { $PSItem -notin $loginCatalog.name -and $PSItem -notin $loginCatalogAfter.name }) | Should -BeNullOrEmpty
            foreach ($row in $result) {
                Assert-NativeLinkedShape -Row $row -Server $loginServer
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaLinkedServer -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaLinkedServer -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # Linked servers aren't available in Azure SQL Database:
            # https://learn.microsoft.com/sql/relational-databases/linked-servers/linked-servers-database-engine
            # There the SMO LinkedServers getter throws UnsupportedVersionException and PowerShell's read of it gives $null with no
            # error, so the pin lists nothing and reports nothing, plain or under -EnableException (evidence
            # pin-azure-linkedserver-20261106.txt and pin-azure-lsgetter-20261106.txt, both editions); the port refuses it
            # (correction azure-unsupported).
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    # A paused database resumes: 40613, a connection timeout (-2, 258 or the wait timing out) or a TimeoutException.
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2, 258 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        if ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        # Correction azure-unsupported: the pin's silent empty result reads as "no linked servers" for an engine that has none
        # to read; the port refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does.
        It "refuses Azure SQL Database with the connection warning and returns nothing" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            # Independent read: SMO itself refuses the linked servers of this engine.
            $getterFault = $null
            try {
                $null = [Microsoft.SqlServer.Management.Smo.Server].GetProperty("LinkedServers").GetValue($azure.PSObject.BaseObject, $null)
            } catch {
                $getterFault = $PSItem.Exception.InnerException
            }
            $getterFault | Should -BeOfType [Microsoft.SqlServer.Management.Smo.UnsupportedVersionException]

            $azureWarnings = @()
            $azureErrors = @()
            $azurePriorErrors = @($global:Error)
            @(Get-DbaLinkedServer -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors).Count | Should -Be 0
            $azureAddedErrors = @($global:Error | Where-Object { $azurePriorErrors -notcontains $PSItem })
            $azureWarnings.Count | Should -Be 1
            $azureWarnings[0].Message | Should -Match ([regex]::Escape("[Get-DbaLinkedServer] Failure | Azure SQL Database not supported") + '$')

            # The shared connection refusal's record, as Get-DbaInstanceAuditSpecification's port probe 55498c70 measured it on
            # both editions: one record, the same object in -ErrorVariable and in $Error, the target the server name the input
            # shows in brackets.
            $azureErrors.Count | Should -Be 1
            $azureAddedErrors.Count | Should -Be 1
            [object]::ReferenceEquals($azureAddedErrors[0], $azureErrors[0]) | Should -BeTrue
            $azureRecord = $azureErrors[0]
            $azureRecord.FullyQualifiedErrorId | Should -BeExactly "dbatools_Get-DbaLinkedServer"
            "$($azureRecord.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $azureRecord.CategoryInfo.Reason | Should -BeExactly "Exception"
            $azureRecord.TargetObject | Should -BeOfType [System.String]
            ("[" + $azureRecord.TargetObject + "]") | Should -BeExactly "$azure"
            $azureRecord.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $azureRecord.Exception.Message | Should -BeExactly "Azure SQL Database not supported"
            $azureRecord.Exception.InnerException | Should -Not -BeNullOrEmpty
            $azureRecord.Exception.InnerException.Message | Should -BeExactly "Azure SQL Database not supported"
        }

        It "refuses Azure SQL Database and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            $rows = @(Get-DbaLinkedServer -SqlInstance $azure, $lsServer -LinkedServer $lsSelf -WarningAction SilentlyContinue -WarningVariable azureWarnings)
            $azureWarnings.Count | Should -Be 1
            $azureWarnings[0].Message | Should -Match ([regex]::Escape("[Get-DbaLinkedServer] Failure | Azure SQL Database not supported") + '$')
            @($rows.Name) | Should -Be @($lsSelf)
            $rows[0].SqlInstance | Should -BeExactly $lsServer.DomainInstanceName
        }

        It "throws the connection refusal for Azure SQL Database under -EnableException" {
            $azureCaught = $null
            try {
                $null = Get-DbaLinkedServer -SqlInstance $azure, $lsServer -EnableException -WarningAction SilentlyContinue
            } catch {
                $azureCaught = $PSItem
            }
            $azureCaught | Should -Not -BeNullOrEmpty
            $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $azureCaught.Exception.ToString() | Should -BeLike "*Azure SQL Database not supported*"
        }
    }
}
