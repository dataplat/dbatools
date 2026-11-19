#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentProxy",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.
# SQL Server Agent proxy accounts are unavailable on Azure SQL Database: https://learn.microsoft.com/ssms/agent/sql-server-agent

Describe "Get-DbaAgentProxy native behavior" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeProxyPrefix = "native_proxy_$([Guid]::NewGuid().ToString("N"))"
        $nativeProxyNames = @("${nativeProxyPrefix}_a", "${nativeProxyPrefix}_b")
        $nativeCredentialName = "native_credential_$([Guid]::NewGuid().ToString("N"))"
        $nativeIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $nativePassword = ConvertTo-SecureString ([Guid]::NewGuid().ToString("N")) -AsPlainText -Force
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $splatNativeCredential = @{
            SqlInstance = $TestConfig.InstanceSingle
            Name        = $nativeCredentialName
            Identity    = $nativeIdentity
            Password    = $nativePassword
        }
        $null = New-DbaCredential @splatNativeCredential
        foreach ($nativeProxyName in $nativeProxyNames) {
            $splatNativeProxy = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Name            = $nativeProxyName
                ProxyCredential = $nativeCredentialName
            }
            $null = New-DbaAgentProxy @splatNativeProxy
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        # Cleanup uses SMO directly so a retrieval regression cannot strand this file's fixtures.
        $nativeCleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $nativeCleanupServer.JobServer.ProxyAccounts.Refresh()
        foreach ($nativeCleanupName in $nativeProxyNames) {
            $nativeCleanupProxy = $nativeCleanupServer.JobServer.ProxyAccounts[$nativeCleanupName]
            if ($null -ne $nativeCleanupProxy) { $nativeCleanupProxy.Drop() }
        }
        $nativeCleanupServer.Credentials.Refresh()
        $nativeCleanupCredential = $nativeCleanupServer.Credentials[$nativeCredentialName]
        if ($null -ne $nativeCleanupCredential) { $nativeCleanupCredential.Drop() }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "preserves wildcard order, duplicate matches, exclusions and SMO output" {
        $splatNativeFilters = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Proxy           = @($nativeProxyNames[1], "${nativeProxyPrefix}_*")
            ExcludeProxy    = $nativeProxyNames[0]
            EnableException = $true
        }
        $nativeFiltered = @(Get-DbaAgentProxy @splatNativeFilters)
        $nativeFiltered.Count | Should -Be 2
        $nativeFiltered[0].Name | Should -BeExactly $nativeProxyNames[1]
        $nativeFiltered[1].Name | Should -BeExactly $nativeProxyNames[1]
        $nativeFiltered[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount
        $nativeFiltered[0].ComputerName | Should -Not -BeNullOrEmpty
        $nativeFiltered[0].InstanceName | Should -Not -BeNullOrEmpty
        $nativeFiltered[0].SqlInstance | Should -Not -BeNullOrEmpty
        $nativeDisplay = @($nativeFiltered[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        ($nativeDisplay -join ",") | Should -BeExactly "ComputerName,SqlInstance,InstanceName,Name,ID,CredentialID,CredentialIdentity,CredentialName,Description,IsEnabled"
    }

    It "materializes inclusion and exclusion results before downstream proxy deletion" {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        foreach ($mode in 'Include', 'Exclude') {
            $prefix = "native_proxy_drop_$([guid]::NewGuid().ToString('N'))"
            $names = @("${prefix}_a", "${prefix}_b", "${prefix}_keep")
            try {
                foreach ($name in $names) {
                    $proxy = New-Object Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount($server.JobServer, $name, $nativeCredentialName, $false)
                    $proxy.Create()
                }
                $server.JobServer.ProxyAccounts.Refresh()
                $parameters = @{ SqlInstance = $server; EnableException = $true }
                if ($mode -eq 'Include') {
                    $parameters.Proxy = @($names[0], $names[1])
                } else {
                    # Exclude every account except these two private fixtures.
                    # This exercises the exclusion-only branch without dropping another test's proxy.
                    $parameters.ExcludeProxy = @($server.JobServer.ProxyAccounts | Where-Object Name -NotIn $names[0..1] | ForEach-Object {
                        [System.Management.Automation.WildcardPattern]::Escape($_.Name)
                    })
                }
                $deleted = New-Object 'System.Collections.Generic.List[string]'
                Get-DbaAgentProxy @parameters | ForEach-Object {
                    $deleted.Add($_.Name)
                    $_.Drop()
                }
                $deleted.Count | Should -Be 2
                ($deleted -join ',') | Should -BeExactly ($names[0..1] -join ',')
                $server.JobServer.ProxyAccounts.Refresh()
                $server.JobServer.ProxyAccounts[$names[0]] | Should -BeNullOrEmpty
                $server.JobServer.ProxyAccounts[$names[1]] | Should -BeNullOrEmpty
                $server.JobServer.ProxyAccounts[$names[2]] | Should -Not -BeNullOrEmpty
            } finally {
                $server.JobServer.ProxyAccounts.Refresh()
                foreach ($name in $names) {
                    $cleanup = $server.JobServer.ProxyAccounts[$name]
                    if ($null -ne $cleanup) { $cleanup.Drop() }
                }
            }
        }
    }

    It "treats an explicitly empty inclusion list as no matches" {
        $splatNativeEmpty = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Proxy           = @()
            EnableException = $true
        }
        @(Get-DbaAgentProxy @splatNativeEmpty).Count | Should -Be 0
    }

    It "warns for a failed middle record and continues without reusing earlier output" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $splatNativeContinue = @{
            Proxy           = $nativeProxyNames[0]
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeContinued = @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle | Get-DbaAgentProxy @splatNativeContinue)
        $nativeContinued.Count | Should -Be 2
        $nativeContinued[0].Name | Should -BeExactly $nativeProxyNames[0]
        $nativeContinued[1].Name | Should -BeExactly $nativeProxyNames[0]
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "streams the first result before EnableException terminates on the failed middle record" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        $splatNativeThrow = @{
            Proxy           = $nativeProxyNames[0]
            EnableException = $true
        }
        try {
            $TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle |
                Get-DbaAgentProxy @splatNativeThrow |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeStreamed[0].Name | Should -BeExactly $nativeProxyNames[0]
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.Exception | Should -BeOfType System.Exception
        $nativeCaught.TargetObject.GetType().FullName | Should -BeExactly "System.String"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaAgentProxy SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $loginProxyName = "native_proxy_login_$([guid]::NewGuid().ToString("N"))"
        $loginCredentialName = "${loginProxyName}_credential"
        $splatLoginConnection = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        $loginProxyServer = Connect-DbaInstance @splatLoginConnection
        $loginCredential = New-Object Microsoft.SqlServer.Management.Smo.Credential($loginProxyServer, $loginCredentialName)
        # This credential is metadata only; no job uses it.
        $loginCredential.Create("sa", [guid]::NewGuid().ToString("N"))
        $loginProxy = New-Object Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount($loginProxyServer.JobServer, $loginProxyName, $loginCredentialName, $false)
        $loginProxy.Create()
    }

    AfterAll {
        if ($null -ne $loginProxyServer) {
            $loginProxyServer.JobServer.ProxyAccounts.Refresh()
            $loginProxyCleanup = $loginProxyServer.JobServer.ProxyAccounts[$loginProxyName]
            if ($null -ne $loginProxyCleanup) { $loginProxyCleanup.Drop() }
            $loginProxyServer.Credentials.Refresh()
            $loginCredentialCleanup = $loginProxyServer.Credentials[$loginCredentialName]
            if ($null -ne $loginCredentialCleanup) { $loginCredentialCleanup.Drop() }
        }
    }

    It "returns the requested proxy with SQL credentials" {
        $splatLoginProxy = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            Proxy           = $loginProxyName
            EnableException = $true
        }
        $loginProxyOutput = @(Get-DbaAgentProxy @splatLoginProxy)
        $loginProxyOutput.Count | Should -Be 1
        $loginProxyOutput[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount
        $loginProxyOutput[0].Name | Should -BeExactly $loginProxyName
        $loginProxyOutput[0].CredentialName | Should -BeExactly $loginCredentialName
        $loginProxyOutput[0].IsEnabled | Should -BeFalse
    }

    It "warns without output when SQL credentials are omitted" {
        $loginProxyWarnings = @()
        $splatLoginProxyDenied = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Proxy           = $loginProxyName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "loginProxyWarnings"
        }
        # Pin public/Get-DbaAgentProxy.ps1:94-98, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        @(Get-DbaAgentProxy @splatLoginProxyDenied).Count | Should -Be 0
        $loginProxyWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # The pinned function catches its Connect-DbaInstance failure and invokes Stop-Function directly.
        $splatLoginProxyThrow = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Proxy           = $loginProxyName
            EnableException = $true
        }
        # Pin public/Get-DbaAgentProxy.ps1:94-98, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        { Get-DbaAgentProxy @splatLoginProxyThrow } | Should -Throw
    }
}

Describe "Get-DbaAgentProxy Azure SQL Database" -Tag IntegrationTests {
    It "refuses Azure SQL Database before enumerating Agent proxies" -Tag NativeChecklist:azure-sqldb {
        $azure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $resuming = $false
                for ($failure = $_.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in 40613, -2 -or $failure -is [System.TimeoutException] -or $failure.Message -match 'timed out|timeout|wait operation') { $resuming = $true }
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            @(Get-DbaAgentProxy -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match 'Azure SQL Database not supported'
            { Get-DbaAgentProxy -SqlInstance $azure -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally { $azure.ConnectionContext.Disconnect() }
    }
}
