$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'ServerProduct', 'Provider', 'DataSource', 'Location', 'ProviderString', 'Catalog', 'InputObject', 'EnableException'
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
    }
    AfterAll {
        if ($instance2.LinkedServers.Name -contains "LS1_$random") {
            $instance2.LinkedServers["LS1_$random"].Drop()
        }

        if ($instance2.LinkedServers.Name -contains "LS2_$random") {
            $instance2.LinkedServers["LS2_$random"].Drop()
        }
    }

    Context "ensure command works" {

        It "Creates a linked server" {
            $results = New-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer "LS1_$random" -ServerProduct product1 -Provider provider1 -DataSource dataSource1 -Location location1 -ProviderString providerString1 -Catalog catalog1
            $results.Parent.Name | Should -Be $instance2.Name
            $results.Name | Should -Be "LS1_$random"
            $results.ProductName | Should -Be product1
            $results.ProviderName | Should -Be provider1
            $results.DataSource | Should -Be dataSource1
            $results.Location | Should -Be location1
            $results.ProviderString | Should -Be providerString1
            $results.Catalog | Should -Be catalog1
        }

        It "Check the validation for duplicate linked servers" {
            $results = New-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer "LS1_$random"
            $results | Should -BeNullOrEmpty
        }

        It "Creates a linked server using a server from a pipeline" {
            $results = $instance2 | New-DbaLinkedServer -LinkedServer "LS2_$random" -ServerProduct product2 -Provider provider2 -DataSource dataSource2 -Location location2 -ProviderString providerString2 -Catalog catalog2
            $results.Parent.Name | Should -Be $instance2.Name
            $results.Name | Should -Be "LS2_$random"
            $results.ProductName | Should -Be product2
            $results.ProviderName | Should -Be provider2
            $results.DataSource | Should -Be dataSource2
            $results.Location | Should -Be location2
            $results.ProviderString | Should -Be providerString2
            $results.Catalog | Should -Be catalog2
        }
    }
}