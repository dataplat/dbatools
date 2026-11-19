#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRandomizedDatasetTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- No pinned parameter accepts pipeline input; multiple Path values are covered below.
# NativeChecklist: multi-instance-failure N/A -- No instance or computer parameter; local provider errors are tested below.
# NativeChecklist: whatif-confirm N/A -- Read-only local template enumeration; the pinned command has no SupportsShouldProcess.
# NativeChecklist: azure-sqldb N/A -- The command reads client-local JSON template files and has no database endpoint operation. Azure SQL Database has no client file-system interface: https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server.
# NativeChecklist: sql-login N/A -- No SqlCredential or SqlInstance parameter, and no SQL connection.

Describe "Native Get-DbaRandomizedDatasetTemplate" -Tag IntegrationTests {
    BeforeAll {
        $fixtureRoot = Join-Path $TestDrive ("dbatoolsci_dataset_" + [guid]::NewGuid().ToString('N'))
        $first = Join-Path $fixtureRoot 'first'
        $second = Join-Path $fixtureRoot 'second'
        $null = New-Item -Path $first, $second -ItemType Directory -Force # teardown-ok: only creates directories below TestDrive; AfterAll removes fixtureRoot and Pester also removes TestDrive.
        $firstFile = Join-Path $first 'native_first.json'
        $secondFile = Join-Path $second 'native_second.json'
        $otherFile = Join-Path $first 'native_other.json'
        Set-Content -LiteralPath $firstFile, $secondFile, $otherFile -Value '{"Columns":[]}' # teardown-ok: all three files are under TestDrive and removed with fixtureRoot in AfterAll.
        Set-Content -LiteralPath (Join-Path $first 'not-a-template.txt') -Value 'not JSON' # teardown-ok: the file is under TestDrive and removed with fixtureRoot in AfterAll.
        $moduleBase = [Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase
        $defaultDirectory = Join-Path $moduleBase 'bin/randomizer/templates'
        $defaultFiles = @(Get-ChildItem -LiteralPath $defaultDirectory -Filter '*.json')
        $nativeTemplateType = (Get-Command Get-DbaRandomizedDatasetTemplate -CommandType Cmdlet).ImplementingType.FullName

        function Invoke-NativeTemplateRecordCase {
            param([string]$BadPath, [string]$Mode)
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $type = (Get-Command Get-DbaRandomizedDatasetTemplate -CommandType Cmdlet).ImplementingType
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbaRandomizedDatasetTemplate', $type, $null
            $state.Commands.Add($entry)
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [System.Management.Automation.PowerShell]::Create()
            $captured = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                # Isolate history from Pester and capture the entire invocation, including a stopping pipeline.
                $null = $shell.AddScript(@'
param($badPath, $mode)
$ErrorActionPreference = 'Continue'
$Error.Clear()
$global:NativeTemplateErrors = @()
$arguments = @{ Path = $badPath; ExcludeDefault = $true; ErrorVariable = '+global:NativeTemplateErrors' }
if ($mode -eq 'EnableException') { $arguments.EnableException = $true }
if ($mode -eq 'ErrorActionStop') { $arguments.ErrorAction = 'Stop' }
if ($mode -eq 'SilentlyContinue') { $arguments.ErrorAction = 'SilentlyContinue' }
if ($mode -eq 'CallerTry') {
    try {
        Get-DbaRandomizedDatasetTemplate @arguments
        'native-template-next'
    } catch { [pscustomobject]@{ NativeTemplateCaught = $PSItem } }
} else {
    Get-DbaRandomizedDatasetTemplate @arguments
    'native-template-next'
}
'@).AddArgument($BadPath).AddArgument($Mode)
                $escaped = $null
                try { $null = $shell.Invoke($null, $captured) } catch { $escaped = $PSItem }
                [pscustomobject]@{
                    Output = @($captured)
                    Errors = @($runspace.SessionStateProxy.GetVariable('NativeTemplateErrors'))
                    History = @($runspace.SessionStateProxy.GetVariable('Error'))
                    Stream = @($shell.Streams.Error)
                    Warnings = @($shell.Streams.Warning)
                    State = $shell.InvocationStateInfo.State.ToString()
                    Escaped = $escaped
                }
            } finally {
                $shell.Dispose()
                $runspace.Dispose()
                $captured.Dispose()
            }
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $fixtureRoot) {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction Stop
        }
    }

    It "returns the built-in JSON template names and full paths in file order" {
        $rows = @(Get-DbaRandomizedDatasetTemplate)
        $defaultFiles.Count | Should -BeGreaterThan 0
        @($rows.FullName) | Should -Be @($defaultFiles.FullName)
        @($rows.BaseName) | Should -Be @($defaultFiles.BaseName)
        foreach ($row in $rows) {
            @($row.PSObject.Properties.Name) | Should -Be @('BaseName', 'FullName')
            $row.PSObject.TypeNames[0] | Should -Be 'Selected.System.IO.FileInfo'
        }
    }

    It "returns custom JSON files without reading their contents" {
        Set-Content -LiteralPath $otherFile -Value 'not valid JSON' # teardown-ok: the TestDrive file is restored in finally and deleted by AfterAll.
        try {
            $rows = @(Get-DbaRandomizedDatasetTemplate -Path $first -ExcludeDefault -EnableException)
            @($rows.BaseName) | Should -Be @('native_first', 'native_other')
            @($rows.FullName) | Should -Be @($firstFile, $otherFile)
        } finally { Set-Content -LiteralPath $otherFile -Value '{"Columns":[]}' } # teardown-ok: restores the fixture contents; AfterAll removes the TestDrive file.
    }

    It "adds custom templates after the built-in templates" {
        $rows = @(Get-DbaRandomizedDatasetTemplate -Path $second)
        @($rows.FullName) | Should -Be (@($defaultFiles.FullName) + @($secondFile))
    }

    It "reads each supplied custom directory once in Path order" {
        $rows = @(Get-DbaRandomizedDatasetTemplate -Path $second, $first -ExcludeDefault -EnableException)
        @($rows.FullName) | Should -Be @($secondFile, $firstFile, $otherFile)
    }

    It "filters by base name without case sensitivity" {
        $rows = @(Get-DbaRandomizedDatasetTemplate -Path $first -ExcludeDefault -Template 'NATIVE_FIRST')
        @($rows.FullName) | Should -Be @($firstFile)
    }

    It "does not enumerate the working directory when a requested directory has no templates" {
        $empty = Join-Path $fixtureRoot 'empty'
        $working = Join-Path $fixtureRoot 'working'
        $null = New-Item -Path $empty, $working -ItemType Directory -Force # teardown-ok: TestDrive children removed by AfterAll.
        Set-Content -LiteralPath (Join-Path $working 'unrelated.txt') -Value 'not a template' # teardown-ok: TestDrive file removed by AfterAll.
        Push-Location -LiteralPath $working
        try {
            @(Get-DbaRandomizedDatasetTemplate -Path $empty -ExcludeDefault).Count | Should -Be 0
            @(Get-DbaRandomizedDatasetTemplate -Path (Join-Path $fixtureRoot 'missing') -ExcludeDefault -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally { Pop-Location }
    }

    It "treats Template filter values as exact names" {
        @(Get-DbaRandomizedDatasetTemplate -Path $first -ExcludeDefault -Template 'native_*').Count | Should -Be 0
    }

    It "includes defaults when ExcludeDefault is explicitly false" -Tag 'NativeChecklist:switch-false' {
        @((Get-DbaRandomizedDatasetTemplate -ExcludeDefault:$false).FullName) | Should -Be @($defaultFiles.FullName)
    }

    It "keeps provider errors non-terminating with EnableException <Enabled>" -ForEach @(@{ Enabled = $false }, @{ Enabled = $true }) -Tag 'NativeChecklist:enable-exception', 'NativeChecklist:switch-false' {
        $providerErrors = @()
        $continued = $false
        $caught = $null
        try {
            $null = Get-DbaRandomizedDatasetTemplate -Path (Join-Path $fixtureRoot 'missing') -ExcludeDefault -EnableException:$Enabled -ErrorAction SilentlyContinue -ErrorVariable providerErrors
            $continued = $true
        } catch { $caught = $PSItem }
        $continued | Should -BeTrue
        $caught | Should -BeNullOrEmpty
        $providerErrors.Count | Should -Be 1
        $providerErrors[0].Exception | Should -BeOfType ([System.Management.Automation.ItemNotFoundException])
        $providerErrors[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
    }

    # Pin probe pinned-paths-r2-aa-20261112 measures these Resolve-Path records on both editions.
    # Part A and watchman 1ad88f5a4989c191 allow the engine's own suffix and Activity, without an override.
    It "preserves the <Id> provider record with EnableException <Enabled>" -ForEach @(
        @{ Id = 'PathNotFound'; Enabled = $false }, @{ Id = 'PathNotFound'; Enabled = $true },
        @{ Id = 'DriveNotFound'; Enabled = $false }, @{ Id = 'DriveNotFound'; Enabled = $true },
        @{ Id = 'ProviderNotFound'; Enabled = $false }, @{ Id = 'ProviderNotFound'; Enabled = $true }
    ) {
        $badPath = switch ($Id) {
            'PathNotFound' { Join-Path $fixtureRoot 'missing' }
            'DriveNotFound' { 'nativeMissingDrive:\templates' }
            'ProviderNotFound' { 'nativeMissingProvider::templates' }
        }
        $referenceErrors = @()
        $null = Resolve-Path -Path ($badPath + '\*.json') -ErrorAction SilentlyContinue -ErrorVariable referenceErrors
        $referenceErrors.Count | Should -Be 1
        $reference = $referenceErrors[0]
        $reference.FullyQualifiedErrorId | Should -Be "$Id,Microsoft.PowerShell.Commands.ResolvePathCommand"
        $reference.CategoryInfo.Activity | Should -Be 'Resolve-Path'

        $nativeErrors = @()
        $warnings = @()
        $rows = @(Get-DbaRandomizedDatasetTemplate -Path $badPath -ExcludeDefault -EnableException:$Enabled -ErrorAction SilentlyContinue -ErrorVariable nativeErrors -WarningVariable warnings)
        $rows.Count | Should -Be 0
        $warnings.Count | Should -Be 0
        $nativeErrors.Count | Should -Be 1
        $actual = $nativeErrors[0]
        $actual.FullyQualifiedErrorId | Should -Be "$Id,$nativeTemplateType"
        $actual.CategoryInfo.Activity | Should -Be 'Get-DbaRandomizedDatasetTemplate'
        $actual.InvocationInfo.MyCommand.Name | Should -Be 'Get-DbaRandomizedDatasetTemplate'
        $actual.Exception.GetType().FullName | Should -Be $reference.Exception.GetType().FullName
        $actual.Exception.Message | Should -BeExactly $reference.Exception.Message
        $actual.Exception.HResult | Should -Be $reference.Exception.HResult
        $actual.Exception.InnerException | Should -BeNullOrEmpty
        $reference.Exception.InnerException | Should -BeNullOrEmpty
        $actual.CategoryInfo.Category | Should -Be $reference.CategoryInfo.Category
        $actual.CategoryInfo.Reason | Should -BeExactly $reference.CategoryInfo.Reason
        $actual.CategoryInfo.TargetName | Should -BeExactly $reference.CategoryInfo.TargetName
        $actual.CategoryInfo.TargetType | Should -BeExactly $reference.CategoryInfo.TargetType
        $actual.TargetObject | Should -BeExactly $reference.TargetObject
        $actual.ErrorDetails | Should -BeNullOrEmpty
        $reference.ErrorDetails | Should -BeNullOrEmpty
    }

    # Installed engine-record policy (2026-11-12): assert every entry, without filtering wrappers or copies.
    # Complete compiled WriteError routes are measured by policy probe 59268719 and ctor-owner-record-native-am3.
    It "preserves complete <Id> error sequences in <Mode> mode" -ForEach @(
        foreach ($recordId in 'PathNotFound', 'DriveNotFound', 'ProviderNotFound') {
            foreach ($callMode in 'Plain', 'CallerTry', 'ErrorActionStop', 'SilentlyContinue', 'EnableException') {
                @{ Id = $recordId; Mode = $callMode }
            }
        }
    ) {
        $badPath = switch ($Id) {
            'PathNotFound' { Join-Path $fixtureRoot 'missing' }
            'DriveNotFound' { 'nativeMissingDrive:\templates' }
            'ProviderNotFound' { 'nativeMissingProvider::templates' }
        }
        $referenceErrors = @()
        $null = Resolve-Path -Path ($badPath + '\*.json') -ErrorAction SilentlyContinue -ErrorVariable referenceErrors
        $referenceErrors.Count | Should -Be 1
        $reference = $referenceErrors[0]
        $actual = Invoke-NativeTemplateRecordCase -BadPath $badPath -Mode $Mode
        $recordType = 'System.Management.Automation.ErrorRecord'
        $stopType = 'System.Management.Automation.ActionPreferenceStopException'
        $expectedErrors = @($recordType)
        $expectedHistory = @($recordType)
        $expectedStream = 1
        if ($Mode -eq 'ErrorActionStop') {
            $expectedErrors = @($stopType)
            $expectedHistory = @($stopType, $recordType)
            $expectedStream = 0
            $actual.State | Should -BeExactly 'Failed'
            $actual.Output.Count | Should -Be 0
        } else {
            $actual.State | Should -BeExactly 'Completed'
            $actual.Escaped | Should -BeNullOrEmpty
            $actual.Output.Count | Should -Be 1
            $actual.Output[0] | Should -BeExactly 'native-template-next'
        }
        if ($Mode -eq 'SilentlyContinue') { $expectedStream = 0 }
        $actual.Stream.Count | Should -Be $expectedStream
        $actual.Warnings.Count | Should -Be 0
        foreach ($channel in 'Errors', 'History') {
            $expected = if ($channel -eq 'Errors') { $expectedErrors } else { $expectedHistory }
            $entries = @($actual.$channel)
            $entries.Count | Should -Be @($expected).Count
            for ($index = 0; $index -lt $entries.Count; $index++) {
                $entry = $entries[$index]
                $entry.GetType().FullName | Should -BeExactly @($expected)[$index]
                $record = if ($entry -is [System.Management.Automation.ErrorRecord]) { $entry } else { $entry.ErrorRecord }
                $record.FullyQualifiedErrorId | Should -BeExactly "$Id,$nativeTemplateType"
                $record.CategoryInfo.Activity | Should -BeExactly 'Get-DbaRandomizedDatasetTemplate'
                $record.Exception.GetType().FullName | Should -BeExactly $reference.Exception.GetType().FullName
                $record.Exception.Message | Should -BeExactly $reference.Exception.Message
                $record.Exception.HResult | Should -Be $reference.Exception.HResult
                $record.Exception.InnerException | Should -BeNullOrEmpty
                $record.CategoryInfo.Category | Should -Be $reference.CategoryInfo.Category
                $record.CategoryInfo.Reason | Should -BeExactly $reference.CategoryInfo.Reason
                $record.CategoryInfo.TargetName | Should -BeExactly $reference.CategoryInfo.TargetName
                $record.CategoryInfo.TargetType | Should -BeExactly $reference.CategoryInfo.TargetType
                $record.TargetObject | Should -BeExactly $reference.TargetObject
                $record.ErrorDetails | Should -BeNullOrEmpty
            }
        }
    }

    It "returns nothing for an empty or null custom Path list with defaults excluded" {
        @(Get-DbaRandomizedDatasetTemplate -Path @() -ExcludeDefault).Count | Should -Be 0
        @(Get-DbaRandomizedDatasetTemplate -Path $null -ExcludeDefault).Count | Should -Be 0
    }

    It "treats an empty or null Template list as no filter" {
        @((Get-DbaRandomizedDatasetTemplate -Path $first -ExcludeDefault -Template @()).FullName) | Should -Be @($firstFile, $otherFile)
        @((Get-DbaRandomizedDatasetTemplate -Path $first -ExcludeDefault -Template $null).FullName) | Should -Be @($firstFile, $otherFile)
    }
}
