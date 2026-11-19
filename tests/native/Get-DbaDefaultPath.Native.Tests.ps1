#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDefaultPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.
# NativeChecklist: azure-sqldb N/A -- upstream connects with Connect-DbaInstance -AzureUnsupported, which refuses Azure SQL Database; the command reads instance-level default file, backup and error log directories.
Describe "Native default path behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativePathServer = $null
        $nativePathListener = $null
        $splatNativePathConnect = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativePathServer = Connect-DbaInstance @splatNativePathConnect
        $nativePathListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        $nativePathListener.Start()
        $nativePathPort = $nativePathListener.LocalEndpoint.Port
        $nativePathBadInstance = "Data Source=tcp:127.0.0.1,$nativePathPort;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    AfterAll {
        if ($nativePathListener) { $nativePathListener.Stop() }
        if ($nativePathServer) { $nativePathServer.ConnectionContext.Disconnect() }
    }

    It "returns the seven documented properties with server identity and normalized data and log paths" {
        $nativePathRows = @(Get-DbaDefaultPath -SqlInstance $nativePathServer -EnableException)
        $nativePathRows.Count | Should -Be 1
        ($nativePathRows[0].PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Data,Log,Backup,ErrorLog"
        $nativePathRows[0].ComputerName | Should -BeExactly $nativePathServer.ComputerName
        $nativePathRows[0].InstanceName | Should -BeExactly $nativePathServer.ServiceName
        $nativePathRows[0].SqlInstance | Should -BeExactly $nativePathServer.DomainInstanceName
        $nativePathRows[0].Data | Should -Not -BeNullOrEmpty
        $nativePathRows[0].Log | Should -Not -BeNullOrEmpty
        $nativePathRows[0].Data | Should -BeExactly $nativePathRows[0].Data.Trim().TrimEnd("\")
        $nativePathRows[0].Log | Should -BeExactly $nativePathRows[0].Log.Trim().TrimEnd("\")
        $nativePathRows[0].Backup | Should -BeExactly $nativePathServer.BackupDirectory
        $nativePathRows[0].ErrorLog | Should -BeExactly $nativePathServer.ErrorLogPath
        $nativePathRows[0].PSObject.Members["PSStandardMembers"] | Should -BeNullOrEmpty
    }

    It "warns for a failed pipeline instance and continues to the following record with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativePathWarnings = @()
        $nativePathPriorErrors = @($global:Error)
        $splatNativePathContinue = @{
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativePathWarnings"
        }
        $nativePathContinued = @(@($nativePathServer, $nativePathBadInstance, $nativePathServer) | Get-DbaDefaultPath @splatNativePathContinue)
        $nativePathContinued.Count | Should -Be 2
        foreach ($nativePathRow in $nativePathContinued) {
            $nativePathRow.SqlInstance | Should -BeExactly $nativePathServer.DomainInstanceName
            $nativePathRow.Data | Should -Not -BeNullOrEmpty
            $nativePathRow.Log | Should -Not -BeNullOrEmpty
        }
        ($nativePathWarnings -join " ") | Should -BeLike "*Failure*"
        $nativePathConnectionError = $global:Error | Where-Object {
            $nativePathPriorErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDefaultPath*"
        } | Select-Object -First 1
        $nativePathConnectionError | Should -Not -BeNullOrEmpty
        $nativePathConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "terminates on the failed pipeline instance with EnableException and preserves earlier output" -Tag "NativeChecklist:enable-exception" {
        $nativePathObserved = New-Object System.Collections.ArrayList
        $nativePathCaught = $null
        try {
            @($nativePathServer, $nativePathBadInstance, $nativePathServer) |
                Get-DbaDefaultPath -EnableException |
                ForEach-Object { $null = $nativePathObserved.Add($PSItem) }
        } catch {
            $nativePathCaught = $PSItem
        }
        $nativePathCaught | Should -Not -BeNullOrEmpty
        $nativePathCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativePathCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDefaultPath*"
        $nativePathCaught.Exception.Message | Should -Match "^The wait operation timed out\.?$"
        $nativePathObserved.Count | Should -Be 1
        $nativePathObserved[0].SqlInstance | Should -BeExactly $nativePathServer.DomainInstanceName
    }
}

Describe "Native Get-DbaDefaultPath over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            # Read-only command: no objects are created on the shared instance.
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $loginRows = @(Get-DbaDefaultPath -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $loginRows.Count | Should -Be 1
            $loginRows[0].SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
            $loginRows[0].Data | Should -Not -BeNullOrEmpty
            $loginRows[0].Log | Should -Not -BeNullOrEmpty
            $loginRows[0].Backup | Should -BeExactly $loginServer.BackupDirectory
        }

        It "fails cleanly without the credential: a warning and no output" {
            # Pinned: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Continue }.
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDefaultPath @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws" {
            { Get-DbaDefaultPath -SqlInstance $loginInstance -EnableException } | Should -Throw
        }
    }
}
