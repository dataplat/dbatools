$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Invoke-Command2.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Identity', 'SecurePassword', 'MappedClassType', 'ProviderName', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $logins = "dbatoolsci_thor", "dbatoolsci_thorsmomma"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $script:instance2
        }
    }
    AfterAll {
        try {
            (Get-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        } catch { }

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $script:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $script:instance2
        }
    }

    Context "Create a new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $script:instance2 -Name dbatoolsci_thorcred -Identity dbatoolsci_thor -Password $password
            $results.Name | Should Be "dbatoolsci_thorcred"
            $results.Identity | Should Be "dbatoolsci_thor"

            $results = New-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thorsmomma -Password $password
            $results | Should Not Be $null
        }
        It "Gets the newly created credential" {
            $results = Get-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thorsmomma
            $results.Name | Should Be "dbatoolsci_thorsmomma"
            $results.Identity | Should Be "dbatoolsci_thorsmomma"
        }
    }
}