$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions', 'Invoke-Command2.ps1'))


Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ExcludeName', 'Identity', 'ExcludeIdentity', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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

        $results = New-DbaCredential -SqlInstance $script:instance2 -Name dbatoolsci_thorcred -Identity dbatoolsci_thor -Password $password
        $results = New-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thorsmomma -Password $password
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

    Context "Get credentials" {
        It "Should get just one credential with the proper properties when using Identity" {
            $results = Get-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thorsmomma
            $results.Name | Should Be "dbatoolsci_thorsmomma"
            $results.Identity | Should Be "dbatoolsci_thorsmomma"
        }
        It "Should get just one credential with the proper properties when using Name" {
            $results = Get-DbaCredential -SqlInstance $script:instance2 -Name dbatoolsci_thorsmomma
            $results.Name | Should Be "dbatoolsci_thorsmomma"
            $results.Identity | Should Be "dbatoolsci_thorsmomma"
        }
        It "gets more than one credential" {
            $results = Get-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma
            $results.count -gt 1
        }
    }
}