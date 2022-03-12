$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemDatabase', 'IncludePublicGuest', 'IncludeSystemObjects', 'ExcludeSecurables', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns proper info" {
        $dbName = "dbatoolsci_UserPermission"
        $sql = @'
create user alice without login;
create user bob without login;
create role userrole AUTHORIZATION dbo;
exec sp_addrolemember 'userrole','alice';
exec sp_addrolemember 'userrole','bob';
'@

        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbName
        $db.ExecuteNonQuery($sql)

        $results = Get-DbaUserPermission -SqlInstance $script:instance1 -Database $dbName

        $null = Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbName -Confirm:$false

        It "returns results" {
            $results.Count -gt 0 | Should Be $true
        }

        foreach ($result in $results) {
            It "returns only $dbName or server results" {
                $result.Object | Should -BeIn $dbName, 'SERVER'
            }
            if ($result.Object -eq $dbName -and $result.RoleSecurableClass -eq 'DATABASE') {
                It "returns correct securable" {
                    $result.Securable | Should Be $dbName
                }
            }
        }
    }
}