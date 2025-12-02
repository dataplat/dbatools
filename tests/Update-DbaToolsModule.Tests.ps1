#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaToolsModule"
)

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter Validation" {
        BeforeAll {
            $command = Get-Command $CommandName
        }

        It "Has parameter: ComputerName" {
            $command | Should -HaveParameter ComputerName -Mandatory -Type ([DbaInstanceParameter[]])
        }

        It "Has parameter: Credential" {
            $command | Should -HaveParameter Credential -Type ([PSCredential])
        }

        It "Has parameter: SourcePath" {
            $command | Should -HaveParameter SourcePath -Type ([string])
        }

        It "Has parameter: UseAdminShare" {
            $command | Should -HaveParameter UseAdminShare -Type ([switch])
        }

        It "Has parameter: EnableException" {
            $command | Should -HaveParameter EnableException -Type ([switch])
        }

        It "Has parameter alias for ComputerName" {
            $command.Parameters.ComputerName.Aliases | Should -Contain 'SqlInstance'
            $command.Parameters.ComputerName.Aliases | Should -Contain 'cn'
            $command.Parameters.ComputerName.Aliases | Should -Contain 'host'
            $command.Parameters.ComputerName.Aliases | Should -Contain 'Server'
        }

        It "ComputerName accepts pipeline input" {
            $command.Parameters.ComputerName.Attributes.ValueFromPipeline | Should -Contain $true
        }

        It "Supports ShouldProcess" {
            $command.CmdletBinding.SupportsShouldProcess | Should -Be $true
        }
    }

    Context "Command Structure" {
        BeforeAll {
            $command = Get-Command $CommandName
        }

        It "Is a function" {
            $command.CommandType | Should -Be 'Function'
        }

        It "Has help documentation" {
            $help = Get-Help $CommandName
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Has examples in help" {
            $help = Get-Help $CommandName -Examples
            $help.Examples.Example.Count | Should -BeGreaterThan 0
        }

        It "Has all required help sections" {
            $help = Get-Help $CommandName -Full
            $help.parameters | Should -Not -BeNullOrEmpty
            $help.examples | Should -Not -BeNullOrEmpty
            $help.relatedLinks | Should -Not -BeNullOrEmpty
        }
    }

    Context "Help Content Validation" {
        BeforeAll {
            $help = Get-Help $CommandName -Full
        }

        It "Has synopsis" {
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Has description" {
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Has at least 5 examples" {
            $help.Examples.Example.Count | Should -BeGreaterOrEqual 5
        }

        It "Each example has a title" {
            foreach ($example in $help.Examples.Example) {
                $example.Title | Should -Not -BeNullOrEmpty
            }
        }

        It "Each example has code" {
            foreach ($example in $help.Examples.Example) {
                $example.Code | Should -Not -BeNullOrEmpty
            }
        }

        It "Each example has remarks" {
            foreach ($example in $help.Examples.Example) {
                $example.Remarks | Should -Not -BeNullOrEmpty
            }
        }

        It "Has notes section with Tags" {
            $help.alertSet.alert.Text | Should -Match 'Tags:'
        }

        It "Has link to dbatools.io" {
            $help.relatedLinks.navigationLink.uri | Should -Contain "https://dbatools.io/$CommandName"
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    BeforeAll {
        # These tests would require actual remote computers and proper test infrastructure
        # For now, we'll test the basic function loading and parameter binding
    }

    Context "Function Execution - Basic" {
        It "Should not throw when loaded" {
            { Get-Command $CommandName } | Should -Not -Throw
        }

        It "Should fail gracefully with invalid computer name" {
            $result = Update-DbaToolsModule -ComputerName "InvalidComputer$(Get-Random)" -EnableException:$false -WarningAction SilentlyContinue 3>&1
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Parameter Validation - Runtime" {
        It "Should require ComputerName parameter" {
            { Update-DbaToolsModule -ErrorAction Stop } | Should -Throw
        }

        It "Should accept pipeline input for ComputerName" {
            { "localhost" | Update-DbaToolsModule -WhatIf } | Should -Not -Throw
        }

        It "Should accept array of computer names" {
            { Update-DbaToolsModule -ComputerName "Server1", "Server2" -WhatIf } | Should -Not -Throw
        }
    }

    Context "Method Selection" {
        It "Should use PSRemoting by default" {
            # This would require mocking or actual test infrastructure
            # Placeholder for future implementation
            Set-ItResult -Skipped -Because "Requires test infrastructure"
        }

        It "Should use AdminShare when switch is specified" {
            # This would require mocking or actual test infrastructure
            # Placeholder for future implementation
            Set-ItResult -Skipped -Because "Requires test infrastructure"
        }
    }

    Context "Error Handling" {
        It "Should handle unreachable computer gracefully" {
            $result = Update-DbaToolsModule -ComputerName "192.0.2.1" -EnableException:$false -WarningAction SilentlyContinue 3>&1
            # Should produce warning message, not throw exception
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should handle missing SourcePath when dbatools not loaded" {
            # This test would need to be run in a clean session
            Set-ItResult -Skipped -Because "Requires clean PowerShell session"
        }
    }
}
