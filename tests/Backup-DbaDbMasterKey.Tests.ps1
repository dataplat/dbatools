$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'Database', 'ExcludeDatabase', 'SecurePassword', 'Path', 'InputObject', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }
        }
        AfterAll {
            (Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb) | Remove-DbaDbMasterKey -Confirm:$false
        }

        $results = Backup-DbaDbMasterKey -SqlInstance $script:instance1 -Confirm:$false -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
        $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

        It "backs up the db cert" {
            $results.Database -eq 'tempdb'
            $results.Status -eq "Success"
        }
    }
}