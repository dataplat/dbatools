#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaEndpoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
# NativeChecklist: pipeline-multiple N/A -- The pinned command has no pipeline parameters; Destination is an explicit array.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database does not expose CREATE ENDPOINT or user-managed server endpoints: https://learn.microsoft.com/sql/t-sql/statements/create-endpoint-transact-sql

Describe "Native Copy-DbaEndpoint" -Tag IntegrationTests {
    BeforeAll {
        $source = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $prefix = 'nativeendpoint_' + [guid]::NewGuid().ToString('N')
        $name = $prefix + "_quote']_" + '$&'
        $quotedName = '[' + $name.Replace(']', ']]') + ']'
        # SQL Server allows only one Service Broker endpoint. Do not replace an existing one.
        @($source.Endpoints | Where-Object EndpointType -eq ServiceBroker).Count | Should -Be 0
        @($destination.Endpoints | Where-Object EndpointType -eq ServiceBroker).Count | Should -Be 0
        $usedPorts = @($source.Endpoints | ForEach-Object { $_.Protocol.Tcp.ListenerPort })
        $usedPorts += @($destination.Endpoints | ForEach-Object { $_.Protocol.Tcp.ListenerPort })
        $port = 26000
        while ($port -in $usedPorts) { $port++ }
        $sql = "CREATE ENDPOINT $quotedName STATE = STOPPED AS TCP (LISTENER_PORT = $port) FOR SERVICE_BROKER (AUTHENTICATION = WINDOWS NEGOTIATE, ENCRYPTION = REQUIRED ALGORITHM AES)"
        $null = $source.ConnectionContext.ExecuteNonQuery($sql)
        $source.Endpoints.Refresh()
    }
    AfterEach {
        if ($destination -and $name) {
            $destination.Endpoints.Refresh()
            if ($destination.Endpoints[$name]) { $destination.Endpoints[$name].Drop() }
        }
    }
    AfterAll {
        if ($source -and $name) {
            $source.Endpoints.Refresh()
            if ($source.Endpoints[$name]) { $source.Endpoints[$name].Drop() }
        }
    }
    It "honors the documented Endpoint wildcard filter" {
        $copy = @{
            Source = $source
            Destination = $destination
            Endpoint = "$prefix*"
            Confirm = $false
            EnableException = $true
        }
        $results = @(Copy-DbaEndpoint @copy)
        $results.Count | Should -Be 1
        $results[0].Status | Should -Be Successful
        $results[0].Name | Should -Be $name
        $destination.Endpoints.Refresh()
        $destination.Endpoints[$name].EndpointType | Should -Be ServiceBroker
        $destination.Endpoints[$name].EndpointState | Should -Be Stopped
        $destination.Endpoints[$name].Protocol.Tcp.ListenerPort | Should -Be $port
    }
    It "keeps exclusion precedence over a matching wildcard" {
        $copy = @{
            Source = $source
            Destination = $destination
            Endpoint = "$prefix*"
            ExcludeEndpoint = $name
            Confirm = $false
            EnableException = $true
        }
        @(Copy-DbaEndpoint @copy).Count | Should -Be 0
        $destination.Endpoints.Refresh()
        $destination.Endpoints[$name] | Should -BeNullOrEmpty
    }
    It "copies a quoted endpoint then skips or replaces it according to Force" -Tag NativeChecklist:switch-false, NativeChecklist:whatif-confirm {
        $copy = @{
            Source = $source
            Destination = $destination
            Endpoint = $name
            Force = $false
            Confirm = $false
            EnableException = $false
        }
        $first = @(Copy-DbaEndpoint @copy)
        $first.Count | Should -Be 1
        $first[0].Status | Should -Be Successful
        $destination.Endpoints.Refresh()
        $destination.Endpoints[$name] | Should -Not -BeNullOrEmpty
        $second = @(Copy-DbaEndpoint @copy)
        $second.Count | Should -Be 1
        $second[0].Status | Should -Be Skipped
        $second[0].Notes | Should -Be 'Already exists on destination'
        $copy.Force = $true
        $preference = $ConfirmPreference
        $third = @(Copy-DbaEndpoint @copy)
        $third.Count | Should -Be 1
        $third[0].Status | Should -Be Successful
        $ConfirmPreference | Should -Be $preference
        $destination.Endpoints.Refresh()
        $destination.Endpoints[$name].EndpointState | Should -Be Stopped
    }
    It "does not create an endpoint under WhatIf" -Tag NativeChecklist:whatif-confirm {
        $copy = @{
            Source = $source
            Destination = $destination
            Endpoint = $name
            Force = $true
            WhatIf = $true
            Confirm = $false
        }
        @(Copy-DbaEndpoint @copy).Count | Should -Be 0
        $destination.Endpoints.Refresh()
        $destination.Endpoints[$name] | Should -BeNullOrEmpty
    }
    It "continues to a valid destination after connection failure" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $copy = @{
            Source = $source
            Destination = @('tcp:127.0.0.1,1', $destination)
            Endpoint = $name
            EnableException = $false
            Confirm = $false
            WarningAction = 'SilentlyContinue'
            WarningVariable = 'warnings'
        }
        $results = @(Copy-DbaEndpoint @copy)
        $results.Count | Should -Be 1
        $results[0].Status | Should -Be Successful
        ($warnings -join ' ') | Should -Match Failure
    }
    It "refuses Azure endpoint operations and continues to a supported destination" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $azure = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
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
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $sourceWarnings = @()
            @(Copy-DbaEndpoint -Source $azure -Destination $destination -Endpoint $name -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable sourceWarnings).Count | Should -Be 0
            ($sourceWarnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            { Copy-DbaEndpoint -Source $azure -Destination $destination -Endpoint $name -EnableException -Confirm:$false } | Should -Throw '*Azure SQL Database not supported*'
            $destinationWarnings = @()
            $result = @(Copy-DbaEndpoint -Source $source -Destination @($azure, $destination) -Endpoint $name -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable destinationWarnings)
            $result.Count | Should -Be 1
            $result[0].Status | Should -Be Successful
            ($destinationWarnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            $destination.Endpoints.Refresh()
            $destination.Endpoints[$name].EndpointType | Should -Be ServiceBroker
            $destination.Endpoints[$name].EndpointState | Should -Be Stopped
            { Copy-DbaEndpoint -Source $source -Destination $azure -Endpoint $name -EnableException -Confirm:$false } | Should -Throw '*Azure SQL Database not supported*'
        } finally {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }
    }

    It "reports the SQL error in Notes when endpoint creation fails" {
        $conflictName = $prefix + '_conflict'
        $conflictIdentifier = '[' + $conflictName.Replace(']', ']]') + ']'
        $conflictPort = $port + 1
        while ($conflictPort -in $usedPorts) { $conflictPort++ }
        try {
            $null = $destination.ConnectionContext.ExecuteNonQuery("CREATE ENDPOINT $conflictIdentifier STATE = STOPPED AS TCP (LISTENER_PORT = $conflictPort) FOR SERVICE_BROKER (AUTHENTICATION = WINDOWS NEGOTIATE, ENCRYPTION = REQUIRED ALGORITHM AES)")
            $destination.Endpoints.Refresh()
            $expectedMessage = $null
            $expectedNumber = $null
            try {
                $null = $destination.ConnectionContext.ExecuteNonQuery(($source.Endpoints[$name].Script() -join [Environment]::NewLine))
            } catch {
                $errorException = $_.Exception
                while ($errorException.InnerException) { $errorException = $errorException.InnerException }
                $expectedMessage = $errorException.Message
                $expectedNumber = $errorException.Number
            }
            $expectedNumber | Should -Be 7862
            $expectedMessage | Should -Not -BeNullOrEmpty
            foreach ($enable in @($false, $true)) {
                $result = @(Copy-DbaEndpoint -Source $source -Destination $destination -Endpoint $name -Confirm:$false -EnableException:$enable)
                $result.Count | Should -Be 1
                $result[0].Status | Should -BeExactly 'Failed'
                $result[0].Notes | Should -BeExactly $expectedMessage
            }
            $destination.Endpoints.Refresh()
            $destination.Endpoints[$name] | Should -BeNullOrEmpty
            $destination.Endpoints[$conflictName].EndpointState | Should -Be Stopped
        } finally {
            $destination.Endpoints.Refresh()
            if ($destination.Endpoints[$conflictName]) { $destination.Endpoints[$conflictName].Drop() }
        }
    }

    It "throws on connection failure with EnableException" -Tag NativeChecklist:enable-exception {
        $copy = @{
            Source = $source
            Destination = 'tcp:127.0.0.1,1'
            Endpoint = $name
            EnableException = $true
            Confirm = $false
        }
        { Copy-DbaEndpoint @copy } | Should -Throw
    }
}
