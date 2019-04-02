$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'FilePath', 'Locale', 'CharacterString', 'Table', 'Column', 'ExcludeTable', 'ExcludeColumn', 'Query', 'MaxValue', 'ModulusFactor', 'ExactLength', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $db = "dbatoolsci_generator"
        $sql = "CREATE TABLE [dbo].[people](
                    [FirstName] [varchar](50) NULL,
                    [LastName] [varchar](50) NULL,
                    [City] [datetime] NULL
                ) ON [PRIMARY];"
        New-DbaDatabase -SqlInstance $script:instance2 -Name $db
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query $sql
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $db -Confirm:$false
        $file | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Command works" {
        It "Starts with the right data" {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "select * from people" | Should -Be $null
        }

        It "Returns the proper output" {
            $file = New-DbaDbDataGeneratorConfig -SqlInstance $script:instance2 -Database $db -Path C:\temp -Rows 10
            $results = $file | Invoke-DbaDbDataGenerator -SqlInstance $script:instance2 -Database $db -Confirm:$false
            foreach ($result in $results) {
                $result.Rows | Should -Be 2
                $result.Database | Should -Contain $db
            }

        }
        It "Generates the data" {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "select * from people" | Should -Not -Be $null
        }
    }
}