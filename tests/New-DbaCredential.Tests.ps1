$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Invoke-Command2.ps1"

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
        $logins = "thor", "thorsmomma"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $TestConfig.instance2
        }
    }
    AfterAll {
        try {
            (Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thor, thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
            (Get-DbaCredential -SqlInstance $TestConfig.instance2 -Name "https://mystorageaccount.blob.core.windows.net/mycontainer" -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        } catch { }

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $TestConfig.instance2
        }
    }

    Context "Create a new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $TestConfig.instance2 -Name thorcred -Identity thor -Password $password
            $results.Name | Should Be "thorcred"
            $results.Identity | Should Be "thor"

            $results = New-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thorsmomma -Password $password
            $results | Should Not Be $null
        }
        It "Gets the newly created credential" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thorsmomma
            $results.Name | Should Be "thorsmomma"
            $results.Identity | Should Be "thorsmomma"
        }
    }

    Context "Create a new credential without password" {
        It "Should create new credentials with the proper properties but without password" {
            $credentialParams = @{
                SqlInstance = $TestConfig.instance2
                Name = "https://mystorageaccount.blob.core.windows.net/mycontainer"
                Identity = 'Managed Identity'
            }
            $results = New-DbaCredential @credentialParams
            $results.Name | Should Be "https://mystorageaccount.blob.core.windows.net/mycontainer"
            $results.Identity | Should Be "Managed Identity"
        }
        It "Gets the newly created credential that doesn't have password" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity "Managed Identity"
            $results.Name | Should Be "https://mystorageaccount.blob.core.windows.net/mycontainer"
            $results.Identity | Should Be "Managed Identity"
        }
    }
}
