#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaDiagnosticQueryScript",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When the pipeline ends at the first script" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The command downloads the scripts from Glenn
            # Berry's resources page, and Select-Object -First 1 stops it at the first file it saved.
            $scriptPath = "$TestDrive\DiagnosticQueries"
            $null = New-Item -Path $scriptPath -ItemType Directory -Force
            $scriptRunspace = [runspacefactory]::CreateRunspace()
            $scriptRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $scriptRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $scriptShell = [powershell]::Create()
            $scriptShell.Runspace = $scriptRunspace
            $firstScript = $scriptShell.AddCommand("Save-DbaDiagnosticQueryScript").AddParameter("Path", $scriptPath).AddCommand("Select-Object").AddParameter("First", 1).Invoke()
            $scriptRecords = @($scriptShell.Streams.Progress)
            $scriptShell.Dispose()
            $scriptRunspace.Dispose()
        }

        It "Saves a script" {
            $firstScript.Name | Should -BeLike "SQLServerDiagnosticQueries_*.sql"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $scriptRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $scriptRecords | Where-Object Activity -eq "Downloading Glenn Berry's most recent DMVs" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}