#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaTrace",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativeTraceInitiallyEnabled = [bool]$nativeServer.Configuration.DefaultTraceEnabled.RunningValue
        if (-not $nativeTraceInitiallyEnabled) {
            $nativeServer.Configuration.DefaultTraceEnabled.ConfigValue = 1
            $nativeServer.Configuration.Alter()
        }
        $nativeParameters = @{ Default = $true }
        $nativeDisplay = "BufferCount,BufferSize,ComputerName,DroppedEventCount,EventCount,FilePosition,Id,InstanceName,IsDefault,IsRollover,IsRowset,IsRunning,IsShutdown,LastEventTime,MaxFiles,MaxSize,Path,ReaderSpid,SqlInstance,StartTime,Status,StopTime"
    }

    AfterAll {
        if (-not $nativeTraceInitiallyEnabled) {
            $nativeServer.Configuration.DefaultTraceEnabled.ConfigValue = 0
            $nativeServer.Configuration.Alter()
        }
    }

    It "preserves the pinned display order and independently verified values" {
        $nativeRows = @(& $CommandName -SqlInstance $TestConfig.InstanceSingle @nativeParameters -EnableException)
        $nativeRows.Count | Should -Be 1
        ($nativeRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeDisplay
        $nativeRows[0].IsDefault | Should -BeTrue
        $nativeRows[0].PSObject.Properties.Name | Should -Contain "Parent"
        $nativeRows[0].PSObject.Properties.Name | Should -Contain "RemotePath"
        $nativeReadback = $nativeServer.ConnectionContext.ExecuteWithResults("SELECT id, path FROM sys.traces WHERE is_default = 1")
        $nativeRows[0].Id | Should -Be $nativeReadback.Tables[0].Rows[0].id
        $nativeRows[0].Path | Should -BeExactly $nativeReadback.Tables[0].Rows[0].path
        $nativePath = [string]$nativeReadback.Tables[0].Rows[0].path
        $nativeExpectedRemotePath = $nativePath
        if (-not $nativePath.StartsWith('\\')) {
            # The pinned private helper delegates path joining to the filesystem provider.
            $nativeComputer = $nativeServer.ComputerName.Split('\')[0]
            $nativeExpectedRemotePath = Join-Path -Path ('\\{0}\' -f $nativeComputer) -ChildPath $nativePath.Replace(':', '$')
        }
        $nativeRows[0].RemotePath | Should -BeExactly $nativeExpectedRemotePath
    }

    It "accepts SqlCredential as an input without exposing it on trace rows" {
        $nativeTraceCommand = Get-Command $CommandName -CommandType Cmdlet
        $nativeTraceCommand.Parameters.ContainsKey("SqlCredential") | Should -BeTrue
        $nativeTraceCommand.Parameters["SqlCredential"].ParameterType | Should -Be ([System.Management.Automation.PSCredential])
        $nativeCredentialRows = @(& $CommandName -SqlInstance $TestConfig.InstanceSingle -EnableException)
        $nativeCredentialRows.Count | Should -BeGreaterThan 0
        foreach ($nativeCredentialRow in $nativeCredentialRows) {
            ($null -eq $nativeCredentialRow.PSObject.Properties["SqlCredential"]) | Should -BeTrue
        }
    }

    It "continues after a failed middle pipeline instance" {
        $nativeWarnings = @()
        $nativeRows = @(
            @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle) |
                & $CommandName @nativeParameters -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeWarnings
        )
        $nativeRows.Count | Should -Be 2
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
        foreach ($nativeRow in $nativeRows) {
            ($nativeRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeDisplay
        }
    }

    It "preserves earlier output before EnableException terminates the pipeline" {
        $nativeEarlierRows = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle) |
                & $CommandName @nativeParameters -EnableException |
                ForEach-Object { $nativeEarlierRows.Add($_) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeEarlierRows.Count | Should -Be 1
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

