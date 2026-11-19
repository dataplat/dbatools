#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXEStore",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "$CommandName native object contract" -Tag IntegrationTests {
    BeforeAll {
        $splatStoreConnection = @{
            SqlInstance     = $TestConfig.InstanceSingle
            SqlCredential   = $TestConfig.SqlCred
            EnableException = $true
        }
        $xeStoreServer = Connect-DbaInstance @splatStoreConnection
        $xeStoreSessionTable = $xeStoreServer.ConnectionContext.ExecuteWithResults("SELECT name FROM sys.server_event_sessions ORDER BY name").Tables[0]
        $xeStorePackageTable = $xeStoreServer.ConnectionContext.ExecuteWithResults("SELECT module_guid, name FROM sys.dm_xe_packages WHERE (capabilities & 1) = 0 OR capabilities IS NULL").Tables[0]
        $xeStoreSessionNames = @($xeStoreSessionTable.Rows | ForEach-Object { [string]$PSItem.name } | Sort-Object)
        $xeStorePackageKeys = @($xeStorePackageTable.Rows | ForEach-Object { "{0}|{1}" -f ([guid]$PSItem.module_guid).ToString("D"), [string]$PSItem.name } | Sort-Object)
        $xeStoreDisplay = "ComputerName,InstanceName,SqlInstance,ServerName,Sessions,Packages,RunningSessionCount"
    }

    It "Returns a live store with exact instance notes and default display" {
        $xeStoreResults = @(Get-DbaXEStore -SqlInstance $xeStoreServer -EnableException)
        $xeStoreResults.Count | Should -Be 1
        $xeStoreResult = $xeStoreResults[0]
        $xeStoreResult.GetType().FullName | Should -Be "Microsoft.SqlServer.Management.XEvent.XEStore"
        $xeStoreResult.ComputerName | Should -Be $xeStoreServer.ComputerName
        $xeStoreResult.InstanceName | Should -Be $xeStoreServer.ServiceName
        $xeStoreResult.SqlInstance | Should -Be $xeStoreServer.DomainInstanceName
        ($xeStoreResult.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $xeStoreDisplay
        @($xeStoreResult.Sessions | ForEach-Object Name | Sort-Object) | Should -Be $xeStoreSessionNames
        $xeStoreActualPackages = @($xeStoreResult.Packages)
        $xeStoreActualPackageKeys = @($xeStoreActualPackages | ForEach-Object { "{0}|{1}" -f $PSItem.ModuleID.ToString("D"), [string]$PSItem.Name } | Sort-Object)
        $xeStoreActualPackages.Count | Should -Be $xeStorePackageTable.Rows.Count
        $xeStoreActualPackageKeys | Should -Be $xeStorePackageKeys
        $xeStoreResult.RunningSessionCount | Should -BeGreaterOrEqual 0
    }

    It "Returns one distinct live store for each duplicate array input" {
        $xeStoreArray = @(Get-DbaXEStore -SqlInstance $xeStoreServer, $xeStoreServer -EnableException)
        $xeStoreArray.Count | Should -Be 2
        [object]::ReferenceEquals($xeStoreArray[0], $xeStoreArray[1]) | Should -BeFalse
        @($xeStoreArray.SqlInstance) | Should -Be @($xeStoreServer.DomainInstanceName, $xeStoreServer.DomainInstanceName)
    }

    It "Processes two pipeline input records independently" {
        $xeStorePipeline = @(@($xeStoreServer, $xeStoreServer) | Get-DbaXEStore -EnableException)
        $xeStorePipeline.Count | Should -Be 2
        @($xeStorePipeline.SqlInstance) | Should -Be @($xeStoreServer.DomainInstanceName, $xeStoreServer.DomainInstanceName)
        foreach ($xeStorePipelineItem in $xeStorePipeline) {
            $xeStorePipelineItem.GetType().FullName | Should -Be "Microsoft.SqlServer.Management.XEvent.XEStore"
        }
    }
}
