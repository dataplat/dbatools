$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Certificate', 'InputObject', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can remove a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }
        }
        AfterAll {
            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey -Confirm:$false }
        }

        $results = New-DbaDbCertificate -SqlInstance $script:instance1 -Confirm:$false | Remove-DbaDbCertificate -Confirm:$false

        It "Successfully removes database certificate in master" {
            "$($results.Status)" -match 'Success' | Should Be $true
        }
    }
}