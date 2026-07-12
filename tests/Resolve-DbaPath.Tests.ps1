#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Resolve-DbaPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Provider",
                "SingleItem",
                "NewChild"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-044). Filesystem-only scenarios, CI-safe: every failure
    # path is a TERMINATING throw (the command hardcodes -EnableException $true on all its
    # Stop-Function sites), resolution honors the session's current location, and output is
    # plain provider-path strings.
    BeforeAll {
        $resolveRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dbatoolsci-resolve-$(Get-Random)"
        $null = New-Item -Path $resolveRoot -ItemType Directory
        $null = New-Item -Path (Join-Path $resolveRoot "alpha.txt") -ItemType File
        $null = New-Item -Path (Join-Path $resolveRoot "beta.txt") -ItemType File
    }

    AfterAll {
        Remove-Item -Path $resolveRoot -Recurse -ErrorAction SilentlyContinue
    }

    Context "Resolving existing paths" {
        It "Resolves an absolute path to its provider path string" {
            $result = Resolve-DbaPath -Path (Join-Path $resolveRoot "alpha.txt")
            $result | Should -BeExactly (Join-Path $resolveRoot "alpha.txt")
            $result | Should -BeOfType [string]
        }

        It "Resolves a wildcard to every match" {
            $results = @(Resolve-DbaPath -Path (Join-Path $resolveRoot "*.txt"))
            $results.Count | Should -BeExactly 2
        }

        It "Resolves relative to the current location" {
            Push-Location $resolveRoot
            try {
                $result = Resolve-DbaPath -Path "alpha.txt"
                $result | Should -BeExactly (Join-Path $resolveRoot "alpha.txt")
            } finally {
                Pop-Location
            }
        }

        It "Resolves piped paths" {
            $results = @((Join-Path $resolveRoot "alpha.txt"), (Join-Path $resolveRoot "beta.txt") | Resolve-DbaPath)
            $results.Count | Should -BeExactly 2
        }
    }

    Context "Failure shapes (always terminating - EnableException is hardcoded)" {
        It "Throws Failed-to-resolve for a nonexistent path" {
            { Resolve-DbaPath -Path (Join-Path $resolveRoot "doesnotexist-$(Get-Random).txt") } | Should -Throw -ExpectedMessage "*Failed to resolve path*"
        }

        It "Throws when SingleItem resolves to multiple paths" {
            { Resolve-DbaPath -Path (Join-Path $resolveRoot "*.txt") -SingleItem } | Should -Throw -ExpectedMessage "*Could not resolve to a single parent path*"
        }

        It "Throws when the resolved provider does not match" {
            { Resolve-DbaPath -Path $resolveRoot -Provider Registry } | Should -Throw -ExpectedMessage "*Resolved provider is FileSystem when it should be Registry*"
        }
    }

    Context "Provider validation" {
        It "Passes a matching FileSystem provider check" {
            Resolve-DbaPath -Path $resolveRoot -Provider FileSystem | Should -BeExactly $resolveRoot
        }
    }

    Context "NewChild" {
        It "Returns the joined path for a new file under an existing parent" {
            $result = Resolve-DbaPath -Path (Join-Path $resolveRoot "newfile.log") -NewChild
            $result | Should -BeExactly (Join-Path $resolveRoot "newfile.log")
        }

        It "Uses the current location for a bare leaf" {
            Push-Location $resolveRoot
            try {
                $result = Resolve-DbaPath -Path "bareleaf.log" -NewChild
                $result | Should -BeExactly (Join-Path $resolveRoot "bareleaf.log")
            } finally {
                Pop-Location
            }
        }

        It "Throws Failed-to-resolve for a nonexistent parent" {
            { Resolve-DbaPath -Path (Join-Path (Join-Path $resolveRoot "nosuchdir") "x.log") -NewChild } | Should -Throw -ExpectedMessage "*Failed to resolve path*"
        }
    }
}