$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Invoke-Command2.ps1"


Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'ExcludeCredential', 'Identity', 'ExcludeIdentity', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $logins = "thor", "thorsmomma"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $TestConfig.instance2
        }

        $null = New-DbaCredential -SqlInstance $TestConfig.instance2 -Name thorcred -Identity thor -Password $password
        $null = New-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thorsmomma -Password $password
    }
    AfterAll {
        try {
            (Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thor, thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        } catch { }

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $TestConfig.instance2
        }
    }

    Context "Get credentials" {
        It "Should get just one credential with the proper properties when using Identity" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thorsmomma
            $results.Name | Should Be "thorsmomma"
            $results.Identity | Should Be "thorsmomma"
        }
        It "Should get just one credential with the proper properties when using Name" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Name thorsmomma
            $results.Name | Should Be "thorsmomma"
            $results.Identity | Should Be "thorsmomma"
        }
        It "gets more than one credential" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thor, thorsmomma
            $results.count -gt 1
        }
    }
}
