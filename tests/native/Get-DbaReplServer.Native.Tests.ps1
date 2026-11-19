#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaReplServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Get-DbaReplServer" -Tag IntegrationTests {
    BeforeAll {
        # The connection failure's own text, read from the record so each assertion names the real cause.
        function Get-NativeFailureCause($record) {
            $record | Should -Not -BeNullOrEmpty
            $cause = $record.Exception.GetBaseException().Message
            $cause | Should -Not -BeNullOrEmpty
            $cause
        }
        function Get-NativeExceptionChain($record) {
            $messages = @()
            for ($exception = $record.Exception; $exception; $exception = $exception.InnerException) { $messages += $exception.Message }
            $messages
        }
        # The command's own connection-failure record. The pin's catch is Stop-Function -ErrorRecord $_ over the record its
        # Connect-DbaInstance threw, as in Get-DbaReplPublisher (measured on the pin, both editions, evidence
        # nondistributor-20261112 of that item): the exception carries the cause itself with the SqlException beneath it,
        # and Connect-DbaInstance's "Error connecting to" text appears only in that command's own warning and record.
        function Assert-NativeConnectFailureRecord($record, $cause) {
            $record.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaReplServer*'
            $record.CategoryInfo.Category | Should -Be 'ConnectionError'
            $record.Exception.Message | Should -BeExactly $cause
            $record.Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
            @(Get-NativeExceptionChain $record | Where-Object { $PSItem -like 'Error connecting to*' }).Count | Should -Be 0 -Because ((Get-NativeExceptionChain $record) -join ' <- ')
        }
        # Port 1 on localhost: nothing listens there, and the one-second timeout keeps the failure quick.
        $nativeReplServerBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
        $nativeReplServerDefaultView = @("ComputerName", "InstanceName", "SqlInstance", "IsDistributor", "IsPublisher", "DistributionServer", "DistributionDatabase")
        $nativeReplServerThrownId = 'dbatools_Get-DbaReplServer,Dataplat.Dbatools.Commands.GetDbaReplServerCommand'

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

        # The nested record names the same target as the command's own record: both come from the same input instance.
        function Get-NativeTargetPattern($record) {
            '^' + [regex]::Escape("$($record.TargetObject)") + '$'
        }

        # The record the absorbed Connect-DbaInstance's Stop-Function threw into the pinned catch. The pin keeps it in $Error
        # behind the command's own record (probe connectfailure-20261112, both editions, $Error[1]); the port inserts it there.
        function Assert-NativeNestedConnectRecord($record, $category, $messagePattern, $targetPattern) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Connect-DbaInstance'
            "$($record.CategoryInfo.Category)" | Should -BeExactly $category
            $record.Exception.Message | Should -Match $messagePattern
            "$($record.TargetObject)" | Should -Match $targetPattern
        }

        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's complete
        # -ErrorVariable and $Error sequences, entry by entry. Pin and port entries per mode are listed side by side in the item
        # notes (point 6). A Stop-Function that goes on (point 4): -ErrorVariable holds only the command's record, id
        # dbatools_Get-DbaReplServer; $Error gains that same record, then the nested Connect-DbaInstance record behind it.
        function Assert-NativeGoesOnSequence($errors, $added, $connectCategory, $connectPattern, $targetPattern) {
            @($errors).Count | Should -Be 1 -Because (@($errors | ForEach-Object { "$($PSItem.GetType().Name):$($PSItem.FullyQualifiedErrorId)" }) -join ' | ')
            $errors[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            $errors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaReplServer'
            @($added).Count | Should -Be 2 -Because (@($added | ForEach-Object { "$($PSItem.GetType().Name):$($PSItem.FullyQualifiedErrorId)" }) -join ' | ')
            [object]::ReferenceEquals($added[0], $errors[0]) | Should -BeTrue
            Assert-NativeNestedConnectRecord $added[1] $connectCategory $connectPattern $targetPattern
        }
        # A stop under -EnableException in a caller's try: -ErrorVariable holds the engine's one CmdletInvocationException
        # around the thrown record ("The -ErrorVariable entry of a native -EnableException stop (operator, 2026-11-06)"); $Error
        # gains the thrown record, then the nested Connect-DbaInstance record behind it. The engine adds the cmdlet type to the id
        # of a record a compiled cmdlet throws.
        function Assert-NativeStopSequence($errors, $added, $caught, $connectCategory, $connectPattern, $targetPattern) {
            $caught | Should -BeOfType System.Management.Automation.ErrorRecord
            $caught.FullyQualifiedErrorId | Should -BeExactly $nativeReplServerThrownId
            @($errors).Count | Should -Be 1 -Because (@($errors | ForEach-Object { $PSItem.GetType().FullName }) -join ' | ')
            $errors[0].GetType().FullName | Should -BeExactly 'System.Management.Automation.CmdletInvocationException'
            $errors[0].ErrorRecord.FullyQualifiedErrorId | Should -BeExactly $nativeReplServerThrownId
            @($added).Count | Should -Be 2 -Because (@($added | ForEach-Object { "$($PSItem.GetType().Name):$($PSItem.FullyQualifiedErrorId)" }) -join ' | ')
            $added[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            $added[0].FullyQualifiedErrorId | Should -BeExactly $nativeReplServerThrownId
            $added[0].Exception.Message | Should -BeExactly $caught.Exception.Message
            Assert-NativeNestedConnectRecord $added[1] $connectCategory $connectPattern $targetPattern
        }
    }

    It "returns the instance's ReplicationServer with the server's identity, RMO's role flags and the pinned default view, by name and piped as a server" {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $direct = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $server.ConnectionContext
        $output = @(Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle -EnableException)
        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType Microsoft.SqlServer.Replication.ReplicationServer
        $output[0].ComputerName | Should -BeExactly $server.ComputerName
        $output[0].InstanceName | Should -BeExactly $server.ServiceName
        $output[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
        $output[0].IsDistributor | Should -Be $direct.IsDistributor
        $output[0].IsPublisher | Should -Be $direct.IsPublisher
        (@($output[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly ($nativeReplServerDefaultView -join ',')

        $piped = @($server | Get-DbaReplServer -EnableException)
        $piped.Count | Should -Be 1
        $piped[0] | Should -BeOfType Microsoft.SqlServer.Replication.ReplicationServer
        $piped[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
        $piped[0].IsDistributor | Should -Be $direct.IsDistributor
    }

    It "warns with the connection failure's cause and goes on to the next pipeline target with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $warnings = @()
        $errors = @()
        $head = Get-NativeErrorHead
        $output = @(@($nativeReplServerBadInstance, $TestConfig.InstanceSingle) | Get-DbaReplServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
        $added = @(Get-NativeAddedErrors $head)
        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType Microsoft.SqlServer.Replication.ReplicationServer
        $output[0].SqlInstance | Should -Not -BeNullOrEmpty
        @($errors).Count | Should -Be 1
        $record = $errors[0]
        $cause = Get-NativeFailureCause $record
        Assert-NativeGoesOnSequence $errors $added 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause)) (Get-NativeTargetPattern $record)
        $text = $warnings -join "`n"
        # The bracketed instance text is not asserted: the pin shows "[Failed to mask the connection string]" for a
        # connection-string input (Get-DbaReplPublisher evidence nondistributor-20261112), the shared native message the instance name.
        $text | Should -Match ('\[Connect-DbaInstance\] Failure \| Error connecting to \[[^\]]+\]: ' + [regex]::Escape($cause))
        $text | Should -Match ('\[Get-DbaReplServer\] Failure \| ' + [regex]::Escape($cause))
        Assert-NativeConnectFailureRecord $record $cause
        "$($record.TargetObject)" | Should -Match 'localhost,1'
    }

    It "stops at a connection failure with EnableException, with the connection failure's cause" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        $output = $null
        $errors = @()
        $head = Get-NativeErrorHead
        try {
            $output = @(@($nativeReplServerBadInstance, $TestConfig.InstanceSingle) | Get-DbaReplServer -EnableException -WarningAction SilentlyContinue -ErrorVariable errors)
        } catch { $failure = $_ }
        $added = @(Get-NativeAddedErrors $head)
        $output | Should -BeNullOrEmpty
        $cause = Get-NativeFailureCause $failure
        Assert-NativeConnectFailureRecord $failure $cause
        Assert-NativeStopSequence $errors $added $failure 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause)) (Get-NativeTargetPattern $failure)
    }

    It "authenticates with SQL credentials" -Tag "NativeChecklist:sql-login" {
        $warnings = @()
        $output = @(Get-DbaReplServer -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        ($warnings -join ' ') | Should -Not -BeLike '*Error connecting to*'
        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType Microsoft.SqlServer.Replication.ReplicationServer
        $output[0].SqlInstance | Should -Not -BeNullOrEmpty
        $output[0].IsDistributor | Should -BeOfType [bool]
    }

    It "rejects the SQL-login instance without credentials" -Tag "NativeChecklist:sql-login" {
        # Pin public/Get-DbaReplServer.ps1, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # ...
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # Pin public/Connect-DbaInstance.ps1:499-503 and 1501-1502, verbatim:
        # if ($DisableException) {
        #     $EnableException = $false
        # } else {
        #     $EnableException = $true
        # }
        # if (-not $connectionSucceeded) {
        #     Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt; manager 26cdfe6de457.
        $warnings = @()
        $errors = @()
        $head = Get-NativeErrorHead
        $rows = @(Get-DbaReplServer -SqlInstance $TestConfig.InstanceSqlLogin -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
        $added = @(Get-NativeAddedErrors $head)
        $rows.Count | Should -Be 0
        @($errors).Count | Should -Be 1
        $record = $errors[0]
        $cause = Get-NativeFailureCause $record
        $cause | Should -BeLike 'Login failed for user*'
        ($warnings -join "`n") | Should -Match ('\[Get-DbaReplServer\] Failure \| ' + [regex]::Escape($cause))
        Assert-NativeConnectFailureRecord $record $cause
        Assert-NativeGoesOnSequence $errors $added 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($cause)) (Get-NativeTargetPattern $record)
        $failure = $null
        $errors = @()
        $head = Get-NativeErrorHead
        try {
            $null = Get-DbaReplServer -SqlInstance $TestConfig.InstanceSqlLogin -EnableException -WarningAction SilentlyContinue -ErrorVariable errors
        } catch { $failure = $_ }
        $added = @(Get-NativeAddedErrors $head)
        $failure.Exception.Message | Should -BeLike 'Login failed for user*'
        Assert-NativeStopSequence $errors $added $failure 'ConnectionError' ('^Error connecting to \[.+\]: ' + [regex]::Escape($failure.Exception.Message)) (Get-NativeTargetPattern $failure)
    }

    # NativeChecklist: azure-sqldb N/A -- Azure SQL Database can only be a push subscriber, never a publisher or distributor, and replication management must be performed from SQL Server: https://learn.microsoft.com/azure/azure-sql/database/replication-to-sql-database
    It "refuses Azure SQL Database before reading the replication server" {
        $azure = $null
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $transient = $false
                for ($failure = $_.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in @(-2, 40613) -or $failure.Message -match "timed out|timeout") { $transient = $true }
                }
                if (-not $transient -or $attempt -eq 5) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = @()
        $errors = @()
        $head = Get-NativeErrorHead
        $rows = @(Get-DbaReplServer -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
        $added = @(Get-NativeAddedErrors $head)
        $rows.Count | Should -Be 0
        ($warnings -join "`n") | Should -Match '\[Get-DbaReplServer\] Failure \| Azure SQL Database not supported'
        @($errors).Count | Should -Be 1
        $errors[0].Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        "$($errors[0].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
        # The refusal is Connect-DbaInstance -AzureUnsupported's Stop-Function, which names no category.
        Assert-NativeGoesOnSequence $errors $added 'NotSpecified' '^Azure SQL Database not supported$' (Get-NativeTargetPattern $errors[0])
        $failure = $null
        $errors = @()
        $head = Get-NativeErrorHead
        try {
            $null = Get-DbaReplServer -SqlInstance $azure -EnableException -WarningAction SilentlyContinue -ErrorVariable errors
        } catch { $failure = $_ }
        $added = @(Get-NativeAddedErrors $head)
        $failure.Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        Assert-NativeStopSequence $errors $added $failure 'NotSpecified' '^Azure SQL Database not supported$' (Get-NativeTargetPattern $failure)
    }
}
