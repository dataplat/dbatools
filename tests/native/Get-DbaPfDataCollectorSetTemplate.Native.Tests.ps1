#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: azure-sqldb N/A -- the command opens no SQL Server connection; it reads Performance Monitor template files from the file system.
# NativeChecklist: sql-login N/A -- the pinned function has no SqlCredential parameter and connects to no SQL Server.
# NativeChecklist: pipeline-multiple N/A -- the command takes no pipeline input; every parameter binds by name or position.
# NativeChecklist: multi-instance-failure N/A -- the command has no instance parameter; several -Path folders are tested below.
# NativeChecklist: whatif-confirm N/A -- the command does not support ShouldProcess; it only reads files.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorSetTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaPfDataCollectorSetTemplate" -Tag IntegrationTests {
    BeforeAll {
        $templateFolder = Join-Path ([Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase) "bin\perfmontemplates\collectorsets"

        # A folder of the test's own files, unique per run: a custom template with a two-line description and no dbatools
        # metadata, a file that is not XML, an empty file, a file whose root is not DataCollectorSet.
        $customFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("dbatoolsci_pftemplate_" + [guid]::NewGuid().ToString("N"))
        $null = New-Item -Path $customFolder -ItemType Directory
        $withBom = New-Object System.Text.UTF8Encoding -ArgumentList $true
        $customXml = "<?xml version=""1.0"" encoding=""UTF-8""?>`r`n<DataCollectorSet>`r`n`t<Name>dbatoolsci custom</Name>`r`n`t<Description>First line`r`nsecond line</Description>`r`n`t<UserAccount>dbatoolsci\user</UserAccount>`r`n</DataCollectorSet>`r`n"
        [System.IO.File]::WriteAllText((Join-Path $customFolder "a-custom.xml"), $customXml, $withBom)
        [System.IO.File]::WriteAllText((Join-Path $customFolder "b-notxml.xml"), "this is not xml", $withBom)
        [System.IO.File]::WriteAllText((Join-Path $customFolder "c-empty.xml"), "", (New-Object System.Text.UTF8Encoding -ArgumentList $false))
        [System.IO.File]::WriteAllText((Join-Path $customFolder "d-otherroot.xml"), "<Other><Name>x</Name></Other>", $withBom)
        $missingFolder = Join-Path $customFolder "missing-folder"

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeTemplateOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaPfDataCollectorSetTemplate -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPfDataCollectorSetTemplate", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaPfDataCollectorSetTemplate @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        # The pinned -match raises .NET's own regex parse exception (pin probe 2026-11-11, both editions): its type name as
        # the error id, OperationStopped, no target.
        function Assert-NativeInvalidPattern {
            param($Record)
            if ($PSVersionTable.PSEdition -eq "Core") {
                $expectedType = "System.Text.RegularExpressions.RegexParseException"
                $expectedMessage = "Invalid pattern '[' at offset 1. Unterminated [] set."
            } else {
                $expectedType = "System.ArgumentException"
                $expectedMessage = 'parsing "[" - Unterminated [] set.'
            }
            ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly $expectedType
            $Record.Exception.GetType().FullName | Should -BeExactly $expectedType
            $Record.Exception.Message | Should -BeExactly $expectedMessage
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationStopped)
            $Record.TargetObject | Should -BeNullOrEmpty
        }

        # A -Path folder the provider cannot list: the pin's Get-ChildItem record, measured by the same call on this leg.
        # Child-command error owner (operator, 2026-11-12), Part A: the id carries the port's own cmdlet type in place of
        # GetChildItemCommand; everything else equals the Get-ChildItem record.
        function Assert-NativeListingRecord {
            param($Port, $Oracle)
            $portType = (Get-Command Get-DbaPfDataCollectorSetTemplate -CommandType Cmdlet).ImplementingType.FullName
            @($Oracle).Count | Should -BeGreaterThan 0
            @($Port).Count | Should -Be @($Oracle).Count
            for ($index = 0; $index -lt @($Oracle).Count; $index++) {
                $portRecord = @($Port)[$index]
                $oracleRecord = @($Oracle)[$index]
                $oracleRecord.FullyQualifiedErrorId | Should -BeLike "*,Microsoft.PowerShell.Commands.GetChildItemCommand"
                $portRecord.FullyQualifiedErrorId | Should -BeExactly ("{0},{1}" -f ($oracleRecord.FullyQualifiedErrorId -split ",")[0], $portType)
                $portRecord.CategoryInfo.Category | Should -Be $oracleRecord.CategoryInfo.Category
                $portRecord.CategoryInfo.Reason | Should -BeExactly $oracleRecord.CategoryInfo.Reason
                $portRecord.Exception.GetType().FullName | Should -BeExactly $oracleRecord.Exception.GetType().FullName
                $portRecord.Exception.Message | Should -BeExactly $oracleRecord.Exception.Message
                "$($portRecord.TargetObject)" | Should -BeExactly "$($oracleRecord.TargetObject)"
                ($null -eq $portRecord.Exception.InnerException) | Should -Be ($null -eq $oracleRecord.Exception.InnerException)
            }
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $customFolder) {
            Remove-Item -LiteralPath $customFolder -Recurse -Force
        }
    }

    Context "The bundled templates" {
        It "lists one template per file, each with its metadata Source" {
            $files = @(Get-ChildItem -Path (Join-Path $templateFolder "*.xml"))
            $results = @(Get-DbaPfDataCollectorSetTemplate)
            $results.Count | Should -Be $files.Count
            foreach ($result in $results) {
                $result.Name | Should -Not -BeNullOrEmpty
                $result.Source | Should -Not -BeNullOrEmpty
                $result.Description | Should -Not -BeNullOrEmpty
                $result.Path | Should -BeOfType [System.IO.FileInfo]
                $result.File | Should -BeExactly $result.Path.Name
                $result.Path.FullName | Should -BeIn $files.FullName
            }
        }

        It "shows Name, Source, UserAccount and Description by default" {
            $result = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries"
            $display = @($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            # The pin's Select-DefaultView lists them sorted by name (pin probe 2026-11-11, both editions).
            ($display -join ",") | Should -BeExactly "Description,Name,Source,UserAccount"
            (@($result.PSObject.Properties.Name) -join ",") | Should -BeExactly "Name,Source,UserAccount,Description,Path,File"
        }

        It "picks a template by its file base name, whatever its case" {
            $results = @(Get-DbaPfDataCollectorSetTemplate -Template "long running queries")
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly "Long Running Queries"
            $results[0].Source | Should -BeExactly "Brad McGehee"
        }

        It "lists every template for an empty -Template, as the pin's if (`$Template) does" {
            $all = @(Get-DbaPfDataCollectorSetTemplate | ForEach-Object Name)
            $all.Count | Should -BeGreaterThan 1
            @(Get-DbaPfDataCollectorSetTemplate -Template "" | ForEach-Object Name) | Should -Be $all
            @(Get-DbaPfDataCollectorSetTemplate -Template "long running queries", "" | ForEach-Object Name) | Should -Be @("Long Running Queries")
        }

        It "turns a wildcard -Pattern into a regex over the name and the description" {
            $results = @(Get-DbaPfDataCollectorSetTemplate -Pattern "long*")
            $results.Name | Should -Contain "Long Running Queries"
            foreach ($result in $results) {
                ($result.Name -match "long.*" -or $result.Description -match "long.*") | Should -BeTrue
            }
            @(Get-DbaPfDataCollectorSetTemplate -Pattern "dbatoolsci_matches_nothing").Count | Should -Be 0
        }
    }

    Context "A -Path folder of other files" {
        It "reads a template without metadata, keeps its description's lines and warns for a file that is not XML" {
            $results = @(Get-DbaPfDataCollectorSetTemplate -Path $customFolder -WarningAction SilentlyContinue -WarningVariable customWarnings)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly "dbatoolsci custom"
            $results[0].Source | Should -BeNullOrEmpty
            $results[0].UserAccount | Should -BeExactly "dbatoolsci\user"
            $results[0].Description | Should -BeExactly "First line`nsecond line"
            $results[0].File | Should -BeExactly "a-custom.xml"
            $customWarnings.Count | Should -Be 1
            "$($customWarnings[0])" | Should -BeLike "*Failure*"
        }

        It "stops at the file that is not XML under -EnableException" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $thrown = $null
            try {
                $null = Get-DbaPfDataCollectorSetTemplate -Path $customFolder -EnableException
            } catch {
                $thrown = $PSItem
            }
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.Exception.InnerException | Should -Not -BeNullOrEmpty
            @(Get-DbaPfDataCollectorSetTemplate -Path $customFolder -EnableException:$false -WarningAction SilentlyContinue).Count | Should -Be 1
        }

        It "writes what Get-ChildItem writes for a missing folder and goes on with the next folder" {
            $results = @(Get-DbaPfDataCollectorSetTemplate -Path $missingFolder, $customFolder -Template "a-custom" -ErrorAction SilentlyContinue -ErrorVariable missingErrors)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly "dbatoolsci custom"
            # The pin lists the folder with Get-ChildItem "$directory\*.xml": the same call on this leg is the oracle.
            $null = Get-ChildItem "$missingFolder\*.xml" -ErrorAction SilentlyContinue -ErrorVariable listingErrors
            Assert-NativeListingRecord -Port $missingErrors -Oracle $listingErrors
        }

        It "writes what Get-ChildItem writes for a missing drive and goes on with the next folder" {
            $missingDrive = "dbatoolscinodrive" + [guid]::NewGuid().ToString("N").Substring(0, 8)
            $drivePath = "$($missingDrive):\templates"
            $results = @(Get-DbaPfDataCollectorSetTemplate -Path $drivePath, $customFolder -Template "a-custom" -ErrorAction SilentlyContinue -ErrorVariable driveErrors)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly "dbatoolsci custom"
            $null = Get-ChildItem "$drivePath\*.xml" -ErrorAction SilentlyContinue -ErrorVariable driveListingErrors
            ($driveListingErrors[0].FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "DriveNotFound"
            Assert-NativeListingRecord -Port $driveErrors -Oracle $driveListingErrors
        }
    }

    Context "An invalid -Pattern" {
        It "writes the regex error for each template and goes on, outside any try" {
            $outside = Invoke-NativeTemplateOutsideTry @{ Pattern = "["; Path = $templateFolder, $customFolder; Template = "Long Running Queries", "a-custom" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativeInvalidPattern -Record $record
            }
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "stops at the first regex error under -EnableException" {
            $outside = Invoke-NativeTemplateOutsideTry @{ Pattern = "["; Path = $templateFolder, $customFolder; Template = "Long Running Queries", "a-custom"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeInvalidPattern -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "stops at the first regex error under -ErrorAction Stop, outside a try" {
            $outside = Invoke-NativeTemplateOutsideTry @{ Pattern = "["; Path = $templateFolder, $customFolder; Template = "Long Running Queries", "a-custom"; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeInvalidPattern -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }

        It "lets a caller's try catch the first regex error" {
            $callerOutput = @(try { Get-DbaPfDataCollectorSetTemplate -Pattern "[" -Path $templateFolder, $customFolder -Template "Long Running Queries", "a-custom"; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeInvalidPattern -Record $callerOutput[0]
        }
    }
}
