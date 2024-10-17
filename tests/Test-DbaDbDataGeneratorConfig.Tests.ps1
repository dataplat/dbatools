param($ModuleName = 'dbatools')

Describe "Test-DbaDbDataGeneratorConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbDataGeneratorConfig
        }
        It "Should have FilePath as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $dbname = "dbatools_datagentest"
            $query = "CREATE DATABASE [$dbname]"

            Invoke-DbaQuery -SqlInstance $global:instance1 -Database master -Query $query

            $query = @"
            CREATE TABLE [dbo].[Customer](
                [CustomerID] [int] IDENTITY(1,1) NOT NULL,
                [Firstname] [varchar](30) NULL,
                [Lastname] [varchar](50) NULL,
                [FullName] [varchar](100) NULL,
                [Address] [varchar](100) NULL,
                [Zip] [varchar](10) NULL,
                [City] [varchar](255) NULL,
                [Randomtext] [varchar](255) NULL,
                [DOB] [date] NULL
            ) ON [PRIMARY]
"@

            Invoke-DbaQuery -SqlInstance $global:instance1 -Database $dbname -Query $query

            $file = New-DbaDbDataGeneratorConfig -SqlInstance $global:instance1 -Database $dbname -Table Customer -Path "C:\temp\datageneration"
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        }

        It "gives no errors with a correct json file" {
            $findings = @()
            $findings += Test-DbaDbDataGeneratorConfig -FilePath $file.FullName

            $findings.Count | Should -Be 0
        }

        It "gives errors with an incorrect json file" {
            # Retrieve the JSON content
            $json = Get-Content -Path $file.FullName | ConvertFrom-Json

            # Break the content by removing a property
            $json.Tables[0].Columns[8].PSObject.Properties.Remove("SubType")

            # Write the JSON back to the file
            $json | ConvertTo-Json -Depth 5 | Out-File $file.FullName -Force

            $findings = @()
            $findings += Test-DbaDbDataGeneratorConfig -FilePath $file.FullName

            $findings.Count | Should -Be 1
        }
    }
}
