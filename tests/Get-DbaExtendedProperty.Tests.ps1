param($ModuleName = 'dbatools')

Describe "Get-DbaExtendedProperty" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaExtendedProperty
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Name",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $random = Get-Random
            $server2 = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Get-DbaProcess -SqlInstance $server2 | Where-Object Program -match dbatools | Stop-DbaProcess
            $newDbName = "dbatoolsci_newdb_$random"
            $db = New-DbaDatabase -SqlInstance $server2 -Name $newDbName
            $db.Query("EXEC sys.sp_addextendedproperty @name=N'dbatoolz', @value=N'woo'")
        }

        AfterAll {
            $null = $db | Remove-DbaDatabase
        }

        It "finds an extended property on an instance" {
            $ep = Get-DbaExtendedProperty -SqlInstance $server2
            $ep.Count | Should -BeGreaterThan 0
        }

        It "finds a sequence in a single database" {
            $ep = Get-DbaExtendedProperty -SqlInstance $server2 -Database $db.Name
            $ep.Parent.Name | Select-Object -Unique | Should -Be $db.Name
            $ep.Count | Should -Be 1
        }

        It "supports piping databases" {
            $ep = $db | Get-DbaExtendedProperty -Name dbatoolz
            $ep.Name | Should -Be "dbatoolz"
        }
    }
}
