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
        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname
        $db.Query($sql)
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
        $results | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbDataGeneratorConfig
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have Table as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[] -Not -Mandatory
        }
        It "Should have ResetIdentity as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ResetIdentity -Type Switch -Not -Mandatory
        }
        It "Should have TruncateTable as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter TruncateTable -Type Switch -Not -Mandatory
        }
        It "Should have Rows as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Rows -Type Int32 -Not -Mandatory
        }
        It "Should have Path as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command works" {
        It "Should output a file with specific content" {
            $results = New-DbaDbDataGeneratorConfig -SqlInstance $script:instance1 -Database $dbname -Path C:\temp
            $results.Directory.Name | Should -Be 'temp'
            $results.FullName | Should -FileContentMatch $dbname
            $results.FullName | Should -FileContentMatch 'FirstName'
        }
    }
}
