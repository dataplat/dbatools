#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaXESessionTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input.
# NativeChecklist: whatif-confirm N/A -- the command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
# NativeChecklist: azure-sqldb N/A -- the command opens no SQL Server connection; it copies SSMS template files between local folders (https://learn.microsoft.com/sql/relational-databases/extended-events/use-the-ssms-xe-profiler).
# NativeChecklist: sql2005 N/A -- the command opens no SQL Server connection; it copies SSMS template files between local folders.

Describe "Native Copy-DbaXESessionTemplate" -Tag IntegrationTests {
    BeforeAll {
        $moduleBase = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
        $moduleTemplates = Join-Path -Path $moduleBase -ChildPath "bin\XEtemplates"
        $customName = "nativecustom_" + [guid]::NewGuid().ToString("N")
        $customFolder = Join-Path -Path $TestDrive -ChildPath "custom"
        $null = New-Item -ItemType Directory -Path $customFolder
        $customTemplate = @"
<event_sessions xmlns="http://schemas.microsoft.com/sqlserver/2008/07/extendedeventconfig">
  <event_session name="$customName" maxMemory="4" eventRetentionMode="allowSingleEventLoss" trackCausality="false" dispatchLatency="30" maxEventSize="0" memoryPartitionMode="none">
    <templateCategory>Native</templateCategory>
    <templateName>$customName</templateName>
    <templateDescription>A template dbatools does not ship.</templateDescription>
  </event_session>
</event_sessions>
"@
        Set-Content -Path (Join-Path -Path $customFolder -ChildPath "$customName.xml") -Value $customTemplate

        # The pinned Get-DbaXESessionTemplate runs Get-ChildItem "$(Join-DbaPath $directory *.xml)". This reads
        # the record Get-ChildItem writes for that path on this leg and edition, and asserts the port's record
        # is the same in everything but the FullyQualifiedErrorId's owner suffix, which is the writing cmdlet's
        # type (harness-edits.md, "Operator decision: Copy-DbaXESessionTemplate missing-folder error owner").
        function Assert-ChildItemRecord {
            param(
                [Parameter(Mandatory)]
                $Record,
                [Parameter(Mandatory)]
                [string]$SourcePath,
                [Parameter(Mandatory)]
                [string]$ErrorId,
                [Parameter(Mandatory)]
                [string]$ExceptionType
            )
            $upstreamErrors = $null
            $null = Get-ChildItem (Join-DbaPath $SourcePath "*.xml") -ErrorAction SilentlyContinue -ErrorVariable upstreamErrors
            @($upstreamErrors).Count | Should -Be 1
            $upstream = $upstreamErrors[0]
            $upstream.FullyQualifiedErrorId | Should -BeExactly "$ErrorId,Microsoft.PowerShell.Commands.GetChildItemCommand"
            $upstream.Exception.GetType().FullName | Should -BeExactly $ExceptionType

            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.Exception.GetType().FullName | Should -BeExactly $upstream.Exception.GetType().FullName
            $Record.Exception.Message | Should -BeExactly $upstream.Exception.Message
            $Record.CategoryInfo.Category | Should -Be $upstream.CategoryInfo.Category
            $Record.CategoryInfo.Reason | Should -BeExactly $upstream.CategoryInfo.Reason
            $Record.TargetObject | Should -Be $upstream.TargetObject
            $Record.FullyQualifiedErrorId | Should -BeExactly "$ErrorId,Dataplat.Dbatools.Commands.CopyDbaXESessionTemplateCommand"
        }
    }

    It "copies only the non-Microsoft templates into a destination folder it creates" -Tag NativeChecklist:switch-false {
        $destination = Join-Path -Path $TestDrive -ChildPath "new\nested"
        $splatCopy = @{
            Destination     = $destination
            EnableException = $false
            WarningVariable = "copyWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $result = Copy-DbaXESessionTemplate @splatCopy 6>$null
        $result | Should -BeNullOrEmpty
        $copyWarnings | Should -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $destination -ChildPath "Login Tracker.xml") | Should -BeTrue
        Test-Path -Path (Join-Path -Path $destination -ChildPath "Activity Tracking.xml") | Should -BeFalse
        @(Get-ChildItem -Path $destination -Filter *.xml).Count | Should -Be 20
    }

    It "copies a custom template that has no dbatools metadata" {
        $destination = Join-Path -Path $TestDrive -ChildPath "customcopy"
        $splatCopy = @{
            Path            = $customFolder
            Destination     = $destination
            WarningVariable = "customWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $null = Copy-DbaXESessionTemplate @splatCopy 6>$null
        $customWarnings | Should -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $destination -ChildPath "$customName.xml") | Should -BeTrue
    }

    It "continues with the next source folder after a missing one" -Tag NativeChecklist:multi-instance-failure {
        $destination = Join-Path -Path $TestDrive -ChildPath "multicopy"
        $splatCopy = @{
            Path            = @((Join-Path -Path $TestDrive -ChildPath "doesnotexist"), $moduleTemplates)
            Destination     = $destination
            ErrorAction     = "SilentlyContinue"
            WarningVariable = "multiWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $null = Copy-DbaXESessionTemplate @splatCopy 6>$null
        $multiWarnings | Should -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $destination -ChildPath "Login Tracker.xml") | Should -BeTrue
    }

    # Review b2451041 and 9b24c78f: a missing folder, plain or written with a wildcard, ends Get-ChildItem's
    # lookup with its non-terminating PathNotFound record, one per folder in -Path order, and the later folders
    # are still copied. Everything but the id's owner suffix is Get-ChildItem's own record; the suffix is the
    # writing cmdlet's type, because a native cmdlet cannot attach Get-ChildItem's identity without forging it
    # (pinned: PathNotFound,Microsoft.PowerShell.Commands.GetChildItemCommand; harness-xefqid-20261029).
    It "writes Get-ChildItem's PathNotFound record for each missing folder, in order, and copies the later folders" {
        $missingPlain = Join-Path -Path $TestDrive -ChildPath "missingplain"
        $missingRoot = Join-Path -Path $TestDrive -ChildPath "missingroot"
        $destination = Join-Path -Path $TestDrive -ChildPath "wildcardcopy"
        $splatCopy = @{
            Path            = @($missingPlain, (Join-Path -Path $missingRoot -ChildPath "*"), $customFolder)
            Destination     = $destination
            ErrorAction     = "Continue"
            ErrorVariable   = "missingErrors"
            WarningVariable = "missingWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $streamed = @(Copy-DbaXESessionTemplate @splatCopy 2>&1 6>$null)
        $missingWarnings | Should -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $destination -ChildPath "$customName.xml") | Should -BeTrue

        $streamed.Count | Should -Be 2
        @($missingErrors).Count | Should -Be 2
        $expectedTargets = @($missingPlain, $missingRoot)
        for ($index = 0; $index -lt 2; $index++) {
            $record = $streamed[$index]
            $record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $record | Should -Be $missingErrors[$index]
            $record.Exception.GetType().FullName | Should -Be "System.Management.Automation.ItemNotFoundException"
            $record.Exception.Message | Should -BeExactly "Cannot find path '$($expectedTargets[$index])' because it does not exist."
            $record.CategoryInfo.Category | Should -Be "ObjectNotFound"
            $record.TargetObject | Should -BeExactly $expectedTargets[$index]
            $record.FullyQualifiedErrorId | Should -BeExactly "PathNotFound,Dataplat.Dbatools.Commands.CopyDbaXESessionTemplateCommand"
            Assert-ChildItemRecord -Record $record -SourcePath $splatCopy.Path[$index] -ErrorId "PathNotFound" -ExceptionType "System.Management.Automation.ItemNotFoundException"
        }
    }

    # Review 001b91eb: besides a missing folder, Get-ChildItem writes a non-terminating record and reads the next
    # path for a missing drive (DriveNotFound), a missing provider (ProviderNotFound) and a provider without item
    # support (NotSupported, category NotImplemented, no target). One test per id; each compares the port's record
    # with Get-ChildItem's for the same path on this leg, and the later folder is still copied.
    It "writes Get-ChildItem's DriveNotFound record for a folder on a missing drive and copies the later folders" {
        $missingDrive = "nativexe" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $missingSource = "$($missingDrive):\templates"
        $destination = Join-Path -Path $TestDrive -ChildPath "drivecopy"
        $splatCopy = @{
            Path            = @($missingSource, $customFolder)
            Destination     = $destination
            ErrorAction     = "Continue"
            ErrorVariable   = "driveErrors"
            WarningVariable = "driveWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $streamed = @(Copy-DbaXESessionTemplate @splatCopy 2>&1 6>$null)
        $driveWarnings | Should -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $destination -ChildPath "$customName.xml") | Should -BeTrue

        $streamed.Count | Should -Be 1
        @($driveErrors).Count | Should -Be 1
        $streamed[0] | Should -Be $driveErrors[0]
        $streamed[0].Exception.Message | Should -BeExactly "Cannot find drive. A drive with the name '$missingDrive' does not exist."
        $streamed[0].TargetObject | Should -BeExactly $missingDrive
        Assert-ChildItemRecord -Record $streamed[0] -SourcePath $missingSource -ErrorId "DriveNotFound" -ExceptionType "System.Management.Automation.DriveNotFoundException"
    }

    It "writes Get-ChildItem's ProviderNotFound record for a folder under a missing provider and copies the later folders" {
        $missingProvider = "nativexe" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $missingSource = "$($missingProvider)::C:\templates"
        $destination = Join-Path -Path $TestDrive -ChildPath "providercopy"
        $splatCopy = @{
            Path            = @($missingSource, $customFolder)
            Destination     = $destination
            ErrorAction     = "Continue"
            ErrorVariable   = "providerErrors"
            WarningVariable = "providerWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $streamed = @(Copy-DbaXESessionTemplate @splatCopy 2>&1 6>$null)
        $providerWarnings | Should -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $destination -ChildPath "$customName.xml") | Should -BeTrue

        $streamed.Count | Should -Be 1
        @($providerErrors).Count | Should -Be 1
        $streamed[0] | Should -Be $providerErrors[0]
        $streamed[0].Exception.Message | Should -BeExactly "Cannot find a provider with the name '$missingProvider'."
        $streamed[0].TargetObject | Should -BeExactly $missingProvider
        Assert-ChildItemRecord -Record $streamed[0] -SourcePath $missingSource -ErrorId "ProviderNotFound" -ExceptionType "System.Management.Automation.ProviderNotFoundException"
    }

    It "writes Get-ChildItem's NotSupported record for a folder under a provider without item support and copies the later folders" {
        # A provider with no item, container or navigation support, loaded only into this session under a unique
        # name, so parallel legs share nothing.
        $suffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $flatProvider = "NativeXeFlat$suffix"
        $providerSource = "using System.Management.Automation; using System.Management.Automation.Provider; [CmdletProvider(""$flatProvider"", ProviderCapabilities.None)] public sealed class NativeXeFlatProvider$suffix : CmdletProvider { }"
        $providerType = Add-Type -TypeDefinition $providerSource -PassThru -WarningAction SilentlyContinue
        $null = Import-Module -Assembly $providerType.Assembly
        $flatSource = "$($flatProvider)::C:\templates"
        $destination = Join-Path -Path $TestDrive -ChildPath "flatcopy"
        $splatCopy = @{
            Path            = @($flatSource, $customFolder)
            Destination     = $destination
            ErrorAction     = "Continue"
            ErrorVariable   = "flatErrors"
            WarningVariable = "flatWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $streamed = @(Copy-DbaXESessionTemplate @splatCopy 2>&1 6>$null)
        $flatWarnings | Should -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $destination -ChildPath "$customName.xml") | Should -BeTrue

        $streamed.Count | Should -Be 1
        @($flatErrors).Count | Should -Be 1
        $streamed[0] | Should -Be $flatErrors[0]
        $streamed[0].CategoryInfo.Category | Should -Be "NotImplemented"
        $streamed[0].TargetObject | Should -BeNullOrEmpty
        Assert-ChildItemRecord -Record $streamed[0] -SourcePath $flatSource -ErrorId "NotSupported" -ExceptionType "System.Management.Automation.PSNotSupportedException"
    }

    It "warns when the destination folder cannot be created and throws under EnableException" -Tag NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $blocker = Join-Path -Path $TestDrive -ChildPath "blocker.txt"
        Set-Content -Path $blocker -Value "a file, not a folder"
        $destination = Join-Path -Path $blocker -ChildPath "sub"
        $splatWarn = @{
            Path            = $customFolder
            Destination     = $destination
            EnableException = $false
            WarningVariable = "blockedWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $result = Copy-DbaXESessionTemplate @splatWarn 6>$null
        $result | Should -BeNullOrEmpty
        ($blockedWarnings -join " ") | Should -Match "Failure"
        { Copy-DbaXESessionTemplate -Path $customFolder -Destination $destination -EnableException 6>$null } | Should -Throw
        Test-Path -Path $destination | Should -BeFalse
    }
}
