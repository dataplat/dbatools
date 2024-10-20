param($ModuleName = 'dbatools')

Describe "Remove-DbaDbView" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbView
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "View",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
            $dbname1 = "dbatoolsci_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $instance2 -Name $dbname1

            $view1 = "dbatoolssci_view1_$(Get-Random)"
            $view2 = "dbatoolssci_view2_$(Get-Random)"
            $null = $instance2.Query("CREATE VIEW $view1 (a) AS (SELECT @@VERSION );", $dbname1)
            $null = $instance2.Query("CREATE VIEW $view2 (b) AS (SELECT 1);", $dbname1)
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $instance2 -Database $dbname1 -Confirm:$false
        }

        It "removes a view" {
            (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view1) | Should -Not -BeNullOrEmpty
            Remove-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view1 -Confirm:$false
            (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view1) | Should -BeNullOrEmpty
        }

        It "supports piping view" {
            (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view2) | Should -Not -BeNullOrEmpty
            Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view2 | Remove-DbaDbView -Confirm:$false
            (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view2) | Should -BeNullOrEmpty
        }
    }
}
