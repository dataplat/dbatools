#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbatoolsRenameHelper",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "Encoding",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $content = @'
function Get-DbaStub {
    <#
        .SYNOPSIS
            is a stub

        .DESCRIPTION
            Using
    #>
    process {
        do this UseLastBackups
        then Find-SqlDuplicateIndex
        or Export-SqlUser -NoSystemLogins
        Write-Message -Level Verbose "stub"
    }
}
'@

        $wantedContent = @'
function Get-DbaStub {
    <#
        .SYNOPSIS
            is a stub

        .DESCRIPTION
            Using
    #>
    process {
        do this UseLastBackup
        then Find-DbaDbDuplicateIndex
        or Export-DbaUser -ExcludeSystemLogins
        Write-Message -Level Verbose "stub"
    }
}

'@

        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random).ps1"
        [System.IO.File]::WriteAllText($tempPath, $content)
        $results = $tempPath | Invoke-DbatoolsRenameHelper
        $newContent = [System.IO.File]::ReadAllText($tempPath)
    }

    AfterAll {
        Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
    }

    Context "Replacement functionality" {
        It "Returns 4 results" {
            $results.Count | Should -Be 4
        }

        It "Returns the expected results" {
            foreach ($result in $results) {
                $result.Path | Should -Be $tempPath
                $result.Pattern | Should -BeIn "Export-SqlUser", "Find-SqlDuplicateIndex", "UseLastBackups", "NoSystemLogins"
                $result.ReplacedWith | Should -BeIn "Export-DbaUser", "Find-DbaDbDuplicateIndex", "UseLastBackup", "ExcludeSystemLogins"
            }
        }

        It "Returns expected specific results" {
            $result = $results | Where-Object Pattern -eq "Export-SqlUser"
            $result.ReplacedWith | Should -Be "Export-DbaUser"
        }

        It "Should return exactly the format we want" {
            $newContent | Should -Be $wantedContent
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $results[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'Path',
                'Pattern',
                'ReplacedWith'
            )
            $actualProps = $results[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Path property contains the file path" {
            $results[0].Path | Should -Be $tempPath
        }

        It "Pattern property contains the matched deprecated name" {
            $results[0].Pattern | Should -Not -BeNullOrEmpty
        }

        It "ReplacedWith property contains the new name" {
            $results[0].ReplacedWith | Should -Not -BeNullOrEmpty
        }
    }
}