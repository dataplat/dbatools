$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Operation', 'InputValue', 'NoInformationalMessages', 'MarkInUseForRemoval', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Operation', 'Cmd', 'Output'
    $result = Invoke-DbaDbccFreeCache -SqlInstance $script:instance2 -Operation FreeSystemCache -Confirm:$false

    Context "Validate standard output" {
        foreach ($prop in $props) {
            $p = $result.PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
    }

    Context "Works correctly" {
        It "returns the right results for FREESYSTEMCACHE" {
            $result.Operation -match 'FREESYSTEMCACHE' | Should Be $true
            $result.Output -match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.' | Should Be $true
        }

        It "returns the right results for FREESESSIONCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $script:instance2 -Operation FreeSessionCache -Confirm:$false
            $result.Operation -match 'FREESESSIONCACHE' | Should Be $true
            $result.Output -match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.' | Should Be $true
        }

        It "returns the right results for FREEPROCCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $script:instance2 -Operation FREEPROCCACHE -Confirm:$false
            $result.Operation -match 'FREEPROCCACHE' | Should Be $true
            $result.Output -match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.' | Should Be $true
        }

        It "returns the right results for FREESESSIONCACHE and using NoInformationalMessages" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $script:instance2 -Operation FreeSessionCache -NoInformationalMessages -Confirm:$false
            $result.Operation -match 'FREESESSIONCACHE' | Should Be $true
            $result.Output | Should Be $null
        }
    }

}