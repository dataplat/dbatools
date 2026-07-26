#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaSqlPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Scope",
                "Type",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "WhatIf download protection" {
        BeforeEach {
            Mock Get-DbaSqlPackagePath -ModuleName dbatools { $null }
            Mock Invoke-TlsWebRequest -ModuleName dbatools {
                param($Uri, $OutFile, [switch]$UseBasicParsing)
                [System.IO.File]::WriteAllText($OutFile, "downloaded")
            }
            Mock Expand-Archive -ModuleName dbatools {
                param($Path, $DestinationPath, [switch]$Force)
                $null = New-Item -ItemType Directory -Path $DestinationPath -Force
                [System.IO.File]::WriteAllText((Join-Path $DestinationPath "SqlPackage.exe"), "fixture")
            }
        }

        It "does not create an absent download under WhatIf" {
            $localFile = Join-Path $TestDrive "absent.zip"
            $installPath = Join-Path $TestDrive "absent-install"
            Test-Path -LiteralPath $localFile | Should -BeFalse

            $null = Install-DbaSqlPackage -LocalFile $localFile -Path $installPath -WhatIf -Confirm:$false -EnableException:$false

            Test-Path -LiteralPath $localFile | Should -BeFalse
            Should -Invoke Invoke-TlsWebRequest -ModuleName dbatools -Times 0 -Exactly

            $null = Install-DbaSqlPackage -LocalFile $localFile -Path $installPath -Confirm:$false -EnableException:$false

            [System.IO.File]::ReadAllText($localFile) | Should -Be "downloaded"
            Test-Path -LiteralPath (Join-Path $installPath "SqlPackage.exe") | Should -BeTrue
            Should -Invoke Invoke-TlsWebRequest -ModuleName dbatools -Times 1 -Exactly
        }

        It "does not overwrite an existing download under Force WhatIf" {
            $localFile = Join-Path $TestDrive "existing.zip"
            $installPath = Join-Path $TestDrive "existing-install"
            [System.IO.File]::WriteAllText($localFile, "original")

            $null = Install-DbaSqlPackage -LocalFile $localFile -Path $installPath -Force -WhatIf -Confirm:$false -EnableException:$false

            [System.IO.File]::ReadAllText($localFile) | Should -Be "original"
            Should -Invoke Invoke-TlsWebRequest -ModuleName dbatools -Times 0 -Exactly

            $null = Install-DbaSqlPackage -LocalFile $localFile -Path $installPath -Force -Confirm:$false -EnableException:$false

            [System.IO.File]::ReadAllText($localFile) | Should -Be "downloaded"
            Test-Path -LiteralPath (Join-Path $installPath "SqlPackage.exe") | Should -BeTrue
            Should -Invoke Invoke-TlsWebRequest -ModuleName dbatools -Times 1 -Exactly
        }
    }

    Context "Testing SqlPackage installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $results = Install-DbaSqlPackage -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # Clean up is not needed as SqlPackage installation is typically permanent
            # and safe to leave installed for other tests
        }

        It "Should have installed SqlPackage successfully" {
            $results.Installed | Should -Be $true
        }

        It "Returns an object with the expected properties" {
            $result = $results
            $ExpectedProps = 'Name', 'Path', 'Installed'
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return a valid installation path" {
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -Be $true
        }

        It "Should be able to find SqlPackage after installation" {
            $sqlPackagePath = Get-DbaSqlPackagePath
            $sqlPackagePath | Should -Not -BeNullOrEmpty
            Test-Path $sqlPackagePath | Should -Be $true
        }

        It "SqlPackage executable should be functional" {
            $sqlPackagePath = Get-DbaSqlPackagePath
            if ($PSVersionTable.Platform -eq "Unix") {
                $testProcess = Start-Process -FilePath $sqlPackagePath -ArgumentList '/?' -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP/sqlpackage_test.txt" -RedirectStandardError "$env:TEMP/sqlpackage_error.txt"
            } else {
                $testProcess = Start-Process -FilePath $sqlPackagePath -ArgumentList '/?' -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\sqlpackage_test.txt" -RedirectStandardError "$env:TEMP\sqlpackage_error.txt"
            }
            $testProcess.ExitCode | Should -Be 0
            if ($PSVersionTable.Platform -eq "Unix") {
                Remove-Item "$env:TEMP/sqlpackage_test.txt" -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP/sqlpackage_error.txt" -ErrorAction SilentlyContinue
            } else {
                Remove-Item "$env:TEMP\sqlpackage_test.txt" -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP\sqlpackage_error.txt" -ErrorAction SilentlyContinue
            }
        }
    }
}
