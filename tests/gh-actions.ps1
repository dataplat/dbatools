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
        $PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
        $global:ProgressPreference = "SilentlyContinue"

        $psm1Path = [IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'src','dbatools.psm1')
        Import-Module $psm1Path -Force
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
            Database = $newdb.Name
            Force    = $true
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

    It "converts to an XE Session" {
        $sql = "-- Create a Queue
                declare @rc int
                declare @TraceID int
                declare @maxfilesize bigint
                set @maxfilesize = 5
                exec @rc = sp_trace_create @TraceID output, 0, N'/tmp/', @maxfilesize, NULL

                -- Set the events
                declare @on bit
                set @on = 1
                exec sp_trace_setevent @TraceID, 14, 1, @on
                exec sp_trace_setevent @TraceID, 14, 9, @on
                exec sp_trace_setevent @TraceID, 14, 10, @on
                exec sp_trace_setevent @TraceID, 14, 11, @on
                exec sp_trace_setevent @TraceID, 14, 6, @on
                exec sp_trace_setevent @TraceID, 14, 12, @on
                exec sp_trace_setevent @TraceID, 14, 14, @on
                exec sp_trace_setevent @TraceID, 15, 11, @on
                exec sp_trace_setevent @TraceID, 15, 6, @on
                exec sp_trace_setevent @TraceID, 15, 9, @on
                exec sp_trace_setevent @TraceID, 15, 10, @on
                exec sp_trace_setevent @TraceID, 15, 12, @on
                exec sp_trace_setevent @TraceID, 15, 13, @on
                exec sp_trace_setevent @TraceID, 15, 14, @on
                exec sp_trace_setevent @TraceID, 15, 15, @on
                exec sp_trace_setevent @TraceID, 15, 16, @on
                exec sp_trace_setevent @TraceID, 15, 17, @on
                exec sp_trace_setevent @TraceID, 15, 18, @on
                exec sp_trace_setevent @TraceID, 17, 1, @on
                exec sp_trace_setevent @TraceID, 17, 9, @on
                exec sp_trace_setevent @TraceID, 17, 10, @on
                exec sp_trace_setevent @TraceID, 17, 11, @on
                exec sp_trace_setevent @TraceID, 17, 6, @on
                exec sp_trace_setevent @TraceID, 17, 12, @on
                exec sp_trace_setevent @TraceID, 17, 14, @on
                exec sp_trace_setevent @TraceID, 10, 9, @on
                exec sp_trace_setevent @TraceID, 10, 2, @on
                exec sp_trace_setevent @TraceID, 10, 10, @on
                exec sp_trace_setevent @TraceID, 10, 6, @on
                exec sp_trace_setevent @TraceID, 10, 11, @on
                exec sp_trace_setevent @TraceID, 10, 12, @on
                exec sp_trace_setevent @TraceID, 10, 13, @on
                exec sp_trace_setevent @TraceID, 10, 14, @on
                exec sp_trace_setevent @TraceID, 10, 15, @on
                exec sp_trace_setevent @TraceID, 10, 16, @on
                exec sp_trace_setevent @TraceID, 10, 17, @on
                exec sp_trace_setevent @TraceID, 10, 18, @on
                exec sp_trace_setevent @TraceID, 12, 1, @on
                exec sp_trace_setevent @TraceID, 12, 9, @on
                exec sp_trace_setevent @TraceID, 12, 11, @on
                exec sp_trace_setevent @TraceID, 12, 6, @on
                exec sp_trace_setevent @TraceID, 12, 10, @on
                exec sp_trace_setevent @TraceID, 12, 12, @on
                exec sp_trace_setevent @TraceID, 12, 13, @on
                exec sp_trace_setevent @TraceID, 12, 14, @on
                exec sp_trace_setevent @TraceID, 12, 15, @on
                exec sp_trace_setevent @TraceID, 12, 16, @on
                exec sp_trace_setevent @TraceID, 12, 17, @on
                exec sp_trace_setevent @TraceID, 12, 18, @on
                exec sp_trace_setevent @TraceID, 13, 1, @on
                exec sp_trace_setevent @TraceID, 13, 9, @on
                exec sp_trace_setevent @TraceID, 13, 11, @on
                exec sp_trace_setevent @TraceID, 13, 6, @on
                exec sp_trace_setevent @TraceID, 13, 10, @on
                exec sp_trace_setevent @TraceID, 13, 12, @on
                exec sp_trace_setevent @TraceID, 13, 14, @on

                -- Set the Filters
                declare @intfilter int
                declare @bigintfilter bigint

                exec sp_trace_setfilter @TraceID, 10, 0, 7, N'SQL Server Profiler - 934a8575-0dc1-4937-bde1-edac1cb9691f'
                -- Set the trace status to start
                exec sp_trace_setstatus @TraceID, 1

                -- display trace id for future references
                select TraceID=@TraceID"
        $server = Connect-DbaInstance
        $traceid = ($server.Query($sql)).TraceID

        $null = Get-DbaTrace -Id $traceid | ConvertTo-DbaXESession -Name "dbatoolsci-session"
        $results = Start-DbaXESession -Session "dbatoolsci-session"
        $results.Name | Should -Be "dbatoolsci-session"
        $results.Status | Should -Be "Running"
        $results.Targets.Name | Should -Be "package0.event_file"
    }

    It "installs darling data" {
        $results = Install-DbaDarlingData
        $results.Database | Select-Object -First 1 | Should -Be "master"
    }

    It "tests the instance name" {
        $results = Test-DbaInstanceName
        $results.RenameRequired | Should -Be $true
    }

    It "creates a new database user" {
        $results = New-DbaDbUser -Database msdb -Username sqladmin -IncludeSystem
        $results.Name | Should -Be sqladmin
    }

    It "returns some permission" {
        Get-DbaPermission -Database tempdb | Should -Not -Be $null
    }

    # Takes two minutes in GH, very boring
    It -Skip "returns the master key" {
        (Get-DbaDbMasterKey).Database | Should -Be "master"
    }

    It "stops an xe session" {
        (Stop-DbaXESession -Session "dbatoolsci-session").Name | Should -Be "dbatoolsci-session"
    }

    It "tests tempdb configs" {
        (Test-DbaTempDbConfig).Rule | Should -Contain "File Growth in Percent"
    }

    It "creates a snapshot" {
        (New-DbaDbSnapshot -Database pubs).SnapshotOf | Should -Be "pubs"
    }

    It "connects to Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
        Connect-DbaInstance -SqlInstance "Server=dbatoolstest.database.windows.net; Authentication=Active Directory Service Principal; Database=test; User Id=$env:CLIENTID; Password=$env:CLIENTSECRET;" | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
    }
}


<#
# fails on newer version of SMO
'Invoke-DbaWhoisActive',
'Remove-DbaAvailabilityGroup',
'Set-DbaAgReplica',
'Read-DbaAuditFile',
'Sync-DbaLoginPermission',
'Read-DbaXEFile',
'Stop-DbaXESession',
'Test-DbaTempDbConfig',
'Watch-DbaDbLogin',
'Remove-DbaDatabaseSafely',
'Test-DbaManagementObject',
'Export-DbaDacPackage'
#>