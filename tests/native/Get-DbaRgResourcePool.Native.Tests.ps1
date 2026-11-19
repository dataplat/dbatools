#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRgResourcePool",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Get-DbaRgResourcePool" -Tag IntegrationTests {
    BeforeAll {
        # Read only: nothing is created, so the system pools "internal" and "default", which every instance has, give exact counts
        # even while other tests add pools of their own on the shared instance.
        $nativePoolInstance = $TestConfig.InstanceSingle
        $nativePoolServer = Connect-DbaInstance -SqlInstance $nativePoolInstance -EnableException
        $nativePoolView = @("ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "CapCpuPercentage", "IsSystemObject", "MaximumCpuPercentage", "MaximumIopsPerVolume", "MaximumMemoryPercentage", "MinimumCpuPercentage", "MinimumIopsPerVolume", "MinimumMemoryPercentage", "WorkloadGroups")
        # Port 1 on localhost: nothing listens there, and the one-second timeout keeps the failure quick.
        $nativePoolBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'

        # How many times each system pool appears in a result.
        function Get-NativeSystemPoolCount($rows, [string]$name) {
            @($rows | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.ResourcePool] -and $PSItem.Name -eq $name }).Count
        }

        # The entries a call added to the global $Error, newest first: everything in front of the entry that was newest before
        # the call. $Error is shared with Pester, so it is not cleared.
        function Get-NativeErrorHead {
            if ($global:Error.Count -gt 0) { $global:Error[0] }
        }
        function Get-NativeAddedErrors($head) {
            $added = New-Object System.Collections.ArrayList
            foreach ($entry in $global:Error) {
                if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                $null = $added.Add($entry)
            }
            $added.ToArray()
        }
        function Get-NativeEntryText($entries) {
            @($entries | ForEach-Object { "$($PSItem.GetType().Name):$($PSItem.FullyQualifiedErrorId)" }) -join ' | '
        }

        # The bad instance then the good one, piped to one call, in the given mode. Every mode runs in a caller try except
        # "plain", and records whether the statement after the call ran.
        function Invoke-NativeBadThenGood([string]$Mode) {
            $result = @{ Output = @(); Warnings = @(); Errors = @(); Caught = $null; After = $false }
            $warnings = @()
            $errors = @()
            $pipedInstances = @($nativePoolBadInstance, $nativePoolInstance)
            $splatPool = @{
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnings"
                ErrorVariable   = "errors"
            }
            switch ($Mode) {
                "EnableException" { $splatPool.EnableException = $true }
                "ErrorActionStop" { $splatPool.ErrorAction = "Stop"; $splatPool.EnableException = $false }
                "ErrorActionSilentlyContinue" { $splatPool.ErrorAction = "SilentlyContinue"; $splatPool.EnableException = $false }
                default { $splatPool.EnableException = $false }
            }
            $head = Get-NativeErrorHead
            if ($Mode -eq "plain") {
                $result.Output = @($pipedInstances | Get-DbaRgResourcePool @splatPool)
                $result.After = $true
            } else {
                try {
                    $result.Output = @($pipedInstances | Get-DbaRgResourcePool @splatPool)
                    $result.After = $true
                } catch {
                    $result.Caught = $PSItem
                }
            }
            $result.Added = @(Get-NativeAddedErrors $head)
            $result.Warnings = @($warnings)
            $result.Errors = @($errors)
            $result
        }

        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's complete
        # -ErrorVariable and $Error sequences, entry by entry, for a failed connection of the nested Get-DbaResourceGovernor. The
        # pin calls that command without -EnableException, so its Stop-Function -Continue warns and goes on in every mode. Pin and
        # port entries per mode are listed side by side in the item notes (point 6). -ErrorVariable: that command's record only.
        # $Error: that record, then the record Connect-DbaInstance threw into its catch.
        function Assert-NativeNestedFailure($result, [string]$cause, [string]$connectPattern) {
            $result.Caught | Should -BeNullOrEmpty -Because "the nested command warns and goes on: $($result.Caught)"
            $result.After | Should -BeTrue
            @($result.Errors).Count | Should -Be 1 -Because (Get-NativeEntryText $result.Errors)
            $record = $result.Errors[0]
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaResourceGovernor'
            "$($record.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $record.Exception.Message | Should -BeExactly $cause
            @($result.Added).Count | Should -Be 2 -Because (Get-NativeEntryText $result.Added)
            [object]::ReferenceEquals($result.Added[0], $record) | Should -BeTrue
            $result.Added[1] | Should -BeOfType System.Management.Automation.ErrorRecord
            $result.Added[1].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
            "$($result.Added[1].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
            $result.Added[1].Exception.Message | Should -Match $connectPattern
            ($result.Warnings -join "`n") | Should -Match ('\[Get-DbaResourceGovernor\] Failure \| ' + [regex]::Escape($cause))
        }
    }

    AfterAll {
        if ($nativePoolServer) { $nativePoolServer.ConnectionContext.Disconnect() }
    }

    It "returns the instance's resource pools with the server's identity and the pinned default view" {
        $rows = @(Get-DbaRgResourcePool -SqlInstance $nativePoolInstance -EnableException)
        $rows.Count | Should -BeGreaterThan 1
        foreach ($row in $rows) {
            $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.ResourcePool
            $row.ComputerName | Should -BeExactly $nativePoolServer.ComputerName
            $row.InstanceName | Should -BeExactly $nativePoolServer.ServiceName
            $row.SqlInstance | Should -BeExactly $nativePoolServer.DomainInstanceName
            (@($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly ($nativePoolView -join ',')
        }
        Get-NativeSystemPoolCount $rows "internal" | Should -Be 1
        Get-NativeSystemPoolCount $rows "default" | Should -Be 1
        $internal = @(Get-DbaRgResourcePool -SqlInstance $nativePoolInstance -Type Internal -EnableException)
        Get-NativeSystemPoolCount $internal "default" | Should -Be 1
    }

    It "returns the external resource pools with -Type External" {
        $direct = @($nativePoolServer.ResourceGovernor.ExternalResourcePools | ForEach-Object { $PSItem.Name } | Sort-Object)
        $rows = @(Get-DbaRgResourcePool -SqlInstance $nativePoolInstance -Type External -EnableException)
        (@($rows | ForEach-Object { $PSItem.Name } | Sort-Object) -join ',') | Should -BeExactly (@($direct) -join ',')
        foreach ($row in $rows) {
            $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.ExternalResourcePool
            $row.SqlInstance | Should -BeExactly $nativePoolServer.DomainInstanceName
        }
    }

    It "reads each -SqlInstance once" -Tag "NativeChecklist:pipeline-multiple" {
        # Correction n-by-n: the pin reads the whole -SqlInstance array once per element, so two names give each pool four times.
        $two = @(Get-DbaRgResourcePool -SqlInstance $nativePoolInstance, $nativePoolInstance -EnableException)
        Get-NativeSystemPoolCount $two "internal" | Should -Be 2
        Get-NativeSystemPoolCount $two "default" | Should -Be 2
        $three = @(Get-DbaRgResourcePool -SqlInstance $nativePoolInstance, $nativePoolInstance, $nativePoolInstance -EnableException)
        Get-NativeSystemPoolCount $three "default" | Should -Be 3
    }

    It "reads only each pipeline record's own instance" -Tag "NativeChecklist:pipeline-multiple" {
        # Correction piped-accumulation: the pin appends each record's governors to $InputObject and walks all of them again, so
        # three piped names give each pool six times.
        $rows = @(@($nativePoolInstance, $nativePoolInstance, $nativePoolInstance) | Get-DbaRgResourcePool -EnableException)
        Get-NativeSystemPoolCount $rows "internal" | Should -Be 3
        Get-NativeSystemPoolCount $rows "default" | Should -Be 3
    }

    It "returns each piped governor's pools once, and a governor beside -SqlInstance once each" -Tag "NativeChecklist:pipeline-multiple" {
        $piped = @(Get-DbaResourceGovernor -SqlInstance $nativePoolInstance, $nativePoolInstance -EnableException | Get-DbaRgResourcePool -EnableException)
        Get-NativeSystemPoolCount $piped "default" | Should -Be 2
        $governor = Get-DbaResourceGovernor -SqlInstance $nativePoolInstance -EnableException
        $both = @(Get-DbaRgResourcePool -InputObject $governor -SqlInstance $nativePoolInstance -EnableException)
        Get-NativeSystemPoolCount $both "default" | Should -Be 2
    }

    It "warns through the nested Get-DbaResourceGovernor and goes on to the next instance, in mode <Mode>" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" -ForEach @(
        @{ Mode = "plain" }
        @{ Mode = "callerTry" }
        @{ Mode = "EnableException" }
        @{ Mode = "ErrorActionStop" }
        @{ Mode = "ErrorActionSilentlyContinue" }
    ) {
        $result = Invoke-NativeBadThenGood $Mode
        Get-NativeSystemPoolCount $result.Output "default" | Should -Be 1
        Get-NativeSystemPoolCount $result.Output "internal" | Should -Be 1
        @($result.Output | Where-Object { $PSItem.SqlInstance -ne $nativePoolServer.DomainInstanceName }).Count | Should -Be 0
        @($result.Errors).Count | Should -Be 1 -Because (Get-NativeEntryText $result.Errors)
        $cause = $result.Errors[0].Exception.Message
        $cause | Should -Not -BeNullOrEmpty
        $cause | Should -Not -BeLike 'Error connecting to*'
        # As the pin's record (probe pin-contract-r2, both editions): the cause itself, with the SqlException beneath it.
        $result.Errors[0].Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
        $result.Errors[0].CategoryInfo.Reason | Should -BeExactly 'Exception'
        Assert-NativeNestedFailure $result $cause ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause))
        "$($result.Errors[0].TargetObject)" | Should -Match 'localhost,1'
        # The bracketed instance text is not asserted: the pin shows "[Failed to mask the connection string]" for a
        # connection-string input, the shared native message the instance name.
        ($result.Warnings -join "`n") | Should -Match ('\[Connect-DbaInstance\] Failure \| Error connecting to \[[^\]]+\]: ' + [regex]::Escape($cause))
    }
}

Describe "Native Get-DbaRgResourcePool on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        # Azure SQL Database has no user-configurable Resource Governor (https://learn.microsoft.com/sql/relational-databases/resource-governor/resource-governor:
        # SQL Server and Azure SQL Managed Instance only), so the nested read refuses it as the corrected Get-DbaResourceGovernor
        # does: correction azure-unsupported.
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per call.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError -is [System.TimeoutException] -or $azureError.Message -match "timed out|timeout|wait operation") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureLocalServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
        if ($azureLocalServer) { $azureLocalServer.ConnectionContext.Disconnect() }
    }

    It "warns that Azure SQL Database is not supported and reads the next instance, with and without -EnableException" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        foreach ($EnableException in @($false, $true)) {
        $azureWarnings = @()
        $azureErrors = @()
        $azureCaught = $null
        $azureAfter = $false
        $splatAzureRefusal = @{
            SqlInstance     = @($azureServer, $TestConfig.InstanceSingle)
            EnableException = $EnableException
            WarningAction   = "SilentlyContinue"
            WarningVariable = "azureWarnings"
            ErrorVariable   = "azureErrors"
        }
        $head = if ($global:Error.Count -gt 0) { $global:Error[0] }
        $azureRows = @()
        try {
            $azureRows = @(Get-DbaRgResourcePool @splatAzureRefusal)
            $azureAfter = $true
        } catch {
            $azureCaught = $PSItem
        }
        $added = New-Object System.Collections.ArrayList
        foreach ($entry in $global:Error) {
            if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
            $null = $added.Add($entry)
        }
        $azureCaught | Should -BeNullOrEmpty
        $azureAfter | Should -BeTrue
        $azureRows.Count | Should -BeGreaterThan 1
        @($azureRows | Where-Object { $PSItem.SqlInstance -ne $azureLocalServer.DomainInstanceName }).Count | Should -Be 0
        ($azureWarnings -join "`n") | Should -Match '\[Get-DbaResourceGovernor\] Failure \| Azure SQL Database not supported'
        @($azureErrors).Count | Should -Be 1
        $azureErrors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaResourceGovernor'
        "$($azureErrors[0].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
        $azureErrors[0].Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        $added.Count | Should -Be 2
        [object]::ReferenceEquals($added[0], $azureErrors[0]) | Should -BeTrue
        $added[1].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
        $added[1].Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        }
    }
}

Describe "Native Get-DbaRgResourcePool over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            try {
                $loginRows = @(Get-DbaRgResourcePool -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
                @($loginRows | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.ResourcePool] -and $PSItem.Name -eq "default" }).Count | Should -Be 1
                @($loginRows | Where-Object { $PSItem.SqlInstance -ne $loginServer.DomainInstanceName }).Count | Should -Be 0
            } finally {
                $loginServer.ConnectionContext.Disconnect()
            }
        }

        It "fails cleanly without the credential, with EnableException <EnableException>: the nested warning and no output" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $loginWarnings = @()
            $loginCaught = $null
            $loginRows = @()
            $splatLoginDenied = @{
                SqlInstance     = $loginInstance
                EnableException = $EnableException
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            try {
                $loginRows = @(Get-DbaRgResourcePool @splatLoginDenied)
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -BeNullOrEmpty
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join "`n") | Should -Match '\[Get-DbaResourceGovernor\] Failure \| .*Login failed'
        }
    }
}
