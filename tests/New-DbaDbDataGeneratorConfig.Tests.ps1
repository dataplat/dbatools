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
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Table",
            "Rows",
            "Path",
            "ResetIdentity",
            "TruncateTable",
            "Force",
            "EnableException"
        )
        foreach ($param in $params) {
            It "has the required parameter: $param" {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
