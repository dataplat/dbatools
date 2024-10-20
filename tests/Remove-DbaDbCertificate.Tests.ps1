$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Certificate', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can remove a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }
        }
        AfterAll {
            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey -Confirm:$false }
        }

        $results = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Confirm:$false | Remove-DbaDbCertificate -Confirm:$false

        It "Successfully removes database certificate in master" {
            "$($results.Status)" -match 'Success' | Should Be $true
        }
    }
}
