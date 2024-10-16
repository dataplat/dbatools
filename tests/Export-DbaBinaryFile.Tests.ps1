param($ModuleName = 'dbatools')

Describe "Export-DbaBinaryFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaBinaryFile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[] -Not -Mandatory
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String[] -Not -Mandatory
        }
        It "Should have FileNameColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileNameColumn -Type String -Not -Mandatory
        }
        It "Should have BinaryColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter BinaryColumn -Type String -Not -Mandatory
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have Query as a parameter" {
            $CommandUnderTest | Should -HaveParameter Query -Type String -Not -Mandatory
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Table[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
            $null = $db.Query("CREATE TABLE [dbo].[BunchOFilezz]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
            $null = Import-DbaBinaryFile -SqlInstance $script:instance2 -Database tempdb -Table BunchOFilezz -FilePath $script:appveyorlabrepo\azure\adalsql.msi
            $null = Get-ChildItem $script:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $script:instance2 -Database tempdb -Table BunchOFilezz
        }

        AfterAll {
            try {
                $null = $db.Query("DROP TABLE dbo.BunchOFilezz")
                $null = Get-ChildItem -Path C:\temp\exports -File | Remove-Item -Confirm:$false -Force
            } catch {
                $null = 1
            }
        }

        It "exports the table data to file" {
            $results = Export-DbaBinaryFile -SqlInstance $script:instance2 -Database tempdb -Path C:\temp\exports
            $results.Name.Count | Should -Be 3
            $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
        }

        It "exports the table data to file using pipeline" {
            $results = Get-DbaBinaryFileTable -SqlInstance $script:instance2 -Database tempdb | Export-DbaBinaryFile -Path C:\temp\exports
            $results.Name.Count | Should -Be 3
            $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
        }
    }
}
