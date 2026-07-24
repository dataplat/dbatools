#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaReplServerSetting",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "FilePath",
                "ScriptOption",
                "InputObject",
                "Encoding",
                "Passthru",
                "NoClobber",
                "Append",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: scripting out a live replication topology needs the native RMO replication
    # libraries plus a configured distributor and publications. That end-to-end .Script() and
    # file-write path is NOT exercised here and is NOT verified by these legs - stating that plainly
    # because a coverage claim is worth less than nothing when it is wrong.
    #
    # What IS deterministic, needs no SQL Server at all, and runs identically on both editions is
    # the command's entire begin block, which the port carries into the module hop ahead of any
    # connection: the replication libraries are loaded (or, where they are absent, the command warns
    # and stops before touching an instance), and the export directory is provisioned or refused.
    # These legs pin that begin block - the guard messages, the directory side effect, the empty
    # result, and the absence of a terminating error - which is the axis the port can actually break.
    #
    # On a host where the replication libraries DO load, the library warning simply does not appear
    # and the directory legs are unaffected; the two directory legs assert only on the directory
    # guard, so they characterize the same behavior either way.
    BeforeAll {
        $exportRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-replexport-$(Get-Random)"
        $null = New-Item -Path $exportRoot -ItemType Directory -Force
    }
    AfterAll {
        Remove-Item -Path $exportRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Provisioning the export directory" {
        It "Refuses a -Path that is a file rather than a directory, emitting nothing" {
            $notADirectory = Join-Path -Path $exportRoot -ChildPath "already-a-file.txt"
            Set-Content -Path $notADirectory -Value "occupied"

            $splatFilePath = @{
                Path            = $notADirectory
                WarningVariable = "directoryWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = @(Export-DbaReplServerSetting @splatFilePath)

            $result.Count | Should -Be 0
            ($directoryWarning -join "`n") | Should -Match "must be a directory"
        }

        It "Creates a -Path directory that does not exist yet and still emits nothing" {
            $newDirectory = Join-Path -Path $exportRoot -ChildPath "created-on-demand"
            Test-Path -Path $newDirectory | Should -BeFalse

            $splatNewDirectory = @{
                Path            = $newDirectory
                WarningVariable = "createWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = @(Export-DbaReplServerSetting @splatNewDirectory)

            Test-Path -Path $newDirectory -PathType Container | Should -BeTrue
            $result.Count | Should -Be 0
            ($createWarning -join "`n") | Should -Not -Match "must be a directory"
        }
    }

    Context "Targeting an instance where the replication libraries are unavailable" {
        It "Warns about the libraries and returns nothing without throwing" {
            # The begin-block library load stops the command before any connection is attempted, so
            # this leg reaches the instance parameter but deliberately never reaches the instance.
            $splatExport = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Passthru        = $true
                Path            = $exportRoot
                WarningVariable = "replWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = @(Export-DbaReplServerSetting @splatExport)

            $result.Count | Should -Be 0
            ($replWarning -join "`n") | Should -Match "replication librar"
        }
    }
}
