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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[] -Mandatory:$false
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type System.String[] -Mandatory:$false
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type System.String[] -Mandatory:$false
        }
        It "Should have FileNameColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileNameColumn -Type System.String -Mandatory:$false
        }
        It "Should have BinaryColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter BinaryColumn -Type System.String -Mandatory:$false
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String -Mandatory:$false
        }
        It "Should have Query as a parameter" {
            $CommandUnderTest | Should -HaveParameter Query -Type System.String -Mandatory:$false
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type System.String -Mandatory:$false
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type [Microsoft.SqlServer.Management.Smo.Table[]] -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database tempdb
            $null = $db.Query("CREATE TABLE [dbo].[BunchOFilezz]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
            $null = Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFilezz -FilePath $global:appveyorlabrepo\azure\adalsql.msi
            $null = Get-ChildItem $global:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFilezz
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
            $results = Export-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Path C:\temp\exports
            $results.Name.Count | Should -Be 3
            $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
        }

        It "exports the table data to file using pipeline" {
            $results = Get-DbaBinaryFileTable -SqlInstance $global:instance2 -Database tempdb | Export-DbaBinaryFile -Path C:\temp\exports
            $results.Name.Count | Should -Be 3
            $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
        }
    }
}
