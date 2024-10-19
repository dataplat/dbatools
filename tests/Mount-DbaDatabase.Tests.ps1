param($ModuleName = 'dbatools')

Describe "Mount-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Mount-DbaDatabase
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "FileStructure",
                "DatabaseOwner",
                "AttachOption",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
