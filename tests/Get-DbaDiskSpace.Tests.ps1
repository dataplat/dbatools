$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandName Integration Tests" -Tags "IntegrationTests" {
    Context "Disks are properly retrieved" {
        $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME
        It "returns at least the system drive" {
            $results.Name -contains "$env:SystemDrive\" | Should Be $true
        }

        $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME | Where-Object Name -eq "$env:SystemDrive\"
        It "has some valid properties" {
            $results.BlockSize -gt 0 | Should Be $true
            $results.SizeInGB -gt 0 | Should Be $true
        }
    }

    Context "CheckForSql returns IsSqlDisk property with a value (likely false)" {
        $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME -CheckForSql -WarningAction SilentlyContinue
            It "SQL Server drive is not found in there somewhere" {
                $false | Should BeIn $results.IsSqlDisk
            }
        }
}