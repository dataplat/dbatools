param($ModuleName = 'dbatools')

Describe "New-DbaDacProfile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDacProfile
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Path",
                "ConnectionString",
                "PublishOptions",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $dbname = "dbatoolsci_publishprofile"
            $db = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int);
                INSERT dbo.example
                SELECT top 100 1
                FROM sys.objects")
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        }

        It "returns the right results" {
            $publishprofile = New-DbaDacProfile -SqlInstance $global:instance1 -Database $dbname
            $publishprofile.FileName | Should -Match 'publish.xml'
            Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
        }
    }
}
