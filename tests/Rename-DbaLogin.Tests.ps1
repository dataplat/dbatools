$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'NewLogin', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $login = "dbatoolsci_renamelogin"
        $renamed = "dbatoolsci_renamelogin2"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newlogin = New-DbaLogin -SqlInstance $script:instance1 -Login $login -Password $securePassword
    }
    AfterAll {
        Stop-DbaProcess -SqlInstance $script:instance1 -Login $renamed
        (Get-Dbalogin -SqlInstance $script:instance1 -Login $renamed).Drop()
    }

    It "renames the login" {
        $results = Rename-DbaLogin -SqlInstance $script:instance1 -Login $login -NewLogin $renamed
        $results.Status -eq "Successful"
        $results.PreviousLogin = $login
        $results.NewLogin = $renamed
        $login1 = Get-Dbalogin -SqlInstance $script:instance1 -login $renamed
        $null -ne $login1
    }
}