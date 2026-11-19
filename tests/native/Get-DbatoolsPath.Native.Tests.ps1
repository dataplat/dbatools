#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: pipeline-multiple N/A -- Name is positional and does not bind pipeline input.
# NativeChecklist: multi-instance-failure N/A -- the lookup takes a configuration name and has no server or instance input.
# NativeChecklist: enable-exception N/A -- the pinned function has no EnableException parameter.
# NativeChecklist: switch-false N/A -- Name is the only command-specific parameter and is a string.
# NativeChecklist: whatif-confirm N/A -- this read-only lookup does not support ShouldProcess.
# NativeChecklist: azure-sqldb N/A -- the configuration store is in the client process. This lookup takes no connection or database target.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbatoolsPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Managed path native value lookup" {
    BeforeAll {
        $script:managedPathName = "nativepath" + [Guid]::NewGuid().ToString("N")
        $script:managedPathKey = "path.managed." + $script:managedPathName
        $script:managedPathConfig = New-Object Dataplat.Dbatools.Configuration.Config
        $script:managedPathConfig.Module = "path.managed"
        $script:managedPathConfig.Name = $script:managedPathName
        [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations[$script:managedPathKey] = $script:managedPathConfig
    }
    AfterAll {
        $removedPathConfig = $null
        $null = [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations.TryRemove($script:managedPathKey, [ref]$removedPathConfig)
    }

    It "reads a custom managed path verbatim by positional name" {
        $script:managedPathConfig.Value = "relative path[1]/export"
        Get-DbatoolsPath $script:managedPathName | Should -BeExactly "relative path[1]/export"
    }

    It "returns collections as individual pipeline records" {
        $script:managedPathConfig.Value = @("first-path", "second-path")
        $pathValues = @(Get-DbatoolsPath -Name $script:managedPathName)
        $pathValues.Count | Should -Be 2
        $pathValues[0] | Should -BeExactly "first-path"
        $pathValues[1] | Should -BeExactly "second-path"
    }

    It "preserves configuration switch strings and case-insensitive names" {
        $script:managedPathConfig.Value = "mAnDaToRy"
        $requiredPath = Get-DbatoolsPath -Name $script:managedPathName.ToUpperInvariant()
        $requiredPath | Should -BeOfType System.Boolean
        $requiredPath | Should -BeTrue
        $script:managedPathConfig.Value = "OpTiOnAl"
        $optionalPath = Get-DbatoolsPath -Name $script:managedPathName
        $optionalPath | Should -BeOfType System.Boolean
        $optionalPath | Should -BeFalse
    }

    It "preserves a single null record for missing and null-valued settings" {
        $script:managedPathConfig.Value = $null
        $nullPath = @(Get-DbatoolsPath -Name $script:managedPathName)
        $missingPath = @(Get-DbatoolsPath -Name ($script:managedPathName + ".missing"))
        $nullPath.Count | Should -Be 1
        $missingPath.Count | Should -Be 1
        $nullPath[0] | Should -BeNullOrEmpty
        $missingPath[0] | Should -BeNullOrEmpty
    }

    It "uses the stored path value's ToString result <Text> and the original call order" -TestCases @(
        @{ Text = 'Mandatory'; Calls = 1; Result = $true }
        @{ Text = 'Optional'; Calls = 2; Result = $false }
    ) {
        param($Text, $Calls, $Result)
        $stored = [pscustomobject]@{ Calls = 0; Text = $Text }
        $stored | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Calls++; $this.Text } -Force
        $script:managedPathConfig.Value = $stored
        $actual = Get-DbatoolsPath $script:managedPathName
        $actual | Should -BeOfType System.Boolean
        $actual | Should -Be $Result
        $stored.Calls | Should -Be $Calls
    }

    It "uses the .NET ToString for a stored path value with no extended method" {
        $script:managedPathConfig.Value = New-Object System.Text.StringBuilder -ArgumentList 'Optional'
        $actual = Get-DbatoolsPath $script:managedPathName
        $actual | Should -BeOfType System.Boolean
        $actual | Should -BeFalse
    }

    It "preserves the delegated path lookup's stored method failure in <Mode> mode" -TestCases @(
        @{ Mode = 'plain' }
        @{ Mode = 'try' }
        @{ Mode = 'Stop' }
        @{ Mode = 'SilentlyContinue' }
    ) {
        param($Mode)
        $stored = [pscustomobject]@{ Calls = 0; Stamp = [guid]::NewGuid() }
        $stored | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Calls++; throw 'managed path fixture failed' } -Force
        $source = $null
        try { $null = $stored.ToString() -eq 'Mandatory' } catch { $source = $_ }
        $source.Exception | Should -BeOfType System.Management.Automation.MethodInvocationException

        # Pester invokes each It inside a try. Register the built command in a separate runspace for plain calls.
        $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $cmdletType = (Get-Command Get-DbatoolsPath -CommandType Cmdlet).ImplementingType
        $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbatoolsPath', $cmdletType, $null
        $state.Commands.Add($entry)
        $space = [runspacefactory]::CreateRunspace($state)
        $shell = [powershell]::Create()
        $rows = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        try {
            $space.Open()
            $shell.Runspace = $space
            $call = {
                param($Name, $Key, $Mode)
                # Create the method in the invoking runspace so its own throw appears in this runspace's history.
                $global:fixture = [pscustomobject]@{ Calls = 0; Stamp = [guid]::NewGuid() }
                $fixture | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Calls++; throw 'managed path fixture failed' } -Force
                [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations[$Key].Value = $fixture
                $global:records = @()
                $global:caughtRecord = $null
                $Error.Clear()
                $arguments = @{ Name = $Name; ErrorVariable = 'global:records' }
                if ($Mode -in 'Stop', 'SilentlyContinue') { $arguments.ErrorAction = $Mode }
                if ($Mode -eq 'try') {
                    try { Get-DbatoolsPath @arguments } catch { $global:caughtRecord = $_ }
                } else { Get-DbatoolsPath @arguments }
                'next statement'
            }
            $null = $shell.AddScript($call.ToString()).AddArgument($script:managedPathName).AddArgument($script:managedPathKey).AddArgument($Mode)
            $stop = $null
            try { $null = $shell.Invoke($null, $rows) } catch { $stop = $_.Exception.InnerException }
            $emitted = @($shell.Streams.Error)
            $vars = $space.SessionStateProxy
            $stored = $vars.GetVariable('fixture')
            $caught = $vars.GetVariable('caughtRecord')
            $history = @($vars.GetVariable('Error'))
            $collected = @($vars.GetVariable('records'))
            if ($Mode -in 'plain', 'SilentlyContinue') {
                $stored.Calls | Should -Be 2
                $rows.Count | Should -Be 2
                $rows[0].Stamp | Should -Be $stored.Stamp
                $rows[1] | Should -BeExactly 'next statement'
                $stop | Should -BeNullOrEmpty
                $caught | Should -BeNullOrEmpty
                $expectedStream = if ($Mode -eq 'plain') { 2 } else { 0 }
                $emitted.Count | Should -Be $expectedStream
                $collected.Count | Should -Be 2
                $history.Count | Should -Be 4
                $visible = @($emitted) + @($collected) + @($history[0], $history[2])
                $innerThrows = @($history[1], $history[3])
            } elseif ($Mode -eq 'try') {
                $stored.Calls | Should -Be 1
                $rows.Count | Should -Be 1
                $rows[0] | Should -BeExactly 'next statement'
                $caught | Should -BeOfType System.Management.Automation.ErrorRecord
                $stop | Should -BeNullOrEmpty
                $emitted.Count | Should -Be 0
                $collected.Count | Should -Be 1
                $collected[0] | Should -BeOfType System.Management.Automation.CmdletInvocationException
                $history.Count | Should -Be 2
                $visible = @($caught, $collected[0].ErrorRecord, $history[0])
                $innerThrows = @($history[1])
            } else {
                $stored.Calls | Should -Be 1
                $rows.Count | Should -Be 0
                $stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                $collected.Count | Should -Be 1
                $collected[0] | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                $history.Count | Should -Be 3
                $history[0] | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                $visible = @($stop.ErrorRecord, $collected[0].ErrorRecord, $history[0].ErrorRecord, $history[1])
                $innerThrows = @($history[2])
            }
            foreach ($inner in $innerThrows) {
                $inner | Should -BeOfType System.Management.Automation.ErrorRecord
                $inner.Exception.GetType().FullName | Should -BeExactly 'System.Management.Automation.RuntimeException'
                $inner.Exception.Message | Should -BeExactly 'managed path fixture failed'
            }
            foreach ($record in $visible) {
                $record | Should -BeOfType System.Management.Automation.ErrorRecord
                $record.FullyQualifiedErrorId | Should -BeExactly (($source.FullyQualifiedErrorId -split ',')[0] + ',' + $cmdletType.FullName)
                $record.CategoryInfo.Category | Should -Be $source.CategoryInfo.Category
                $record.CategoryInfo.Reason | Should -BeExactly $source.CategoryInfo.Reason
                $record.TargetObject | Should -Be $source.TargetObject
                $cause = $record.Exception
                for ($reference = $source.Exception; $null -ne $reference; $reference = $reference.InnerException) {
                    $cause.GetType().FullName | Should -BeExactly $reference.GetType().FullName
                    $cause.Message | Should -BeExactly $reference.Message
                    $cause = $cause.InnerException
                }
                $cause | Should -BeNullOrEmpty
            }
        } finally {
            $rows.Dispose()
            $shell.Dispose()
            $space.Dispose()
        }
    }
}
