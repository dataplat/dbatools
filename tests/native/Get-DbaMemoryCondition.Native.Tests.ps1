#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- read-only diagnostics; the pin has no ShouldProcess.

BeforeAll {
    function Assert-NativeMemoryRecords {
        param($Server, [object[]]$Rows)
        $raw = @($Server.Query("SELECT record FROM sys.dm_os_ring_buffers WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR';"))
        $records = @{}
        foreach ($entry in $raw) {
            $xml = [xml]$entry.record
            $records["$($xml.Record.id):$($xml.Record.time)"] = $xml.Record
        }
        if ($Rows.Count -eq 0) {
            $raw.Count | Should -Be 0
            return
        }
        $matched = 0
        $previousTime = [long]::MinValue
        foreach ($row in $Rows) {
            $row.ComputerName | Should -BeExactly $Server.ComputerName
            $row.InstanceName | Should -BeExactly $Server.ServiceName
            $row.SqlInstance | Should -BeExactly $Server.DomainInstanceName
            $row.Runtime | Should -BeOfType [string]
            $row.NotificationTime | Should -BeOfType [datetime]
            $row.RecordTime | Should -BeGreaterOrEqual $previousTime
            $previousTime = $row.RecordTime
            $expected = $records["$($row.RecordId):$($row.RecordTime)"]
            # Records can be evicted between the command and this independent read.
            if ($null -eq $expected) { continue }
            $matched++
            $row.NotificationType | Should -BeExactly $expected.ResourceMonitor.Notification
            $row.MemoryUtilizationPercent | Should -Be ([long]$expected.MemoryRecord.MemoryUtilization)
            $row.NodeId | Should -Be ([long]$expected.MemoryNode.id)
            $legacy = $expected.SelectSingleNode('ResourceMonitor/Indicators')
            $mask = $null
            if ($null -ne $legacy) {
                $mask = [long]$legacy.InnerText
            } else {
                foreach ($node in $expected.SelectNodes('ResourceMonitor/IndicatorsProcess | ResourceMonitor/IndicatorsSystem')) {
                    if ($null -eq $mask) { $mask = [long]$node.InnerText }
                    else { $mask = $mask -bor [long]$node.InnerText }
                }
            }
            if ($null -eq $mask) { $row.Indicators | Should -BeNullOrEmpty }
            else { $row.Indicators | Should -Be $mask }
            $row.Type | Should -BeExactly $expected.type
            foreach ($name in 'TotalPhysicalMemory', 'AvailablePhysicalMemory', 'TotalPageFile', 'AvailablePageFile', 'TotalVirtualAddressSpace', 'AvailableVirtualAddressSpace') {
                $row.$name | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
                $row.$name.Byte | Should -Be ([long]$expected.MemoryRecord.$name * 1024)
            }
            $row.SQLReservedMemory.Byte | Should -Be ([long]$expected.MemoryNode.ReservedMemory * 1024)
            $row.SQLCommittedMemory.Byte | Should -Be ([long]$expected.MemoryNode.CommittedMemory * 1024)
            $runtime = [datetime]::ParseExact($row.Runtime, 'yyyy-MM-dd HH:mm:ss.fff', [cultureinfo]::InvariantCulture)
            $expectedTime = $runtime.AddMilliseconds(-($row.CurrentTime - $row.RecordTime))
            [math]::Abs(($row.NotificationTime - $expectedTime).TotalMilliseconds) | Should -BeLessThan 20
        }
        $matched | Should -BeGreaterThan 0
    }
}

Describe 'Native Get-DbaMemoryCondition' -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
    }
    It 'returns resource monitor values, sizes and event times in record order' {
        $rows = @(Get-DbaMemoryCondition -SqlInstance $server -EnableException)
        $rows.Count | Should -BeGreaterThan 0
        Assert-NativeMemoryRecords -Server $server -Rows $rows
        @($rows[0].PSObject.Properties.Name) | Should -BeExactly @('ComputerName', 'InstanceName', 'SqlInstance', 'Runtime', 'NotificationTime', 'NotificationType', 'MemoryUtilizationPercent', 'TotalPhysicalMemory', 'AvailablePhysicalMemory', 'TotalPageFile', 'AvailablePageFile', 'TotalVirtualAddressSpace', 'AvailableVirtualAddressSpace', 'NodeId', 'SQLReservedMemory', 'SQLCommittedMemory', 'RecordId', 'Type', 'Indicators', 'RecordTime', 'CurrentTime')
    }
    It 'reads multiple pipeline instances' -Tag NativeChecklist:pipeline-multiple {
        $rows = @($server, $server | Get-DbaMemoryCondition -EnableException)
        @($rows | Group-Object RecordId, RecordTime | Where-Object Count -eq 2).Count | Should -BeGreaterThan 0
    }
    It 'continues after a failed connection with EnableException false and stops when requested' -Tag NativeChecklist:multi-instance-failure, NativeChecklist:switch-false, NativeChecklist:enable-exception {
        $rows = @(Get-DbaMemoryCondition -SqlInstance 'tcp:127.0.0.1,1', $server -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows.Count | Should -BeGreaterThan 0
        @($warnings).Count | Should -Be 1
        "$warnings" | Should -BeLike '*Failure*'
        { Get-DbaMemoryCondition -SqlInstance 'tcp:127.0.0.1,1', $server -EnableException } | Should -Throw -ErrorId 'dbatools_Get-DbaMemoryCondition*'
    }
}

Describe 'Native Get-DbaMemoryCondition SQL authentication' -Tag IntegrationTests {
    It 'works with SqlCredential and fails cleanly without it' -Tag NativeChecklist:sql-login {
        $rows = @(Get-DbaMemoryCondition -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException)
        $rows.Count | Should -BeGreaterThan 0
        $loginServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        Assert-NativeMemoryRecords -Server $loginServer -Rows $rows
        $failed = @(Get-DbaMemoryCondition -SqlInstance $TestConfig.InstanceSqlLogin -WarningVariable warnings -WarningAction SilentlyContinue)
        $failed.Count | Should -Be 0
        "$warnings" | Should -BeLike '*Failure*Login failed*'
        { Get-DbaMemoryCondition -SqlInstance $TestConfig.InstanceSqlLogin -EnableException } | Should -Throw -ExpectedMessage '*Login failed*' -ErrorId 'dbatools_Get-DbaMemoryCondition*'
    }
}

Describe 'Native Get-DbaMemoryCondition Azure SQL Database' -Tag IntegrationTests {
    BeforeAll {
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                break
            } catch {
                $retry = $false
                for ($cause = $PSItem.Exception; $null -ne $cause; $cause = $cause.InnerException) {
                    if ($cause.Number -in 40613, -2 -or $cause -is [TimeoutException] -or ($cause -is [System.ComponentModel.Win32Exception] -and $cause.NativeErrorCode -eq 258)) { $retry = $true }
                }
                if (-not $retry -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }
    It 'reads database resource monitor records through its bound connection' -Tag NativeChecklist:azure-sqldb {
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
        $rows = @(Get-DbaMemoryCondition -SqlInstance $azure -EnableException)
        Assert-NativeMemoryRecords -Server $azure -Rows $rows
    }
}

Describe 'Native Get-DbaMemoryCondition read failures' -Tag IntegrationTests {
    BeforeAll {
        $admin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $login = 'native_memory_read_' + [guid]::NewGuid().ToString('N')
        $password = 'Nm!' + [guid]::NewGuid().ToString('N')
        $null = $admin.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$login] WITH PASSWORD=N'$password', CHECK_POLICY=OFF;")
        $connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $admin.Name, $login, $password
        $connection.NonPooledConnection = $true
        $connection.TrustServerCertificate = $true
        $connection.DatabaseName = 'master'
        $connection.Connect()
        $low = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connection
        $connection.ExecuteScalar('SELECT SUSER_SNAME();') | Should -BeExactly $login
        $denied = $null
        try { $null = $connection.ExecuteWithResults('SELECT record FROM sys.dm_os_ring_buffers;') } catch { $denied = $PSItem.Exception }
        $denied | Should -Not -BeNullOrEmpty
        $denials = @()
        for ($cause = $denied; $null -ne $cause; $cause = $cause.InnerException) {
            foreach ($sqlError in $cause.Errors) {
                if ($sqlError.Number -in 297, 300) { $denials += $sqlError.Number }
            }
        }
        $denials.Count | Should -BeGreaterThan 0
    }
    AfterAll {
        if ($connection) { $connection.Disconnect() }
        if ($admin -and $login) {
            $null = $admin.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$login') IS NOT NULL DROP LOGIN [$login];")
            $admin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE name=N'$login';") | Should -Be 0
        }
    }

    It 'does not repeat earlier records when a later instance read fails' -Tag NativeChecklist:multi-instance-failure {
        $rows = @(Get-DbaMemoryCondition -SqlInstance $admin, $low -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows.Count | Should -BeGreaterThan 0
        @($warnings).Count | Should -Be 1
        "$warnings" | Should -BeLike '*Issue collecting data*permission was denied*'
        @($rows | Group-Object RecordId, RecordTime | Where-Object Count -ne 1).Count | Should -Be 0
    }
    It 'does not repeat earlier pipeline records when the next read fails' -Tag NativeChecklist:pipeline-multiple {
        $rows = @($admin, $low | Get-DbaMemoryCondition -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows.Count | Should -BeGreaterThan 0
        @($warnings).Count | Should -Be 1
        @($rows | Group-Object RecordId, RecordTime | Where-Object Count -ne 1).Count | Should -Be 0
    }
    It 'continues after a denied first read and stops on it under EnableException' -Tag NativeChecklist:enable-exception {
        $rows = @(Get-DbaMemoryCondition -SqlInstance $low, $admin -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows.Count | Should -BeGreaterThan 0
        @($warnings).Count | Should -Be 1
        { Get-DbaMemoryCondition -SqlInstance $low, $admin -EnableException } | Should -Throw -ExpectedMessage '*permission was denied*' -ErrorId 'dbatools_Get-DbaMemoryCondition*'
        $caught = $null
        try { Get-DbaMemoryCondition -SqlInstance $low, $admin -EnableException } catch { $caught = $PSItem }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.GetBaseException().GetType().FullName | Should -BeExactly $denied.GetBaseException().GetType().FullName
        $caught.Exception.GetBaseException().Number | Should -Be $denied.GetBaseException().Number
        @($caught.Exception.GetBaseException().Errors | ForEach-Object Number) | Should -Contain $denied.GetBaseException().Number
    }
}

Describe 'Native Get-DbaMemoryCondition row conversion faults' -Tag IntegrationTests {
    BeforeAll {
        $conversionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $conversionServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.dm_os_ring_buffers WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR';") | Should -BeGreaterThan 0
        $conversionValue = [long]$conversionServer.ConnectionContext.ExecuteScalar("SELECT TOP (1) x.value('(//Record/MemoryRecord/TotalPhysicalMemory)[1]', 'BIGINT') FROM (SELECT CAST(record AS XML) AS x FROM sys.dm_os_ring_buffers WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR') AS r ORDER BY x.value('(//Record/@time)[1]', 'BIGINT');")
        # A runspace-local ETS converter makes the first real row fail; later rows still use the Size constructor.
        # The server's ring buffers remain untouched and the production command has no fixture-only branch.
        if (-not ('NativeMemoryConversionFixture' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Management.Automation;
public sealed class NativeMemoryConversionFixture : PSTypeConverter
{
    private bool failed;
    public override bool CanConvertFrom(object sourceValue, Type destinationType)
    {
        return sourceValue is long || sourceValue is int;
    }
    public override bool CanConvertTo(object sourceValue, Type destinationType) { return false; }
    public override object ConvertFrom(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
    {
        if (!failed)
        {
            failed = true;
            throw new InvalidCastException("native memory conversion fixture");
        }
        return Activator.CreateInstance(destinationType, new object[] { Convert.ToInt64(sourceValue, formatProvider) });
    }
    public override object ConvertTo(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
    {
        throw new NotSupportedException();
    }
}
'@
        }

        function Invoke-NativeMemoryRowFault {
            param([string]$Mode = 'plain')
            # Pester encloses each It in a try; a separate runspace observes the caller's plain-call behavior.
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaMemoryCondition -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbaMemoryCondition', $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript(@'
param($Server, $Mode, $ConversionValue)
$ErrorActionPreference = 'Continue'
Update-TypeData -TypeName Dataplat.Dbatools.Utility.Size -TypeConverter NativeMemoryConversionFixture -Force -ErrorAction Stop
if ($Mode -eq 'reference') {
    try { [Dataplat.Dbatools.Utility.Size]$ConversionValue } catch { $PSItem }
} else {
    $arguments = @{ SqlInstance = @($Server, $Server); EnableException = $false }
    if ($Mode -eq 'enabled') { $arguments.EnableException = $true }
    if ($Mode -eq 'stop') { $arguments.ErrorAction = 'Stop' }
    if ($Mode -eq 'pipeline') {
        $Server, $Server | Get-DbaMemoryCondition -EnableException:$false
    } elseif ($Mode -eq 'try') {
        try {
            Get-DbaMemoryCondition @arguments
            'inside next statement'
        } catch { [pscustomobject]@{ Caught = $PSItem } }
    } else {
        Get-DbaMemoryCondition @arguments
    }
    'next statement'
}
'@).AddArgument($conversionServer).AddArgument($Mode).AddArgument($conversionValue)
                try { $null = $outsideShell.Invoke($null, $outsideOutput) } catch { $outsideStop = $PSItem.Exception.InnerException }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
        $reference = Invoke-NativeMemoryRowFault -Mode reference
        $reference.Output.Count | Should -Be 1
        $conversionFault = $reference.Output[0]

        function Assert-NativeMemoryConversionFault {
            param($Record)
            $Record.Exception.GetType().FullName | Should -BeExactly $conversionFault.Exception.GetType().FullName
            $Record.Exception.Message | Should -BeExactly $conversionFault.Exception.Message
            $Record.CategoryInfo.Category | Should -Be $conversionFault.CategoryInfo.Category
            $Record.TargetObject | Should -Be $conversionFault.TargetObject
            ($Record.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly ($conversionFault.FullyQualifiedErrorId -split ',')[0]
        }
    }

    It 'outside any try writes one conversion fault and continues with the next instance' {
        $outside = Invoke-NativeMemoryRowFault
        $outside.Stop | Should -BeNullOrEmpty
        $outside.Warnings.Count | Should -Be 0
        $outside.Errors.Count | Should -Be 1
        Assert-NativeMemoryConversionFault $outside.Errors[0]
        $outside.Output.Count | Should -BeGreaterThan 1
        $outside.Output[-1] | Should -BeExactly 'next statement'
        @($outside.Output | Where-Object { $null -ne $PSItem.PSObject.Properties['RecordId'] }).Count | Should -BeGreaterThan 0
    }

    It 'outside any try writes one conversion fault and continues with the next pipeline record' {
        $outside = Invoke-NativeMemoryRowFault -Mode pipeline
        $outside.Stop | Should -BeNullOrEmpty
        $outside.Warnings.Count | Should -Be 0
        $outside.Errors.Count | Should -Be 1
        Assert-NativeMemoryConversionFault $outside.Errors[0]
        @($outside.Output | Where-Object { $null -ne $PSItem.PSObject.Properties['RecordId'] }).Count | Should -BeGreaterThan 0
        $outside.Output[-1] | Should -BeExactly 'next statement'
    }

    It 'outside any try EnableException ends the command at the conversion fault' -Tag NativeChecklist:enable-exception {
        $outside = Invoke-NativeMemoryRowFault -Mode enabled
        $outside.Stop | Should -BeNullOrEmpty
        $outside.Errors.Count | Should -Be 1
        Assert-NativeMemoryConversionFault $outside.Errors[0]
        ($outside.Output -join ',') | Should -BeExactly 'next statement'
    }

    It 'outside any try ErrorAction Stop ends the script at the conversion fault' {
        # The installed keep-going contract retains the effect of WriteError under ErrorAction Stop at caller-try sites.
        $outside = Invoke-NativeMemoryRowFault -Mode stop
        $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
        Assert-NativeMemoryConversionFault $outside.Stop.ErrorRecord
        $outside.Output.Count | Should -Be 0
    }

    It 'inside a caller try catches the conversion fault and produces no later rows' {
        $outside = Invoke-NativeMemoryRowFault -Mode try
        $outside.Stop | Should -BeNullOrEmpty
        $outside.Errors.Count | Should -Be 0
        $outside.Output.Count | Should -Be 2
        Assert-NativeMemoryConversionFault $outside.Output[0].Caught
        $outside.Output[1] | Should -BeExactly 'next statement'
    }
}
