param($ModuleName = 'dbatools')

Describe "New-DbaDbDataGeneratorConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolsci_generatorconfig"
        $sql = "CREATE TABLE [dbo].[people](
                    [FirstName] [varchar](50) NULL,
                    [LastName] [varchar](50) NULL,
                    [City] [datetime] NULL
                ) ON [PRIMARY]"
        $db = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname
        $db.Query($sql)
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        $results | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbDataGeneratorConfig
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Table as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Table
        }
        It "Should have ResetIdentity as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ResetIdentity
        }
        It "Should have TruncateTable as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter TruncateTable
        }
        It "Should have Rows as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Rows
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command works" {
        It "Should output a file with specific content" {
            $results = New-DbaDbDataGeneratorConfig -SqlInstance $global:instance1 -Database $dbname -Path C:\temp
            $results.Directory.Name | Should -Be 'temp'
            $results.FullName | Should -FileContentMatch $dbname
            $results.FullName | Should -FileContentMatch 'FirstName'
        }
    }
}
