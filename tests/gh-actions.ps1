Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $PSDefaultParameterValues["*:SqlInstance"] = "localhost"
        $PSDefaultParameterValues["*:Source"] = "localhost"
        $PSDefaultParameterValues["*:Destination"] = "localhost:14333"
        $PSDefaultParameterValues["*:Primary"] = "localhost"
        $PSDefaultParameterValues["*:Mirror"] = "localhost:14333"
        $PSDefaultParameterValues["*:SqlCredential"] = $cred
        $PSDefaultParameterValues["*:SourceSqlCredential"] = $cred
        $PSDefaultParameterValues["*:DestinationSqlCredential"] = $cred
        $PSDefaultParameterValues["*:PrimarySqlCredential"] = $cred
        $PSDefaultParameterValues["*:MirrorSqlCredential"] = $cred
        $PSDefaultParameterValues["*:WitnessSqlCredential"] = $cred
        $PSDefaultParameterValues["*:Confirm"] = $false
        $PSDefaultParameterValues["*:SharedPath"] = "/shared"
        $global:ProgressPreference = "SilentlyContinue"

        Import-Module ./dbatools.psm1 -Force
        $null = Get-XPlatVariable | Where-Object { $PSItem -notmatch "Copy-", "Migration" } | Sort-Object
    }

    It "migrates" {
        $params = @{
            BackupRestore = $true
            Exclude       = "LinkedServers", "Credentials", "DataCollector", "EndPoints", "PolicyManagement", "ResourceGovernor", "BackupDevices"
        }

        $results = Start-DbaMigration @params
        $results.Name | Should -Contain "Northwind"
    }

    It "sets up a mirror" {
        $newdb = New-DbaDatabase
        $params = @{
            Database      = $newdb.Name
            Force         = $true
            WarningAction = "SilentlyContinue"
        }

        Invoke-DbaDbMirroring @params | Select-Object -ExpandProperty Status | Should -Be "Success"
        Get-DbaDbMirror | Select-Object -ExpandProperty MirroringPartner | Should -Be "TCP://dockersql2:5022"
    }

    It "gets some permissions" {
        $results = Get-DbaUserPermission -Database "Northwind"
        foreach ($result in $results) {
            $results.Object -in "SERVER", "Northwind"
        }
    }

    It "attempts to balance" {
        $results = Invoke-DbaBalanceDataFiles -Database "Northwind" -Force
        $results.Database | Should -Be "Northwind"
    }
}