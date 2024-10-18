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
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[] -Mandatory:$false
        }
        It "Should have FilePath parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type System.Object -Mandatory:$false
        }
        It "Should have Locale parameter" {
            $CommandUnderTest | Should -HaveParameter Locale -Type System.String -Mandatory:$false
        }
        It "Should have CharacterString parameter" {
            $CommandUnderTest | Should -HaveParameter CharacterString -Type System.String -Mandatory:$false
        }
        It "Should have Table parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type System.String[] -Mandatory:$false
        }
        It "Should have Column parameter" {
            $CommandUnderTest | Should -HaveParameter Column -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeTable parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeTable -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeColumn parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeColumn -Type System.String[] -Mandatory:$false
        }
        It "Should have MaxValue parameter" {
            $CommandUnderTest | Should -HaveParameter MaxValue -Type System.Int32 -Mandatory:$false
        }
        It "Should have ExactLength parameter" {
            $CommandUnderTest | Should -HaveParameter ExactLength -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have ModulusFactor parameter" {
            $CommandUnderTest | Should -HaveParameter ModulusFactor -Type System.Int32 -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
