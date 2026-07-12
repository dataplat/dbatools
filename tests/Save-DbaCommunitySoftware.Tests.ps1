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

    Context "Download retry behavior" {
        BeforeAll {
            # Build a valid archive that looks like a downloaded GitHub zip of DarlingData-main,
            # so the mocked download can produce a file that survives extraction and content checks.
            $sourceFolder = Join-Path -Path $TestDrive -ChildPath "DarlingData-main"
            $null = New-Item -Path $sourceFolder -ItemType Directory
            Set-Content -Path (Join-Path -Path $sourceFolder -ChildPath "readme.txt") -Value "dbatoolsci retry test"
            $goodZip = Join-Path -Path $TestDrive -ChildPath "gooddownload.zip"
            Compress-Archive -Path $sourceFolder -DestinationPath $goodZip

            # Invoke-TlsWebRequest is not an advanced function, so the mock receives the
            # original arguments in $args and has to locate the -OutFile value itself.
            # Behavior is driven by $global:dbatoolsciDownloadResults, one entry per call:
            # "throw" fails the call, "junkthrow" writes a partial file and then fails,
            # "skip" succeeds without creating the file, "write" creates a valid file.
            Mock -ModuleName dbatools -CommandName Invoke-TlsWebRequest -MockWith {
                $global:dbatoolsciDownloadCallCount++
                $behavior = $global:dbatoolsciDownloadResults[$global:dbatoolsciDownloadCallCount - 1]
                $outFileIndex = $args.IndexOf("-OutFile:") + 1
                if ($outFileIndex -eq 0) { $outFileIndex = $args.IndexOf("-OutFile") + 1 }
                if ($behavior -eq "throw") {
                    throw "dbatoolsci simulated transient download failure"
                }
                if ($behavior -eq "junkthrow") {
                    Set-Content -Path $args[$outFileIndex] -Value "dbatoolsci partial download junk"
                    throw "dbatoolsci simulated connection reset after partial write"
                }
                if ($behavior -eq "write") {
                    Copy-Item -Path $global:dbatoolsciDownloadGoodZip -Destination $args[$outFileIndex]
                }
            }
            Mock -ModuleName dbatools -CommandName Start-Sleep -MockWith { }

            $global:dbatoolsciDownloadGoodZip = $goodZip
        }

        BeforeEach {
            $global:dbatoolsciDownloadCallCount = 0
            # The content check inside Save-DbaCommunitySoftware expects the target directory leaf
            # to match the archive's top-level folder name, so keep the leaf as DarlingData-main.
            $targetParent = Join-Path -Path $TestDrive -ChildPath "target-$(Get-Random)"
            $null = New-Item -Path $targetParent -ItemType Directory
            $targetDirectory = Join-Path -Path $targetParent -ChildPath "DarlingData-main"
        }

        AfterAll {
            Remove-Variable -Name dbatoolsciDownloadResults, dbatoolsciDownloadCallCount, dbatoolsciDownloadGoodZip -Scope Global -ErrorAction SilentlyContinue
        }

        It "Retries after a transient download failure and then succeeds" {
            # Both calls of attempt one fail (direct, then proxy fallback), the second attempt succeeds.
            $global:dbatoolsciDownloadResults = @("throw", "throw", "write")

            Save-DbaCommunitySoftware -Software DarlingData -LocalDirectory $targetDirectory -EnableException

            $global:dbatoolsciDownloadCallCount | Should -Be 3
            Test-Path -Path (Join-Path -Path $targetDirectory -ChildPath "readme.txt") | Should -BeTrue
        }

        It "Does not mistake a partial file from a failed request for a completed download" {
            # The direct request writes a partial file and dies, the proxy fallback completes
            # silently without writing anything, so the attempt must fail and be retried
            # instead of extracting the leftover junk.
            $global:dbatoolsciDownloadResults = @("junkthrow", "skip", "write")

            Save-DbaCommunitySoftware -Software DarlingData -LocalDirectory $targetDirectory -EnableException

            $global:dbatoolsciDownloadCallCount | Should -Be 3
            Test-Path -Path (Join-Path -Path $targetDirectory -ChildPath "readme.txt") | Should -BeTrue
        }

        It "Retries when the download completes without creating the file" {
            # First attempt completes silently without a file, the second attempt succeeds.
            $global:dbatoolsciDownloadResults = @("skip", "write")

            Save-DbaCommunitySoftware -Software DarlingData -LocalDirectory $targetDirectory -EnableException

            $global:dbatoolsciDownloadCallCount | Should -Be 2
            Test-Path -Path (Join-Path -Path $targetDirectory -ChildPath "readme.txt") | Should -BeTrue
        }

        It "Gives up with a warning after all attempts fail" {
            $global:dbatoolsciDownloadResults = @("skip", "skip", "skip")

            Save-DbaCommunitySoftware -Software DarlingData -LocalDirectory $targetDirectory -WarningAction SilentlyContinue

            $global:dbatoolsciDownloadCallCount | Should -Be 3
            $WarnVar | Should -Match "after 3 attempts"
            Test-Path -Path $targetDirectory | Should -BeFalse
        }
    }
}