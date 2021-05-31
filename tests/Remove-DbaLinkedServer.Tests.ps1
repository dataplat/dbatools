$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2

        $instance2.Query("EXEC sp_addlinkedserver @server=N'LS1_$random'")
        $instance2.Query("EXEC sp_addlinkedserver @server=N'LS2_$random'")
        $instance2.Query("EXEC sp_addlinkedserver @server=N'LS3_$random'")

        $ls1 = Get-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "LS1_$random"
        $ls2 = Get-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "LS2_$random"
        $ls3 = Get-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "LS3_$random"
    }
    AfterAll {
        if ($instance2.LinkedServers.Name -contains "LS1_$random") {
            $instance2.LinkedServers["LS1_$random"].Drop()
        }

        if ($instance2.LinkedServers.Name -contains "LS2_$random") {
            $instance2.LinkedServers["LS2_$random"].Drop()
        }

        if ($instance2.LinkedServers.Name -contains "LS3_$random") {
            $instance2.LinkedServers["LS3_$random"].Drop()
        }
    }

    Context "ensure command works" {

        It "Removes a linked server" {
            $results = Get-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "LS1_$random"
            $results.Length | Should -Be 1
            Remove-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer "LS1_$random" -Confirm:$false
            $results = Get-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "LS1_$random"
            $results | Should -BeNullOrEmpty
        }

        It "Tries to remove a non-existent linked server" {
            Remove-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer "LS1_$random" -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Linked server LS1_$random does not exist on $($instance2.Name)"
        }

        It "Removes a linked server using a server from a pipeline and a linked server from a pipeline" {
            $results = Get-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer "LS2_$random"
            $results.Length | Should -Be 1
            $ls2 | Remove-DbaLinkedServer -Confirm:$false
            $results = Get-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "LS2_$random"
            $results | Should -BeNullOrEmpty

            $results = Get-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer "LS3_$random"
            $results.Length | Should -Be 1
            $instance2 | Remove-DbaLinkedServer -LinkedServer "LS3_$random" -Confirm:$false
            $results = Get-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "LS3_$random"
            $results | Should -BeNullOrEmpty
        }
    }
}