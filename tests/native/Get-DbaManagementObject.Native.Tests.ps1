#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaManagementObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads loaded assemblies, process modules and GAC folders.
# NativeChecklist: azure-sqldb N/A -- The command never opens a SQL Server connection on any path, parameter set or pipeline input: it reads the .NET assemblies, process modules and GAC folders of computers, locally or over PowerShell remoting.
# NativeChecklist: sql-login N/A -- The pinned function declares no SqlCredential and never connects to SQL Server.
# NativeChecklist: platform cross-platform -- no Windows-only API: the GAC folder reads are skipped off Windows as the pin skips them, and remote computers are read over PowerShell remoting.

Describe "Native Get-DbaManagementObject" -Tag IntegrationTests {
    BeforeAll {
        $smoPatterns = "Microsoft.SqlServer.SMO,*", "*.smo.*", "*SqlClient*", "*sqlclient*sni*"
        $tokenTail = ", Culture=neutral, PublicKeyToken=89845dcd8080cc91`""
        $remoteServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $remoteComputer = $remoteServer.ComputerName
        $missingComputer = "dbatoolsci-nohost-$(Get-Random)"

        # What the pinned script block reads in this process, read here on its own: the SQL-related assemblies, the
        # library version, the GAC folder versions newest first and the SNI modules.
        function Get-NativeLocalState {
            $assemblies = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
                    $fullName = $PSItem.FullName
                    @($smoPatterns | Where-Object { $fullName -like $PSItem }).Count -gt 0
                })
            $library = $assemblies[0].Location
            $libraryVersion = [version](((Get-Item -LiteralPath $library).VersionInfo.ProductVersion -split "\+")[0])
            $gac = @(Get-ChildItem -Path "$env:SystemRoot\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -ErrorAction Ignore | Sort-Object Name -Descending | ForEach-Object { $PSItem.Name.Split("_")[0] })
            if (-not $gac) {
                $gac = @(Get-ChildItem -Path "$env:SystemRoot\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -ErrorAction Ignore | Sort-Object Name -Descending | ForEach-Object { $PSItem.Name.Split("_")[1] })
            }
            [pscustomobject]@{
                Assemblies     = $assemblies
                Versions       = @($assemblies | ForEach-Object { if ($PSItem.FullName -match "Version=([^,]+)") { $Matches[1] } })
                Library        = $library
                LibraryVersion = $libraryVersion
                Gac            = $gac
                Sni            = @((Get-Process -Id $PID).Modules | Where-Object ModuleName -like "*SNI*")
            }
        }

        function Test-NativeSameMajorMinor {
            param([string]$Version, [version]$Library)
            $parsed = [version]$Version
            $parsed.Major -eq $Library.Major -and $parsed.Minor -eq $Library.Minor
        }

        function Format-NativeRow {
            param($Row)
            "$($Row.ComputerName)|$($Row.Version)|$($Row.Loaded)|$(if ($null -eq $Row.Path) { '<null>' } else { $Row.Path })|$($Row.LoadTemplate)"
        }

        # The rows the pinned script block builds in this process from the independent reads: with -Library the local branch's
        # library row and the loaded assemblies it does not cover, then the GAC folders (filtered by -VersionNumber), then the
        # SNI modules, which a computer with no GAC folder never reaches.
        function Get-NativeExpectedRow {
            param($State, [switch]$Library, [int]$VersionNumber)
            $expected = New-Object System.Collections.ArrayList
            if ($Library) {
                if ($VersionNumber -eq 0 -or "$($State.LibraryVersion)".StartsWith("$VersionNumber.")) {
                    $libraryLoaded = @($State.Versions | Where-Object { Test-NativeSameMajorMinor -Version $PSItem -Library $State.LibraryVersion }).Count -gt 0
                    $null = $expected.Add("$env:COMPUTERNAME|$($State.LibraryVersion)|$libraryLoaded|$($State.Library)|Add-Type -Path $($State.Library)")
                }
                foreach ($assembly in $State.Assemblies) {
                    if ($assembly.FullName -match "Version=([^,]+)" -and -not (Test-NativeSameMajorMinor -Version $Matches[1] -Library $State.LibraryVersion)) {
                        $null = $expected.Add("$env:COMPUTERNAME|$($Matches[1])|True|$($assembly.Location)|Add-Type -Path `"$($assembly.Location)`"")
                    }
                }
            }
            foreach ($version in $State.Gac) {
                if ($VersionNumber -eq 0 -or $version.StartsWith("$VersionNumber.")) {
                    $null = $expected.Add("$env:COMPUTERNAME|$version|$($State.Versions -contains $version)|<null>|Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$version$tokenTail")
                }
            }
            if ($State.Gac) {
                foreach ($module in $state.Sni) {
                    $sniPath = $module.FileName
                    $client = @($state.Assemblies | Where-Object { $PSItem.FullName -like "*SqlClient*" -and $sniPath -like "*$([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetDirectoryName($PSItem.Location))))*" })
                    $folder = [System.IO.Path]::GetDirectoryName($sniPath)
                    while ($folder -and -not $client) {
                        $folder = [System.IO.Path]::GetDirectoryName($folder)
                        if ($folder) {
                            $candidate = Join-Path $folder "Microsoft.Data.SqlClient.dll"
                            $client = @($state.Assemblies | Where-Object Location -eq $candidate)
                        }
                    }
                    $template = if ($client) { "Add-Type -Path `"$(@($client.Location) -join ' ')`" -ReferencedAssemblies `"$sniPath`"" } else { "" }
                    $version = if ($module.FileVersionInfo.FileVersion) { $module.FileVersionInfo.FileVersion } else { "Unknown" }
                    $null = $expected.Add("$env:COMPUTERNAME|$version|True|$sniPath|$template")
                }
            }
            , @($expected)
        }
    }

    Context "The local computer" {
        It "reads the library, the loaded assemblies it does not cover, the GAC folders and the SNI modules, in that order" {
            $rows = @(Get-DbaManagementObject)
            $state = Get-NativeLocalState
            $expected = Get-NativeExpectedRow -State $state -Library
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $expected
        }

        It "returns five typed properties per row" {
            $row = @(Get-DbaManagementObject -ComputerName $env:COMPUTERNAME)[0]
            $row.PSObject.Properties.Name | Should -Be @("ComputerName", "Version", "Loaded", "Path", "LoadTemplate")
            $row.ComputerName | Should -BeOfType [string]
            $row.Version | Should -BeOfType [string]
            $row.Loaded | Should -BeOfType [bool]
            $row.Path | Should -BeOfType [string]
            $row.LoadTemplate | Should -BeOfType [string]
            $row.PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
        }

        It "reads the same for localhost and for the computer's name" {
            @(Get-DbaManagementObject -ComputerName localhost | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @(Get-DbaManagementObject -ComputerName $env:COMPUTERNAME | ForEach-Object { Format-NativeRow $PSItem })
        }

        # Correction local-version-number: the pin ran the local script block without -ArgumentList, so -VersionNumber
        # changed nothing there; here the library row and the GAC rows are filtered as a remote computer filters them.
        It "honours -VersionNumber on the local computer" {
            $state = Get-NativeLocalState
            $other = @(Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber 99)
            (@($other | ForEach-Object { Format-NativeRow $PSItem }) -join "`n") | Should -BeExactly ((Get-NativeExpectedRow -State $state -Library -VersionNumber 99) -join "`n")
            @($other | Where-Object { $PSItem.Path -eq $state.Library -and $PSItem.Version -eq "$($state.LibraryVersion)" }).Count | Should -Be 0
            $own = @(Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber $state.LibraryVersion.Major)
            (@($own | ForEach-Object { Format-NativeRow $PSItem }) -join "`n") | Should -BeExactly ((Get-NativeExpectedRow -State $state -Library -VersionNumber $state.LibraryVersion.Major) -join "`n")
            $own[0].Version | Should -BeExactly "$($state.LibraryVersion)"
            $own[0].Path | Should -BeExactly $state.Library
            $own[0].LoadTemplate | Should -BeExactly "Add-Type -Path $($state.Library)"
        }

        It "writes the pinned script block's verbose lines without the dbatools prefix" {
            $state = Get-NativeLocalState
            $verbose = @(Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            $verbose | Should -Contain "Checking currently loaded SMO, SqlClient, and related assemblies"
            $verbose | Should -Contain "Looking for included smo library at $($state.Library)"
            $verbose | Should -Contain "Did not pass a version"
            @($verbose | Where-Object { $PSItem -match "\[Get-DbaManagementObject\] Executing scriptblock against $env:COMPUTERNAME$" }).Count | Should -Be 1
        }

        # Invoke-Command2 runs the script block in this process for a local address it does not compare by name, with
        # -ArgumentList $VersionNumber, $true: the remote branch here, no library rows, and its Select-Object row type.
        It "reads a local address in this process through the script block's remote branch" {
            $state = Get-NativeLocalState
            $records = @(Get-DbaManagementObject -ComputerName 127.0.0.1 -Verbose 4>&1)
            $rows = @($records | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
            $verbose = @($records | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            (@($rows | ForEach-Object { Format-NativeRow $PSItem }) -join "`n") | Should -BeExactly ((Get-NativeExpectedRow -State $state) -join "`n")
            foreach ($row in $rows) {
                $row.PSObject.TypeNames[0] | Should -BeExactly "Selected.System.Management.Automation.PSCustomObject"
            }
            $verbose | Should -Contain "Checking currently loaded SMO, SqlClient, and related assemblies"
            @($verbose | Where-Object { $PSItem -like "Found * loaded SQL-related assemblies: *" }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem -like "Looking for included smo library at*" }).Count | Should -Be 0
            @($verbose | Where-Object { $PSItem -match "\[Get-DbaManagementObject\] Executing scriptblock against 127\.0\.0\.1$" }).Count | Should -Be 1
        }
    }

    # These tests prove the remote rows on the default session configuration (Microsoft.PowerShell) only. On a configuration
    # that preloads SMO or SqlClient the pin can show Loaded=True or an SNI LoadTemplate and the port does not: an accepted
    # difference the operator installed (harness-edits.md, "Get-DbaManagementObject: remote Loaded on a custom session
    # configuration", 2026-11-07); nothing here covers a custom or changed configuration.
    Context "A remote computer, on the default session configuration" {
        BeforeAll {
            # An independent read of the same remote computer in a session on the same configuration: the GAC folders, the
            # SQL-related assemblies loaded in that session (the pinned script block's filter) and its SNI modules.
            $remoteState = Invoke-Command -ComputerName $remoteComputer -ConfigurationName Microsoft.PowerShell -ArgumentList (, $smoPatterns) -ScriptBlock {
                param($Patterns)
                $old = @(Get-ChildItem -Path "$env:SystemRoot\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -ErrorAction Ignore | Sort-Object Name -Descending | ForEach-Object { $PSItem.Name.Split("_")[0] })
                $new = @(Get-ChildItem -Path "$env:SystemRoot\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -ErrorAction Ignore | Sort-Object Name -Descending | ForEach-Object { $PSItem.Name.Split("_")[1] })
                $loaded = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
                        $fullName = $PSItem.FullName
                        @($Patterns | Where-Object { $fullName -like $PSItem }).Count -gt 0
                    } | ForEach-Object { $PSItem.FullName })
                $sni = @((Get-Process -Id $PID).Modules | Where-Object ModuleName -like "*SNI*" | ForEach-Object {
                        [pscustomobject]@{
                            Path    = $PSItem.FileName
                            Version = if ($PSItem.FileVersionInfo.FileVersion) { $PSItem.FileVersionInfo.FileVersion } else { "Unknown" }
                        }
                    })
                [pscustomobject]@{
                    Name   = $env:COMPUTERNAME
                    Gac    = if ($old) { $old } else { $new }
                    Loaded = $loaded
                    Sni    = $sni
                }
            }
            # The pinned script block's rows for that session: the GAC folders, Loaded when a loaded assembly has the folder's
            # version, then (only when a GAC folder exists) the SNI modules, Loaded and with no LoadTemplate when no SqlClient
            # assembly is loaded.
            $remoteLoadedVersions = @($remoteState.Loaded | ForEach-Object { if ($PSItem -match "Version=([^,]+)") { $Matches[1] } })
            $remoteExpected = @($remoteState.Gac | ForEach-Object { "$($remoteState.Name)|$PSItem|$($remoteLoadedVersions -contains $PSItem)|<null>|Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$PSItem$tokenTail" })
            if ($remoteState.Gac) {
                $remoteExpected += @($remoteState.Sni | ForEach-Object { "$($remoteState.Name)|$($PSItem.Version)|True|$($PSItem.Path)|" })
            }
        }

        It "reads the remote computer's GAC folders in a remote session, none of them loaded there" {
            # The default configuration loads no SMO or SqlClient assembly (probe dd10904b measured the same), so the pinned rows
            # say Loaded=False there.
            @($remoteState.Loaded) | Should -BeNullOrEmpty
            $rows = @(Get-DbaManagementObject -ComputerName $remoteComputer)
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $remoteExpected
            foreach ($row in $rows) {
                $row.PSObject.TypeNames[0] | Should -BeExactly "Selected.System.Management.Automation.PSCustomObject"
                $row.PSObject.Properties.Name | Should -Be @("ComputerName", "Version", "Loaded", "Path", "LoadTemplate")
            }
        }

        # Probe pin-mgmtobject-20261106, remote-verbose: the remote session keeps the script block's Write-Verbose lines.
        It "writes only the dbatools verbose line for a remote computer" {
            $records = @(Get-DbaManagementObject -ComputerName $remoteComputer -Verbose 4>&1)
            $verbose = @($records | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            $verbose.Count | Should -Be 1
            $verbose[0] | Should -Match "\[Get-DbaManagementObject\] Executing scriptblock against $([regex]::Escape($remoteComputer))$"
            @($records | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be $remoteExpected.Count
        }

        It "filters the remote GAC folders by -VersionNumber" {
            $major = ([version]@($remoteState.Gac)[0]).Major
            $rows = @(Get-DbaManagementObject -ComputerName $remoteComputer -VersionNumber $major)
            @($rows.Version) | Should -Be @($remoteState.Gac | Where-Object { $PSItem.StartsWith("$major.") })
        }

        It "reads several computers, piped or named, in order" -Tag "NativeChecklist:pipeline-multiple" {
            $piped = @($env:COMPUTERNAME, $remoteComputer | Get-DbaManagementObject)
            $named = @(Get-DbaManagementObject -ComputerName $env:COMPUTERNAME, $remoteComputer)
            @($piped | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @($named | ForEach-Object { Format-NativeRow $PSItem })
            @($named.ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME, $remoteState.Name)
        }

        # The pin's Invoke-Command2 gives New-PSSession no -ConfigurationName, so the session opens on $PSSessionConfigurationName.
        # Set here in the caller's scope only; it never leaves this It.
        It "opens the remote session on the caller's `$PSSessionConfigurationName, a bare name or a full URI" {
            $PSSessionConfigurationName = "Microsoft.PowerShell"
            $bare = @(Get-DbaManagementObject -ComputerName $remoteComputer)
            @($bare | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $remoteExpected

            $missingConfiguration = "dbatoolsci.missing.$(Get-Random)"
            foreach ($value in $missingConfiguration, "http://schemas.microsoft.com/powershell/$missingConfiguration") {
                $PSSessionConfigurationName = $value
                $warnings = @()
                $rows = @(Get-DbaManagementObject -ComputerName $remoteComputer, $env:COMPUTERNAME -WarningAction SilentlyContinue -WarningVariable warnings)
                @($rows.ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME)
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaManagementObject\] Failure \| Connecting to remote server $([regex]::Escape($remoteComputer)) failed"
                "$($warnings[0])" | Should -BeLike "*$missingConfiguration*"

                $failure = $null
                try {
                    $null = Get-DbaManagementObject -ComputerName $remoteComputer -EnableException -WarningAction SilentlyContinue
                } catch {
                    $failure = $PSItem
                }
                $failure | Should -Not -BeNullOrEmpty
                $failure.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OpenError)
                $failure.Exception.Message | Should -BeLike "*$missingConfiguration*"
            }
        }
    }

    Context "A computer that cannot be reached" -Tag "NativeChecklist:multi-instance-failure" {
        It "warns and reads the next computer, under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $warnings = @()
            $rows = @(Get-DbaManagementObject -ComputerName $missingComputer, $env:COMPUTERNAME -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            @($rows.ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME)
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaManagementObject\] Failure \| Connecting to remote server $([regex]::Escape($missingComputer)) failed"
        }

        It "throws under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaManagementObject -ComputerName $missingComputer -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            $failure.FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaManagementObject(,|$)"
            # Probe pin-mgmtobject-20261106, unreachable-enable-exception: New-PSSession's OpenError and the computer as target.
            $failure.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OpenError)
            "$($failure.TargetObject)" | Should -BeExactly $missingComputer
            $failure.Exception.Message | Should -Match "^Connecting to remote server $([regex]::Escape($missingComputer)) failed"
        }
    }
}
