param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbDataGenerator" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbDataGenerator
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "FilePath",
            "Locale",
            "CharacterString",
            "Table",
            "Column",
            "ExcludeTable",
            "ExcludeColumn",
            "MaxValue",
            "ExactLength",
            "ModulusFactor",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command works" {
        BeforeAll {
            $db = "dbatoolsci_generator"
            $sql = "CREATE TABLE [dbo].[people](
                        [FirstName] [varchar](50) NULL,
                        [LastName] [varchar](50) NULL,
                        [City] [varchar](100) NULL
                    ) ON [PRIMARY];"
            New-DbaDatabase -SqlInstance $global:instance2 -Name $db
            Invoke-DbaQuery -SqlInstance $global:instance2 -Database $db -Query $sql
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $db -Confirm:$false
            $file | Remove-Item -Confirm:$false -ErrorAction Ignore
        }

        It "Starts with the right data" {
            $result = Invoke-DbaQuery -SqlInstance $global:instance2 -Database $db -Query "select * from people"
            $result | Should -BeNullOrEmpty
        }

        It "Returns the proper output" {
            $file = New-DbaDbDataGeneratorConfig -SqlInstance $global:instance2 -Database $db -Path C:\temp -Rows 10

            $results = Invoke-DbaDbDataGenerator -SqlInstance $global:instance2 -Database $db -Confirm:$false -FilePath $file.FullName

            foreach ($result in $results) {
                $result.Rows | Should -Be 10
                $result.Database | Should -Contain $db
            }
        }

        It "Generates the data" {
            $result = Invoke-DbaQuery -SqlInstance $global:instance2 -Database $db -Query "select * from people"
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
