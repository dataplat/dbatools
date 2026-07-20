#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaCommunitySoftware",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Software",
                "Branch",
                "LocalFile",
                "Url",
                "LocalDirectory",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: downloading and unpacking community software reaches out to GitHub (and for
    # some software the GitHub releases API), so the real download legs need network access and
    # external services - those are DEFERRED-TO-GATE (a networked runner). What IS characterizable
    # locally, with no instance and no network, is the LocalFile guard: for MaintenanceSolution the
    # source only composes URL strings (no web request) and then, when -LocalFile is supplied,
    # validates the file exists before doing anything - a nonexistent path warns and returns before
    # any download. This leg needs no SQL instance. WhatIf is passed as belt-and-braces on this
    # file-writing command, though the guard returns ahead of any write.
    BeforeAll {
        # GetTempPath, not $env:TEMP: the environment variable is unset on typical Linux runners.
        # (No EnableException default toggle here: nothing in this BeforeAll runs a dbatools
        # command, so the toggle would be dead state - same ruling as the Export-DbaSpConfigure
        # sweep fix.) A GUID guarantees a globally unique name, so no leftover or independently
        # created file can pre-exist at this path and silently satisfy the guard.
        $tempBase = [System.IO.Path]::GetTempPath()
        $missingLocalFile = Join-Path $tempBase "dbatoolsci_missing_$([guid]::NewGuid()).zip"
        # [char]39 supplies the apostrophe the source message contains (the contraction in "does
        # not exist") without putting a literal apostrophe in the test source
        $apostrophe = [char]39

        # offline happy-path fixture: a zip whose single top-level directory name matches the
        # -LocalDirectory leaf, which is the shape the command's post-extract safety net requires
        # GUID, not Get-Random: parallel runs on the shared temp root could collide on a
        # 32-bit random and cross-delete each other's fixtures
        $fixtureToken = ([guid]::NewGuid()).ToString("N")
        $fixtureName = "dbatoolsci_ms_$fixtureToken"
        $fixtureRoot = Join-Path $tempBase "dbatoolsci_savecs_$fixtureToken"
        $fixtureSource = Join-Path $fixtureRoot $fixtureName
        $null = New-Item -Path $fixtureSource -ItemType Directory -Force
        Set-Content -Path (Join-Path $fixtureSource "MaintenanceSolution.sql") -Value "SELECT 1;"
        $fixtureZip = Join-Path $fixtureRoot "$fixtureName.zip"
        Compress-Archive -Path $fixtureSource -DestinationPath $fixtureZip
        # the destination leaf must match the zip's inner directory name (the safety-net contract),
        # and the destination's PARENT must already exist - the final Copy-Item targets the parent,
        # and a missing parent silently becomes a renamed copy instead of a child directory. A
        # separate dest/ parent keeps the extraction target distinct from the fixture source.
        # Contract verified live: WARN empty, dest + file present (guest ps7, 2026-07-20).
        $destBase = Join-Path $fixtureRoot "dest"
        $null = New-Item -Path $destBase -ItemType Directory -Force
        $happyLocalDirectory = Join-Path $destBase $fixtureName
    }

    AfterAll {
        Remove-Item -Path $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Guarding a missing LocalFile" {
        It "Warns and returns nothing when the supplied LocalFile does not exist" {
            # precondition: the path must genuinely not exist for this to test the guard
            Test-Path -Path $missingLocalFile | Should -BeFalse

            $splatMissing = @{
                Software        = "MaintenanceSolution"
                LocalFile       = $missingLocalFile
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Save-DbaCommunitySoftware @splatMissing)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "$missingLocalFile doesn${apostrophe}t exist"
        }
    }

    Context "Unpacking a supplied LocalFile offline" {
        It "Extracts the archive into LocalDirectory without any network access" {
            $splatHappy = @{
                Software        = "MaintenanceSolution"
                LocalFile       = $fixtureZip
                LocalDirectory  = $happyLocalDirectory
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                EnableException = $true
            }
            Save-DbaCommunitySoftware @splatHappy
            $warn | Should -BeNullOrEmpty
            Test-Path -Path $happyLocalDirectory | Should -BeTrue
            Test-Path -Path (Join-Path $happyLocalDirectory "MaintenanceSolution.sql") | Should -BeTrue
        }
    }
}