$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SecurePassword', 'InputObject', 'Path', 'FilePath', 'Type', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Certificate is added properly" {
        $null = Add-DbaComputerCertificate -Path $script:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
        It "returns the proper results" {
            $result = Get-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 | Backup-DbaComputerCertificate -Path C:\temp
            $result.Name -match '29C469578D6C6211076A09CEE5C5797EEA0C2713.cer'
        }
        $null = Remove-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 -Confirm:$false
    }
}