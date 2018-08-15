$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $commonParamCount = ([System.Management.Automation.PSCmdlet]::CommonParameters).Count + 2
        [object[]]$params = (Get-ChildItem function:\Install-DbaFirstResponderKit).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Branch', 'Database', 'Force', 'LocalFile', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $commonParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing First Responder Kit installer" {
        BeforeAll {
            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $database")
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $database -Confirm:$false
        }

        $results = Install-DbaFirstResponderKit -SqlInstance $script:instance2 -Database $database -Branch master -Force

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should Be $true
        }
        It "Shows status of Installed" {
            $results[0].Status -eq "Installed" | Should Be $true
        }
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            'sp_Blitz', 'sp_BlitzIndex' | Should BeIn $results.Name
        }
        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
    }
}