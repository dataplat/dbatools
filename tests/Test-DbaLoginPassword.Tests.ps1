$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Get-PasswordHash.ps1"

Describe "$CommandName Unit Tests" -Tag UnitTests, Get-DbaLogin {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'Dictionary', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $weaksauce = "dbatoolsci_testweak"
        $weakpass = ConvertTo-SecureString $weaksauce -AsPlainText -Force
        $newlogin = New-DbaLogin -SqlInstance $TestConfig.instance1 -Login $weaksauce -HashedPassword (Get-PasswordHash $weakpass $server.VersionMajor) -Force
    }
    AfterAll {
        try {
            $newlogin.Drop()
        } catch {
            # don't care
        }
    }

    Context "making sure command works" {
        It "finds the new weak password and supports piping" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.instance1 | Test-DbaLoginPassword
            $results.SqlLogin | Should -Contain $weaksauce
        }
        It "returns just one login" {
            $results = Test-DbaLoginPassword -SqlInstance $TestConfig.instance1 -Login $weaksauce
            $results.SqlLogin | Should -Be $weaksauce
        }
        It "handles passwords with quotes, see #9095" {
            $results = Test-DbaLoginPassword -SqlInstance $TestConfig.instance1 -Login $weaksauce -Dictionary "&é`"'(-", "hello"
            $results.SqlLogin | Should -Be $weaksauce
        }
    }
}
