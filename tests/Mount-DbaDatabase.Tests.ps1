param($ModuleName = 'dbatools')

Describe "Mount-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Mount-DbaDatabase
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have FileStructure as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileStructure -Type System.Collections.Specialized.StringCollection
        }
        It "Should have DatabaseOwner as a parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseOwner -Type String
        }
        It "Should have AttachOption as a parameter" {
            $CommandUnderTest | Should -HaveParameter AttachOption -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"

            # Setup: remove, restore and backup on the local drive
            Get-DbaDatabase -SqlInstance $global:instance1 -Database detachattach | Remove-DbaDatabase -Confirm:$false
            Restore-DbaDatabase -SqlInstance $global:instance1 -Path $env:appveyorlabrepo\detachattach\detachattach.bak -WithReplace
            Get-DbaDatabase -SqlInstance $global:instance1 -Database detachattach | Backup-DbaDatabase -Type Full
            Detach-DbaDatabase -SqlInstance $global:instance1 -Database detachattach -Force
        }

        It "Attaches a single database and ensures the alias still exists" {
            $results = Attach-DbaDatabase -SqlInstance $global:instance1 -Database detachattach

            $results.AttachResult | Should -Be "Success"
            $results.Database | Should -Be "detachattach"
            $results.AttachOption | Should -Be "None"
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance1 -Database detachattach | Remove-DbaDatabase -Confirm:$false
        }
    }
}
