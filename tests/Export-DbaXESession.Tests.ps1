param($ModuleName = 'dbatools')

Describe "Export-DbaXESession" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_XE_CustomFile.sql"
    }

    AfterAll {
        Get-ChildItem $outputFile -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaXESession
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Session parameter" {
            $CommandUnderTest | Should -HaveParameter Session
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have FilePath parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath
        }
        It "Should have Encoding parameter" {
            $CommandUnderTest | Should -HaveParameter Encoding
        }
        It "Should have Passthru parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru
        }
        It "Should have BatchSeparator parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator
        }
        It "Should have NoPrefix parameter" {
            $CommandUnderTest | Should -HaveParameter NoPrefix
        }
        It "Should have NoClobber parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber
        }
        It "Should have Append parameter" {
            $CommandUnderTest | Should -HaveParameter Append
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaXESession -SqlInstance $global:instance2 -FilePath $outputFile
        }
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check if session parameter is honored" {
        BeforeAll {
            $null = Export-DbaXESession -SqlInstance $global:instance2 -FilePath $outputFile -Session system_health
        }
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check if supports Pipeline input" {
        BeforeAll {
            $null = Get-DbaXESession -SqlInstance $global:instance2 -Session system_health | Export-DbaXESession -FilePath $outputFile
        }
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }
}
