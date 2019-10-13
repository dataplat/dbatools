$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Role', 'User', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $user1 = "dbatoolssci_user1_$(Get-Random)"
        $user2 = "dbatoolssci_user2_$(Get-Random)"
        $role = "dbatoolssci_role_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $script:instance2 -Login $user1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $script:instance2 -Login $user2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $dbname = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname -Owner sa
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database $dbname -Login $user1 -Username $user1
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database $dbname -Login $user2 -Username $user2
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database msdb -Login $user1 -Username $user1 -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database msdb -Login $user2 -Username $user2 -IncludeSystem
        $null = $server.Query("CREATE ROLE $role", $dbname)
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("DROP USER $user1", 'msdb')
        $null = $server.Query("DROP USER $user2", 'msdb')
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -confirm:$false
        $null = Remove-DbaLogin -SqlInstance $script:instance2 -Login $user1, $user2 -confirm:$false
    }

    Context "Functionality" {
        It 'Adds User to Role' {
            Add-DbaDbRoleMember -SqlInstance $script:instance2 -Role $role -User $user1 -Database $dbname -confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database $dbname -Role $role

            $roleDBAfter.Role | Should Be $role
            $roleDBAfter.Login | Should Be $user1
            $roleDBAfter.UserName | Should Be $user1
        }

        It 'Adds User to Multiple Roles' {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            Add-DbaDbRoleMember -SqlInstance $script:instance2 -Role db_datareader, SQLAgentReaderRole -User $user1 -Database msdb -confirm:$false

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDBAfter.Count | Should BeGreaterThan $roleDB.Count
            $roleDB.UserName -contains $user1 | Should Be $false
            $roleDBAfter.UserName -contains $user1 | Should Be $true

        }

        It 'Adds User to Roles via piped input from Get-DbaDbRole' {
            $roleInput = Get-DbaDbRole -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleInput | Add-DbaDbRoleMember -User $user2 -confirm:$false

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB.UserName -contains $user2 | Should Be $false
            $roleDBAfter.UserName -contains $user2 | Should Be $true
        }
    }
}