#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Install-DbaParquet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Version",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $script:originalParquetPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsParquet"
    }

    AfterAll {
        Set-DbatoolsConfig -FullName "Path.DbatoolsParquet" -Value $script:originalParquetPath
    }

    Context "NuGet installation" {
        It "installs Parquet.NET and managed dependencies to a custom path" {
            $installPath = Join-Path $TestDrive "parquet"

            $result = Install-DbaParquet -Path $installPath -Force -EnableException

            $result | Should -Not -BeNullOrEmpty
            $result.Installed | Should -BeTrue
            @("Parquet.dll", "Parquet.Net.dll") | Should -Contain $result.Name
            Test-Path -Path $result.Path | Should -BeTrue

            foreach ($assemblyName in "IronCompress.dll", "Microsoft.IO.RecyclableMemoryStream.dll", "Snappier.dll", "ZstdSharp.dll") {
                Test-Path -Path (Join-Path $installPath $assemblyName) | Should -BeTrue
            }
        }

        It "keeps the editions apart by installing below the configured path" {
            # The assemblies are picked for the runtime, so an installation made by the other edition
            # cannot be loaded here. Both editions share the data directory, so they only stay usable
            # side by side while each one installs into its own folder.
            $basePath = Join-Path $TestDrive "editionbase"
            Set-DbatoolsConfig -FullName "Path.DbatoolsParquet" -Value $basePath

            $result = Install-DbaParquet -Force -EnableException

            if ($PSVersionTable.PSEdition -eq "Core") {
                $expectedFolder = "core"
            } else {
                $expectedFolder = "desktop"
            }

            $result.Installed | Should -BeTrue
            Split-Path -Path $result.Path -Parent | Should -Be (Join-Path $basePath $expectedFolder)
        }
    }

    Context "When the pipeline is stopped" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. Force makes the command resolve the packages
            # from NuGet, which takes seconds, and the pipeline is stopped as soon as the first record arrives,
            # which is what Ctrl+C does. The installation goes to the test drive; the AfterAll above restores
            # the configured path, which the command changes for the whole process.
            $splatStopInstall = @{
                Path  = "$TestDrive\stoppedparquet"
                Force = $true
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $null = $stopShell.AddCommand("Install-DbaParquet").AddParameters($splatStopInstall)
            $stopAsync = $stopShell.BeginInvoke()
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not ($stopShell.Streams.Progress | Where-Object Activity -eq "Installing Parquet.NET") -and -not $stopAsync.IsCompleted -and $stopWatch.Elapsed.TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 10
            }
            $stopShell.Stop()
            $stopState = $stopShell.InvocationStateInfo.State
            $stopRecords = @($stopShell.Streams.Progress)
            $stopShell.Dispose()
            $stopRunspace.Dispose()
        }

        It "Was stopped while it was running" {
            $stopState | Should -Be "Stopped"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $stopRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $stopRecords | Where-Object Activity -eq "Installing Parquet.NET" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}
