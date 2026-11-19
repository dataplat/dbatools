#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: pipeline-multiple N/A -- The pinned command accepts one key and binds no parameter from pipeline input.
# NativeChecklist: multi-instance-failure N/A -- The lookup reads the process-local configuration store without connecting to an instance.
# NativeChecklist: azure-sqldb N/A -- The lookup uses the local ConfigurationHost and has no SQL target or server-dependent path.
# NativeChecklist: whatif-confirm N/A -- The getter reads a value and does not support ShouldProcess.
# NativeChecklist: enable-exception N/A -- The pinned command exposes NotNull for a missing value and has no EnableException parameter.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbatoolsConfigValue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Configuration value lookup extraction" {
    BeforeAll {
        $script:nativePathName = "native_lookup_" + [Guid]::NewGuid().ToString("N")
        $script:nativeConfigKey = "path.managed." + $script:nativePathName
        $script:nativeConfig = New-Object Dataplat.Dbatools.Configuration.Config
        $script:nativeConfig.Module = "path.managed"
        $script:nativeConfig.Name = $script:nativePathName
        [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations[$script:nativeConfigKey] = $script:nativeConfig
        function Assert-StoredMethodFault {
            param($Record, $Reference)
            $Record.Exception.Message | Should -BeLike '*fixture conversion failed*'
            ($Record.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly ($Reference.FullyQualifiedErrorId -split ',')[0]
            $Record.CategoryInfo.Category | Should -Be $Reference.CategoryInfo.Category
            $actualCause = $Record.Exception
            $referenceCause = $Reference.Exception
            while ($null -ne $referenceCause) {
                $actualCause | Should -Not -BeNullOrEmpty
                $actualCause.GetType().FullName | Should -BeExactly $referenceCause.GetType().FullName
                $actualCause.Message | Should -BeExactly $referenceCause.Message
                $actualCause = $actualCause.InnerException
                $referenceCause = $referenceCause.InnerException
            }
            $actualCause | Should -BeNullOrEmpty
        }
    }
    AfterAll {
        $removedNativeConfig = $null
        $null = [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations.TryRemove($script:nativeConfigKey, [ref]$removedNativeConfig)
    }

    It "normalizes a stored switch value but leaves a fallback string unchanged" {
        $script:nativeConfig.Value = "Mandatory"
        Get-DbatoolsConfigValue -FullName $script:nativeConfigKey | Should -BeTrue
        $script:nativeConfig.Value = $null
        $fallbackValue = Get-DbatoolsConfigValue -FullName $script:nativeConfigKey -Fallback "Optional"
        $fallbackValue | Should -BeOfType System.String
        $fallbackValue | Should -BeExactly "Optional"
    }

    It "uses fallback for a missing key and preserves explicit NotNull termination" {
        $missingKey = $script:nativeConfigKey + ".missing"
        Get-DbatoolsConfigValue -FullName $missingKey -Fallback 42 | Should -Be 42
        { Get-DbatoolsConfigValue -FullName $missingKey -NotNull } | Should -Throw
    }

    It "uses the pinned case-insensitive invariant comparison for switch values" {
        $script:nativeConfig.Value = "Mand" + [char]0x00ad + "atory"
        Get-DbatoolsConfigValue $script:nativeConfigKey | Should -BeTrue
        $script:nativeConfig.Value = "oPTioNal"
        Get-DbatoolsConfigValue $script:nativeConfigKey | Should -BeFalse
    }

    It "uses the stored object's ToString when it returns <Token>" -TestCases @(
        @{ Token = 'Mandatory'; Expected = $true; Calls = 1 }
        @{ Token = 'Optional'; Expected = $false; Calls = 2 }
    ) {
        param($Token, $Expected, $Calls)
        $stored = [pscustomobject]@{ Text = $Token; Calls = 0 }
        $stored | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Calls++; $this.Text } -Force
        $script:nativeConfig.Value = $stored
        $result = Get-DbatoolsConfigValue $script:nativeConfigKey
        $result | Should -BeOfType System.Boolean
        $result | Should -Be $Expected
        $stored.Calls | Should -Be $Calls
        $stored.Calls = 0
        $pathResult = Get-DbatoolsPath -Name $script:nativePathName
        $pathResult | Should -BeOfType System.Boolean
        $pathResult | Should -Be $Expected
        $stored.Calls | Should -Be $Calls
    }

    It "uses the plain .NET ToString when a stored value has no extended method" {
        $stored = New-Object System.Text.StringBuilder -ArgumentList 'Optional'
        $script:nativeConfig.Value = $stored
        $result = Get-DbatoolsConfigValue $script:nativeConfigKey
        $result | Should -BeOfType System.Boolean
        $result | Should -BeFalse
        $pathResult = Get-DbatoolsPath -Name $script:nativePathName
        $pathResult | Should -BeOfType System.Boolean
        $pathResult | Should -BeFalse
    }

    It "compares a collection returned by the stored method using the matching elements" {
        $stored = [pscustomobject]@{}
        $stored | Add-Member -MemberType ScriptMethod -Name ToString -Value { 'other'; 'Optional' } -Force
        $script:nativeConfig.Value = $stored
        Get-DbatoolsConfigValue $script:nativeConfigKey | Should -BeFalse
    }

    It "lets a caller try catch a stored method's fault at the first comparison" {
        $stored = [pscustomobject]@{ Calls = 0 }
        $stored | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Calls++; throw 'fixture conversion failed' } -Force
        $script:nativeConfig.Value = $stored
        $methodReference = $null
        try { $null = $stored.ToString() -eq 'Mandatory' } catch { $methodReference = $_ }
        $methodReference | Should -BeOfType System.Management.Automation.ErrorRecord
        $stored.Calls = 0
        $caught = $null
        try {
            $null = Get-DbatoolsConfigValue $script:nativeConfigKey
        } catch {
            $caught = $_
        }
        Assert-StoredMethodFault $caught $methodReference
        $stored.Calls | Should -Be 1
    }

    It "preserves stored method errors and statement continuation outside a caller try in <Mode> mode" -TestCases @(
        @{ Mode = 'plain' }
        @{ Mode = 'Stop' }
    ) {
        param($Mode)
        $marker = New-Object object
        $stored = [pscustomobject]@{ Calls = 0; Marker = $marker }
        $stored | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Calls++; throw 'fixture conversion failed' } -Force
        $script:nativeConfig.Value = $stored
        $methodReference = $null
        try { $null = $stored.ToString() -eq 'Mandatory' } catch { $methodReference = $_ }
        $methodReference.Exception | Should -BeOfType System.Management.Automation.MethodInvocationException
        $stored.Calls = 0

        # Pester wraps an It in a try; the isolated invoking script has no enclosing try.
        $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $getterType = (Get-Command Get-DbatoolsConfigValue -CommandType Cmdlet).ImplementingType
        $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbatoolsConfigValue', $getterType, $null
        $state.Commands.Add($entry)
        $space = [runspacefactory]::CreateRunspace($state)
        $shell = [powershell]::Create()
        $rows = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        try {
            $space.Open()
            $shell.Runspace = $space
            $arguments = @{ FullName = $script:nativeConfigKey }
            if ($Mode -eq 'Stop') { $arguments.ErrorAction = 'Stop' }
            $null = $shell.AddScript('param($Arguments) Get-DbatoolsConfigValue @Arguments; "next statement"').AddArgument($arguments)
            $stop = $null
            try { $null = $shell.Invoke($null, $rows) } catch { $stop = $_.Exception.InnerException }
            if ($Mode -eq 'plain') {
                $stop | Should -BeNullOrEmpty
                $stored.Calls | Should -Be 2
                $shell.Streams.Error.Count | Should -Be 2
                foreach ($record in $shell.Streams.Error) { Assert-StoredMethodFault $record $methodReference }
                $rows.Count | Should -Be 2
                [object]::ReferenceEquals($rows[0].Marker, $marker) | Should -BeTrue
                $rows[1] | Should -BeExactly 'next statement'
            } else {
                $stored.Calls | Should -Be 1
                $stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                Assert-StoredMethodFault $stop.ErrorRecord $methodReference
                $rows.Count | Should -Be 0
            }
        } finally {
            $rows.Dispose()
            $shell.Dispose()
            $space.Dispose()
        }
    }

    It "writes collection elements in order for stored values and fallbacks" {
        $script:nativeConfig.Value = [int[]]@(17, 19)
        $fromStore = @(Get-DbatoolsConfigValue -Name $script:nativeConfigKey.ToUpperInvariant())
        $fromStore.Count | Should -Be 2
        $fromStore[0] | Should -Be 17
        $fromStore[1] | Should -Be 19
        $fromFallback = @(Get-DbatoolsConfigValue ($script:nativeConfigKey + ".missing") @("Mandatory", "Optional"))
        $fromFallback.Count | Should -Be 2
        $fromFallback[0] | Should -BeExactly "Mandatory"
        $fromFallback[1] | Should -BeExactly "Optional"
    }

    It "returns a null value when NotNull is explicitly false" -Tag "NativeChecklist:switch-false" {
        $nullValue = Get-DbatoolsConfigValue -FullName ($script:nativeConfigKey + ".missing") -NotNull:$false
        $nullValue | Should -BeNullOrEmpty
    }

    It "names the normalized requested key when NotNull rejects a missing value" {
        $missingKey = $script:nativeConfigKey + ".MISSING"
        $normalizedKey = $missingKey.ToLowerInvariant()
        $caught = $null
        try {
            $null = Get-DbatoolsConfigValue -FullName $missingKey -NotNull
        } catch {
            $caught = $PSItem
        }
        ($caught.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "dbatools_Get-DbatoolsConfigValue"
        $caught.Exception.GetType().FullName | Should -BeExactly "System.Exception"
        $caught.Exception.InnerException | Should -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be "InvalidData"
        $caught.CategoryInfo.Reason | Should -BeExactly "Exception"
        $caught.TargetObject | Should -BeExactly $normalizedKey
        $caught.Exception.Message | Should -BeExactly "No Configuration Value available for $normalizedKey"
    }
}

Describe "Missing configuration value error records" {
    BeforeAll {
        $missingConfigKey = 'native.missing.' + [guid]::NewGuid().ToString('N')
        $scriptModule = Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1
        # Capture the pinned Stop-Function record on this leg, with the separately proven key correction.
        $reference = & $scriptModule {
            param($Key)
            try {
                Stop-Function -FunctionName Get-DbatoolsConfigValue -Message "No Configuration Value available for $Key" -EnableException $true -Category InvalidData -Target $Key
            } catch {
                $_
            }
        } $missingConfigKey
        $reference | Should -BeOfType System.Management.Automation.ErrorRecord
        $recordId = $reference.FullyQualifiedErrorId + ',' + (Get-Command Get-DbatoolsConfigValue -CommandType Cmdlet).ImplementingType.FullName

        if (-not ('NativeConfigValueTests.RecordControlCommand' -as [type])) {
            Add-Type -TypeDefinition @'
using System.Management.Automation;
namespace NativeConfigValueTests {
    [Cmdlet(VerbsDiagnostic.Test, "NativeConfigRecordControl")]
    public sealed class RecordControlCommand : PSCmdlet {
        [Parameter(Mandatory = true)]
        public ErrorRecord Source { get; set; }
        protected override void ProcessRecord() {
            ThrowTerminatingError(new ErrorRecord(Source.Exception, Source.FullyQualifiedErrorId,
                Source.CategoryInfo.Category, Source.TargetObject));
        }
    }
}
'@
        }
        $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Test-NativeConfigRecordControl', ([NativeConfigValueTests.RecordControlCommand]), $null
        $initialState.Commands.Add($entry)
        $getterType = (Get-Command Get-DbatoolsConfigValue -CommandType Cmdlet).ImplementingType
        $getterEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbatoolsConfigValue', $getterType, $null
        $initialState.Commands.Add($getterEntry)
        $errorRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
        $errorRunspace.Open()
        $errorShell = [powershell]::Create()
        $errorShell.Runspace = $errorRunspace
        $errorCase = {
            param($Mode, $Command, $Arguments)
            $global:nativeLookupErrors = @()
            $global:nativeLookupCaught = $null
            $global:nativeLookupContinued = $false
            $Error.Clear()
            $Arguments.ErrorVariable = 'global:nativeLookupErrors'
            if ($Mode -in 'Stop', 'SilentlyContinue') { $Arguments.ErrorAction = $Mode }
            if ($Mode -eq 'try') {
                try { & $Command @Arguments } catch { $global:nativeLookupCaught = $_ }
            } else {
                & $Command @Arguments
            }
            $global:nativeLookupContinued = $true
        }
        function Assert-ConfigStopRecord {
            param($Record)
            $Record | Should -BeOfType System.Management.Automation.ErrorRecord
            $Record.FullyQualifiedErrorId | Should -BeExactly $recordId
            $Record.Exception.GetType().FullName | Should -BeExactly $reference.Exception.GetType().FullName
            $Record.Exception.Message | Should -BeExactly $reference.Exception.Message
            $Record.Exception.InnerException | Should -Be $reference.Exception.InnerException
            $Record.CategoryInfo.Category | Should -Be $reference.CategoryInfo.Category
            $Record.CategoryInfo.Reason | Should -BeExactly $reference.CategoryInfo.Reason
            $Record.CategoryInfo.Activity | Should -BeExactly 'Get-DbatoolsConfigValue'
            $Record.CategoryInfo.TargetName | Should -BeExactly $reference.CategoryInfo.TargetName
            $Record.CategoryInfo.TargetType | Should -BeExactly $reference.CategoryInfo.TargetType
            $Record.TargetObject | Should -BeExactly $reference.TargetObject
            $Record.ErrorDetails | Should -Be $reference.ErrorDetails
        }
        function Invoke-ConfigStopCase {
            param($Mode, $Command, $Arguments)
            $errorShell.Commands.Clear()
            $errorShell.Streams.ClearStreams()
            $invocation = $errorShell.AddScript($errorCase.ToString()).AddArgument($Mode).AddArgument($Command).AddArgument($Arguments)
            $invokeThrew = $false
            try { $null = $invocation.Invoke() } catch { $invokeThrew = $true }
            $variables = $errorShell.Runspace.SessionStateProxy
            [pscustomobject]@{
                Entries = @($variables.GetVariable('nativeLookupErrors'))
                History = @($variables.GetVariable('Error'))
                Caught = $variables.GetVariable('nativeLookupCaught')
                Continued = $variables.GetVariable('nativeLookupContinued')
                Stream = @($errorShell.Streams.Error)
                InvokeThrew = $invokeThrew
            }
        }
    }

    AfterAll {
        if ($null -ne $errorShell) { $errorShell.Dispose() }
        if ($null -ne $errorRunspace) { $errorRunspace.Dispose() }
    }

    It "preserves the complete engine sequence in <Mode> mode" -TestCases @(
        @{ Mode = 'plain' }
        @{ Mode = 'try' }
        @{ Mode = 'Stop' }
        @{ Mode = 'SilentlyContinue' }
    ) {
        param($Mode)
        $engine = Invoke-ConfigStopCase $Mode 'Test-NativeConfigRecordControl' @{ Source = $reference }
        $actual = Invoke-ConfigStopCase $Mode 'Get-DbatoolsConfigValue' @{ FullName = $missingConfigKey; NotNull = $true }
        $actual.Continued | Should -Be $engine.Continued
        $actual.InvokeThrew | Should -Be $engine.InvokeThrew
        ($null -ne $actual.Caught) | Should -Be ($null -ne $engine.Caught)
        if ($null -ne $actual.Caught) { Assert-ConfigStopRecord $actual.Caught }
        foreach ($sequence in 'Entries', 'History', 'Stream') {
            $actual.$sequence.Count | Should -Be $engine.$sequence.Count
            for ($i = 0; $i -lt $engine.$sequence.Count; $i++) {
                $entry = $actual.$sequence[$i]
                $example = $engine.$sequence[$i]
                $entry.GetType().FullName | Should -BeExactly $example.GetType().FullName
                if ($entry -is [System.Management.Automation.ErrorRecord]) {
                    $record = $entry
                    $engineRecord = $example
                } else {
                    $record = $entry.ErrorRecord
                    $engineRecord = $example.ErrorRecord
                }
                ($record.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly ($engineRecord.FullyQualifiedErrorId -split ',')[0]
                $record.Exception.GetType().FullName | Should -BeExactly $engineRecord.Exception.GetType().FullName
                if ($engineRecord.Exception.GetType() -eq $reference.Exception.GetType()) {
                    Assert-ConfigStopRecord $record
                } else {
                    $record.CategoryInfo.Category | Should -Be $engineRecord.CategoryInfo.Category
                    $record.CategoryInfo.Reason | Should -BeExactly $engineRecord.CategoryInfo.Reason
                    $record.TargetObject | Should -Be $engineRecord.TargetObject
                }
            }
        }
        if ($Mode -eq 'try') {
            $actual.Entries.Count | Should -Be 1
            $actual.Entries[0] | Should -BeOfType System.Management.Automation.CmdletInvocationException
            $actual.History.Count | Should -Be 1
            $actual.History[0] | Should -BeOfType System.Management.Automation.ErrorRecord
        }
    }
}
