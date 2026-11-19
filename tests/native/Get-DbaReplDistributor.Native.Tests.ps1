#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaReplDistributor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Get-DbaReplDistributor" -Tag IntegrationTests {
    BeforeAll {
        # Port 1 on localhost refuses at once; the one-second timeout keeps the failure quick.
        $nativeDistributorBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
        $nativeDistributorDefaultView = @("ComputerName", "InstanceName", "SqlInstance", "IsPublisher", "IsDistributor", "DistributionServer", "DistributionDatabase", "DistributorInstalled", "DistributorAvailable", "HasRemotePublisher")

        # The nested Connect-DbaInstance logs "Failure | Error connecting to [<name>]: <cause>" and Get-DbaReplServer
        # "Failure | <cause>", where <cause> is the connection's base exception text; under EnableException this command
        # adds "Error occurred getting information about <instance> | <cause>". Measured on the pin, both editions:
        # evidence/pin-connect-failure-chain-r2-20261112.txt in the item folder. <name> is checked exactly for a plain
        # instance name. For a connection-string target the pin's Stop-Function masks the instance through
        # Hide-ConnectionString, which rejects the instance's text and prints "Failed to mask the connection string"
        # there, while the port prints the instance; that divergence is reported in the item notes and not asserted
        # either way, so <name> is only required to be non-empty for $InstanceName = $null.
        # Returns <cause> after checking every line carries the same, non-empty cause.
        function Get-NativeConnectWarningCause {
            param($Warnings, $InstanceName, [string]$InstanceText, [switch]$EnableException)
            $lines = @($Warnings | ForEach-Object { "$PSItem" })
            $connectLines = @($lines -match '\[Connect-DbaInstance\] Failure \| ')
            $connectLines.Count | Should -Be 1 -Because ($lines -join ' ')
            $name = if ($null -eq $InstanceName) { '[^\]]+' } else { [regex]::Escape($InstanceName) }
            $pattern = '(?s)\[Connect-DbaInstance\] Failure \| Error connecting to \[' + $name + '\]: (?<cause>\S.*)\z'
            ($connectLines[0] -match $pattern) | Should -BeTrue -Because $connectLines[0]
            $cause = $Matches.cause
            $replLines = @($lines -match '\[Get-DbaReplServer\] Failure \| ')
            $replLines.Count | Should -Be 1 -Because ($lines -join ' ')
            $replLines[0] | Should -Match ('(?s)\[Get-DbaReplServer\] Failure \| ' + [regex]::Escape($cause) + '\z')
            $ownLines = @($lines -match 'Error occurred getting information about')
            if ($EnableException) {
                $ownLines.Count | Should -Be 1 -Because ($lines -join ' ')
                $ownLines[0] | Should -Match ('(?s)\[Get-DbaReplDistributor\] Error occurred getting information about ' + [regex]::Escape($InstanceText) + ' \| ' + [regex]::Escape($cause) + '\z')
                $lines.Count | Should -Be 3 -Because ($lines -join ' ')
            } else {
                $ownLines.Count | Should -Be 0 -Because ($lines -join ' ')
                $lines.Count | Should -Be 2 -Because ($lines -join ' ')
            }
            $cause
        }

        # With EnableException each Stop-Function on the way (Connect-DbaInstance, Get-DbaReplServer, this command) passes
        # its input record through the module's exception transform (private/scripts/message-transforms.ps1), which
        # replaces any exception holding a SqlException with that SqlException. The thrown record is therefore
        # System.Exception(<cause>) over the connection's SqlException, whose base text is <cause>, with no
        # "Error connecting to" layer (measured on the pin, both editions, as above). Returns <cause>.
        function Get-NativeConnectFailureCause {
            param($Failure, $Warnings, $InstanceName, [string]$InstanceText)
            $Failure | Should -Not -BeNullOrEmpty
            $Failure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaReplDistributor*'
            $Failure.CategoryInfo.Category | Should -Be 'ConnectionError'
            "$($Failure.TargetObject)" | Should -BeExactly $InstanceText
            $messages = @()
            for ($inner = $Failure.Exception; $inner; $inner = $inner.InnerException) { $messages += "[$($inner.GetType().FullName)] $($inner.Message)" }
            $chainText = $messages -join ' <- '
            $cause = $Failure.Exception.GetBaseException().Message
            $cause | Should -Not -BeNullOrEmpty
            $Failure.Exception.GetType().FullName | Should -BeExactly 'System.Exception' -Because $chainText
            $Failure.Exception.Message | Should -BeExactly $cause -Because $chainText
            $Failure.Exception.InnerException | Should -BeOfType Microsoft.Data.SqlClient.SqlException -Because $chainText
            $Failure.Exception.InnerException.GetBaseException().Message | Should -BeExactly $cause -Because $chainText
            Get-NativeConnectWarningCause -Warnings $Warnings -InstanceName $InstanceName -InstanceText $InstanceText -EnableException | Should -BeExactly $cause
            $cause
        }
    }

    It "returns the decorated replication server with the pinned default view" {
        $output = @(Get-DbaReplDistributor -SqlInstance $TestConfig.InstanceSingle -EnableException)
        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType Microsoft.SqlServer.Replication.ReplicationServer
        (@($output[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly ($nativeDistributorDefaultView -join ',')
        $output[0].DistributorInstalled | Should -BeFalse
        $output[0].IsDistributor | Should -BeFalse
        $output[0].ComputerName | Should -Not -BeNullOrEmpty
        $output[0].InstanceName | Should -Not -BeNullOrEmpty
        $output[0].SqlInstance | Should -Not -BeNullOrEmpty
    }

    It "warns as Get-DbaReplServer and goes on to the next pipeline target with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $warnings = @()
        $output = @(@($nativeDistributorBadInstance, $TestConfig.InstanceSingle) | Get-DbaReplDistributor -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $output.Count | Should -Be 1
        $output[0].DistributorInstalled | Should -BeFalse
        $cause = Get-NativeConnectWarningCause -Warnings $warnings -InstanceName $null -InstanceText 'localhost,1'
        $cause | Should -Not -BeNullOrEmpty
    }

    It "stops at a connection failure with EnableException, under this command's message" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        $output = $null
        $warnings = @()
        try {
            $output = @(@($nativeDistributorBadInstance, $TestConfig.InstanceSingle) | Get-DbaReplDistributor -EnableException -WarningAction SilentlyContinue -WarningVariable warnings)
        } catch { $failure = $_ }
        $output | Should -BeNullOrEmpty
        $cause = Get-NativeConnectFailureCause -Failure $failure -Warnings $warnings -InstanceName $null -InstanceText 'localhost,1'
        $cause | Should -Not -BeNullOrEmpty
    }

    It "authenticates with SQL credentials" -Tag "NativeChecklist:sql-login" {
        $warnings = @()
        $output = @(Get-DbaReplDistributor -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException -WarningAction SilentlyContinue -WarningVariable warnings)
        $output.Count | Should -Be 1
        $output[0].DistributorInstalled | Should -BeOfType [bool]
        $output[0].SqlInstance | Should -Not -BeNullOrEmpty
        ($warnings -join ' ') | Should -Not -BeLike '*Error connecting to*'
    }

    It "rejects the SQL-login instance without credentials" -Tag "NativeChecklist:sql-login" {
        # Pin public/Get-DbaReplDistributor.ps1:84-87, verbatim:
        # try {
        #     $distributor = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
        # } catch {
        #     Stop-Function -Message "Error occurred getting information about $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # Pin public/Get-DbaReplServer.ps1:89-90 and 98-99, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
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
        $loginInstance = "$($TestConfig.InstanceSqlLogin)"
        $warnings = @()
        @(Get-DbaReplDistributor -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        Get-NativeConnectWarningCause -Warnings $warnings -InstanceName $loginInstance -InstanceText $loginInstance | Should -BeLike 'Login failed for user *'
        # Get-DbaReplServer throws under the forwarded EnableException; this command's catch stops with the caught record.
        $failure = $null
        $warnings = @()
        try {
            $null = Get-DbaReplDistributor -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue -WarningVariable warnings
        } catch { $failure = $_ }
        Get-NativeConnectFailureCause -Failure $failure -Warnings $warnings -InstanceName $loginInstance -InstanceText $loginInstance | Should -BeLike 'Login failed for user *'
    }

    # NativeChecklist: azure-sqldb N/A -- Azure SQL Database can only be a push subscriber; it cannot be a publisher or distributor: https://learn.microsoft.com/azure/azure-sql/managed-instance/replication-transactional-overview
    It "refuses Azure SQL Database before reading distributor information" {
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
        @(Get-DbaReplDistributor -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        { Get-DbaReplDistributor -SqlInstance $azure -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Azure SQL Database not supported*"
    }
}
